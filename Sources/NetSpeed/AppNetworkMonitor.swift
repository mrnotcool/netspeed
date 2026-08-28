import Foundation
import AppKit

struct AppSpeedInfo {
    let name: String
    let icon: NSImage?
    let bytesPerSec: Double
}

struct AppTrafficInfo {
    let name: String
    let icon: NSImage?
    let totalBytes: UInt64
}

enum TrafficRange {
    case today
    case month
}

struct TrafficChartPoint {
    let date: Date
    let totalBytes: UInt64
}

final class AppNetworkMonitor {
    static let shared = AppNetworkMonitor()

    private static let systemServicesName = ProcessIdentityResolver.systemServicesDisplayName
    private let identityResolver = ProcessIdentityResolver()
    
    private var timer: Timer?
    private var pollingInterval: TimeInterval = 3
    private var previousProcessBytes: [Int32: (inBytes: UInt64, outBytes: UInt64)] = [:]
    private var previousTime: Date = Date()
    private var isPolling = false
    
    // App Name -> Real-time Speed (Bytes / sec)
    private(set) var realtimeSpeeds: [String: Double] = [:]
    // App Name -> App Icon
    private(set) var appIcons: [String: NSImage] = [:]
    // App Name -> Current Calendar Month Cumulative Bytes
    private(set) var monthlyUsage: [String: UInt64] = [:]
    // App Name -> Today's Cumulative Bytes
    private(set) var dailyUsage: [String: UInt64] = [:]
    // Local hour start timestamp -> Cumulative Bytes
    private var hourlyUsage: [String: UInt64] = [:]
    
    private let defaults = UserDefaults.standard
    private let cycleStartDateKey = "NetSpeed_CycleStartDate"
    private let monthlyUsageKey = "NetSpeed_MonthlyUsage"
    private let monthStartDateKey = "NetSpeed_MonthStartDate_V3"
    private let dayStartDateKey = "NetSpeed_DayStartDate_V3"
    private let dailyUsageKey = "NetSpeed_DailyUsage_V3"
    private let hourlyUsageKey = "NetSpeed_HourlyUsage_V3"
    private let recalibratedKey = "NetSpeed_Recalibrated_V2"
    private let calendar = Calendar.autoupdatingCurrent
    private let usageSaveInterval: TimeInterval = 15
    private var usageDirty = false
    private var lastUsageSaveDate = Date.distantPast

    private init() {
        loadUsage()
        checkAndResetCycles()
        
        // One-time recalibration to clear corrupted development restart inflation
        if !defaults.bool(forKey: recalibratedKey) {
            resetMonth(startDate: startOfMonth(containing: Date()))
            defaults.set(true, forKey: recalibratedKey)
        }

        if migrateWrappedApplicationUsage() {
            saveUsage()
        }
    }
    
    func startMonitoring() {
        guard timer == nil else { return }
        installPollingTimer(interval: pollingInterval, pollImmediately: true)
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        saveUsageIfNeeded(at: Date(), force: true)
    }

    func setDashboardVisible(_ isVisible: Bool) {
        let interval: TimeInterval = isVisible ? 1 : 3
        guard interval != pollingInterval else { return }
        pollingInterval = interval
        guard timer != nil else { return }
        installPollingTimer(interval: interval, pollImmediately: isVisible)
    }

    private func installPollingTimer(interval: TimeInterval, pollImmediately: Bool) {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollNettopAsync()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        if pollImmediately {
            pollNettopAsync()
        }
    }
    
    private func checkAndResetCycles() {
        let now = Date()

        let currentMonthStart = startOfMonth(containing: now)
        if let savedMonthStart = defaults.object(forKey: monthStartDateKey) as? Date {
            if !calendar.isDate(savedMonthStart, equalTo: currentMonthStart, toGranularity: .month) {
                resetMonth(startDate: currentMonthStart)
            }
        } else if let legacyStart = defaults.object(forKey: cycleStartDateKey) as? Date,
                  calendar.isDate(legacyStart, equalTo: now, toGranularity: .month) {
            // Preserve an existing 30-day total when it already belongs to this calendar month.
            defaults.set(currentMonthStart, forKey: monthStartDateKey)
        } else {
            resetMonth(startDate: currentMonthStart)
        }

        let currentDayStart = calendar.startOfDay(for: now)
        if let savedDayStart = defaults.object(forKey: dayStartDateKey) as? Date,
           calendar.isDate(savedDayStart, inSameDayAs: currentDayStart) {
            // The current daily bucket is still valid.
        } else {
            resetDay(startDate: currentDayStart)
        }

        pruneHourlyUsage(before: currentMonthStart)
    }

    private func startOfMonth(containing date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func resetMonth(startDate: Date) {
        defaults.set(startDate, forKey: monthStartDateKey)
        defaults.set(startDate, forKey: cycleStartDateKey)
        monthlyUsage.removeAll()
        defaults.set([String: String](), forKey: monthlyUsageKey)
        pruneHourlyUsage(before: startDate)
    }

    private func resetDay(startDate: Date) {
        defaults.set(startDate, forKey: dayStartDateKey)
        dailyUsage.removeAll()
        defaults.set([String: String](), forKey: dailyUsageKey)
    }

    private func decodeUsage(forKey key: String) -> [String: UInt64] {
        guard let saved = defaults.dictionary(forKey: key) as? [String: String] else { return [:] }
        var usage: [String: UInt64] = [:]
        for (name, value) in saved {
            guard let bytes = UInt64(value) else { continue }
            let normalizedName = (name == "Browser Helper" || name == "Browser Helper (Renderer)") ? "Dia" : name
            usage[normalizedName, default: 0] += bytes
        }
        return usage
    }

    private func loadUsage() {
        monthlyUsage = decodeUsage(forKey: monthlyUsageKey)
        dailyUsage = decodeUsage(forKey: dailyUsageKey)
        hourlyUsage = decodeUsage(forKey: hourlyUsageKey)
    }

    private func encodeUsage(_ usage: [String: UInt64], forKey key: String) {
        var toSave: [String: String] = [:]
        for (name, bytes) in usage {
            toSave[name] = String(bytes)
        }
        defaults.set(toSave, forKey: key)
    }

    private func saveUsage() {
        encodeUsage(monthlyUsage, forKey: monthlyUsageKey)
        encodeUsage(dailyUsage, forKey: dailyUsageKey)
        encodeUsage(hourlyUsage, forKey: hourlyUsageKey)
        usageDirty = false
        lastUsageSaveDate = Date()
    }

    private func saveUsageIfNeeded(at date: Date, force: Bool = false) {
        guard usageDirty,
              force || date.timeIntervalSince(lastUsageSaveDate) >= usageSaveInterval else { return }
        saveUsage()
    }

    private func hourKey(for date: Date) -> String {
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return String(Int(hourStart.timeIntervalSince1970))
    }

    private func pruneHourlyUsage(before cutoff: Date) {
        let cutoffTimestamp = Int(cutoff.timeIntervalSince1970)
        hourlyUsage = hourlyUsage.filter { key, _ in
            guard let timestamp = Int(key) else { return false }
            return timestamp >= cutoffTimestamp
        }
    }

    private func migrateWrappedApplicationUsage() -> Bool {
        let aliases = identityResolver.wrappedApplicationAliases()
        guard !aliases.isEmpty else { return false }
        var didChange = false

        func migrate(_ usage: inout [String: UInt64]) {
            for existingName in Array(usage.keys) {
                guard let displayName = aliases[identityResolver.normalize(existingName)],
                      displayName != existingName,
                      let bytes = usage.removeValue(forKey: existingName) else { continue }
                usage[displayName, default: 0] += bytes
                didChange = true
            }
        }

        migrate(&dailyUsage)
        migrate(&monthlyUsage)
        return didChange
    }

    func findAppIcon(appName: String, pid: Int32 = 0) -> NSImage {
        identityResolver.icon(appName: appName, pid: pid)
    }

    private func resolveProcessIdentity(pid: Int32, rawName: String) -> ProcessIdentity {
        identityResolver.resolve(pid: pid, rawName: rawName)
    }

    private func mergePreviouslyRecordedSystemServices(_ processNames: Set<String>) -> Bool {
        var didChange = false

        for processName in processNames where processName != Self.systemServicesName {
            if let bytes = dailyUsage.removeValue(forKey: processName) {
                dailyUsage[Self.systemServicesName, default: 0] += bytes
                didChange = true
            }
            if let bytes = monthlyUsage.removeValue(forKey: processName) {
                monthlyUsage[Self.systemServicesName, default: 0] += bytes
                didChange = true
            }
            appIcons.removeValue(forKey: processName)
        }

        if !processNames.isEmpty {
            appIcons[Self.systemServicesName] = identityResolver.systemServicesIcon
        }
        return didChange
    }
    
    private func pollNettopAsync() {
        guard !isPolling else { return }
        isPolling = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            task.arguments = ["-P", "-L", "1", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                guard let output = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async { self.isPolling = false }
                    return
                }

                let now = Date()
                let elapsed = now.timeIntervalSince(self.previousTime)
                guard elapsed > 0 else {
                    DispatchQueue.main.async { self.isPolling = false }
                    return
                }

                var currentProcessBytes: [Int32: (inBytes: UInt64, outBytes: UInt64)] = [:]
                var speedsByIdentity: [String: Double] = [:]
                var deltasByIdentity: [String: UInt64] = [:]
                var resolvedIdentities: [String: ProcessIdentity] = [:]
                var systemServiceProcessNames: Set<String> = []

                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix(",") || trimmed.hasPrefix("bytes_in") {
                        continue
                    }

                    let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                    guard parts.count >= 3,
                          let bytesIn = UInt64(parts[1]),
                          let bytesOut = UInt64(parts[2]) else { continue }

                    let nameAndPID = String(parts[0])
                    guard let lastDotIndex = nameAndPID.lastIndex(of: "."),
                          let pid = Int32(nameAndPID[nameAndPID.index(after: lastDotIndex)...]) else { continue }

                    let rawName = String(nameAndPID[..<lastDotIndex])
                    currentProcessBytes[pid] = (bytesIn, bytesOut)

                    let previous = self.previousProcessBytes[pid]
                    let deltaIn = previous.map { bytesIn >= $0.inBytes ? bytesIn - $0.inBytes : 0 } ?? 0
                    let deltaOut = previous.map { bytesOut >= $0.outBytes ? bytesOut - $0.outBytes : 0 } ?? 0
                    let deltaTotal = deltaIn + deltaOut

                    let identity = self.resolveProcessIdentity(pid: pid, rawName: rawName)
                    resolvedIdentities[identity.stableID] = identity
                    if identity.category == .systemServices {
                        systemServiceProcessNames.insert(rawName)
                    }

                    speedsByIdentity[identity.stableID, default: 0] += Double(deltaTotal) / elapsed
                    deltasByIdentity[identity.stableID, default: 0] += deltaTotal
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.checkAndResetCycles()
                    self.previousProcessBytes = currentProcessBytes
                    self.previousTime = now

                    var currentRealtimeSpeeds: [String: Double] = [:]
                    var deltasPerApp: [String: UInt64] = [:]
                    var resolvedIcons: [String: NSImage] = [:]
                    for (stableID, identity) in resolvedIdentities {
                        currentRealtimeSpeeds[identity.displayName, default: 0] += speedsByIdentity[stableID, default: 0]
                        deltasPerApp[identity.displayName, default: 0] += deltasByIdentity[stableID, default: 0]
                        resolvedIcons[identity.displayName] = identity.icon
                    }
                    self.realtimeSpeeds = currentRealtimeSpeeds

                    for (name, icon) in resolvedIcons where self.appIcons[name] == nil {
                        self.appIcons[name] = icon
                    }

                    let migratedSystemServices = self.mergePreviouslyRecordedSystemServices(
                        systemServiceProcessNames
                    )

                    var updatedUsage = false
                    for (appName, delta) in deltasPerApp where delta > 0 {
                        self.dailyUsage[appName, default: 0] += delta
                        self.monthlyUsage[appName, default: 0] += delta
                        updatedUsage = true
                    }
                    if updatedUsage {
                        let totalDelta = deltasPerApp.values.reduce(UInt64(0), +)
                        self.hourlyUsage[self.hourKey(for: now), default: 0] += totalDelta
                    }
                    if updatedUsage || migratedSystemServices {
                        self.usageDirty = true
                        self.saveUsageIfNeeded(at: now)
                    }
                    self.isPolling = false
                }
            } catch {
                DispatchQueue.main.async { self.isPolling = false }
            }
        }
    }
    
    func topRealtimeApps(limit: Int = 5) -> [AppSpeedInfo] {
        let sorted = realtimeSpeeds.map { (name, speed) in
            let icon = appIcons[name] ?? findAppIcon(appName: name)
            return AppSpeedInfo(name: name, icon: icon, bytesPerSec: speed)
        }.sorted { $0.bytesPerSec > $1.bytesPerSec }
        
        return Array(sorted.prefix(limit))
    }
    
    func topMonthlyApps(limit: Int = 5) -> [AppTrafficInfo] {
        topTrafficApps(range: .month, limit: limit)
    }

    func topTrafficApps(range: TrafficRange, limit: Int = 5) -> [AppTrafficInfo] {
        checkAndResetCycles()
        let source = range == .today ? dailyUsage : monthlyUsage
        let sorted = source.map { (name, total) in
            let icon = appIcons[name] ?? findAppIcon(appName: name)
            return AppTrafficInfo(name: name, icon: icon, totalBytes: total)
        }.sorted { $0.totalBytes > $1.totalBytes }

        return Array(sorted.prefix(limit))
    }

    func trafficChartPoints(range: TrafficRange) -> [TrafficChartPoint] {
        checkAndResetCycles()
        let now = Date()

        switch range {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (0..<24).compactMap { offset in
                guard let date = calendar.date(byAdding: .hour, value: offset, to: start) else { return nil }
                return TrafficChartPoint(date: date, totalBytes: hourlyUsage[hourKey(for: date), default: 0])
            }

        case .month:
            let start = startOfMonth(containing: now)
            let dayCount = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            return (0..<dayCount).compactMap { dayOffset in
                guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: start),
                      let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

                let lowerBound = Int(dayStart.timeIntervalSince1970)
                let upperBound = Int(nextDay.timeIntervalSince1970)
                let total = hourlyUsage.reduce(UInt64(0)) { partial, entry in
                    guard let timestamp = Int(entry.key), timestamp >= lowerBound, timestamp < upperBound else {
                        return partial
                    }
                    return partial + entry.value
                }
                return TrafficChartPoint(date: dayStart, totalBytes: total)
            }
        }
    }
}
