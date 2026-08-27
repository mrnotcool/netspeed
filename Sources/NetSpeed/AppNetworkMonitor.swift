import Foundation
import AppKit
import Darwin

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
    
    private var timer: Timer?
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
    
    private init() {
        loadUsage()
        checkAndResetCycles()
        
        // One-time recalibration to clear corrupted development restart inflation
        if !defaults.bool(forKey: recalibratedKey) {
            resetMonth(startDate: startOfMonth(containing: Date()))
            defaults.set(true, forKey: recalibratedKey)
        }
    }
    
    func startMonitoring() {
        guard timer == nil else { return }
        // Use RunLoop.main with mode .common so timer continues firing during menu interaction
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollNettopAsync()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        
        // Initial poll
        pollNettopAsync()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
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

    private func isXiaohongshu(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "小红书" || lower == "discover" || lower == "rednote" || lower == "redmote"
    }

    private func getParentPID(pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        if result == size {
            return Int32(info.pbi_ppid)
        }
        return nil
    }

    private func getExecutablePath(pid: Int32) -> String? {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        defer { buffer.deallocate() }
        let ret = proc_pidpath(pid, buffer, UInt32(MAXPATHLEN))
        if ret > 0 {
            return String(cString: buffer)
        }
        return nil
    }

    func findAppIcon(appName: String, pid: Int32 = 0) -> NSImage {
        let lower = appName.lowercased()

        // 1. Direct pid running app check
        if pid > 0, let runningApp = NSRunningApplication(processIdentifier: pid), let icon = runningApp.icon {
            return icon
        }
        
        // 2. Parent PID chain lookup
        if pid > 0 {
            var currentPID = pid
            var depth = 0
            while depth < 5 && currentPID > 1 {
                if let app = NSRunningApplication(processIdentifier: currentPID), let icon = app.icon {
                    return icon
                }
                guard let ppid = getParentPID(pid: currentPID) else { break }
                currentPID = ppid
                depth += 1
            }
        }
        
        // 3. Executable path inspection
        if pid > 0, let execPath = getExecutablePath(pid: pid) {
            let components = execPath.components(separatedBy: "/")
            if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                let appPath = "/" + components[1...appIndex].joined(separator: "/")
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }
        
        // 4. Running apps matching by localizedName
        for app in NSWorkspace.shared.runningApplications {
            if let locName = app.localizedName {
                let locLower = locName.lowercased()
                if locLower == lower || (isXiaohongshu(lower) && isXiaohongshu(locLower)) {
                    if let icon = app.icon {
                        return icon
                    }
                }
            }
        }
        
        // 5. Search /Applications, /System/Applications, ~/Applications for matching .app
        let fileManager = FileManager.default
        let searchDirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "\(NSHomeDirectory())/Applications"]
        for dir in searchDirs {
            if let contents = try? fileManager.contentsOfDirectory(atPath: dir) {
                for item in contents {
                    if item.hasSuffix(".app") {
                        let nameWithoutExt = String(item.dropLast(4)).lowercased()
                        let isMatch = (nameWithoutExt == lower) || (isXiaohongshu(lower) && isXiaohongshu(nameWithoutExt))
                        if isMatch {
                            let fullPath = "\(dir)/\(item)"
                            return NSWorkspace.shared.icon(forFile: fullPath)
                        }
                    }
                }
            }
        }
        
        // 6. SF Symbol fallbacks based on process type
        let symbolName: String
        if lower.contains("system services") || lower == "kernel_task" || lower == "launchd" {
            symbolName = "wrench.and.screwdriver"
        } else if lower.contains("node") || lower.contains("zsh") || lower.contains("bash") || lower.contains("python") || lower.contains("server") {
            symbolName = "terminal"
        } else {
            symbolName = "gearshape"
        }
        
        if #available(macOS 11.0, *), let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            return symbolImage.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) ?? symbolImage
        }
        
        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
    }

    private func resolveAppInfo(pid: Int32, rawName: String) -> (name: String, icon: NSImage?) {
        // 1. Executable path inspection for top-level .app bundle (e.g. /Applications/Dia.app/...)
        if let execPath = getExecutablePath(pid: pid) {
            let components = execPath.components(separatedBy: "/")
            if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                let appBundleName = components[appIndex]
                let topAppName = String(appBundleName.dropLast(4))
                let name = (topAppName == "Browser Helper" || topAppName == "Browser Helper (Renderer)") ? "Dia" : topAppName
                let icon = findAppIcon(appName: name, pid: pid)
                return (name, icon)
            }
        }
        
        // 2. Check parent process chain (PPID) up to 5 levels
        var currentPID = pid
        var depth = 0
        while depth < 5 {
            if let parentApp = NSRunningApplication(processIdentifier: currentPID),
               let locName = parentApp.localizedName, !locName.isEmpty {
                let name = (locName == "Browser Helper" || locName == "Browser Helper (Renderer)") ? "Dia" : locName
                let icon = parentApp.icon ?? findAppIcon(appName: name, pid: currentPID)
                return (name, icon)
            }
            guard let ppid = getParentPID(pid: currentPID), ppid > 1 else { break }
            currentPID = ppid
            depth += 1
        }
        
        let name = (rawName == "Browser Helper" || rawName == "Browser Helper (Renderer)") ? "Dia" : rawName
        let icon = findAppIcon(appName: name, pid: pid)
        return (name, icon)
    }
    
    private func pollNettopAsync() {
        guard !isPolling else { return }
        isPolling = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            task.arguments = ["-P", "-L", "1", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]
            
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
                var currentRealtimeSpeeds: [String: Double] = [:]
                var deltasPerApp: [String: UInt64] = [:]
                var resolvedIcons: [String: NSImage] = [:]
                
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix(",") || trimmed.hasPrefix("bytes_in") {
                        continue
                    }
                    
                    let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                    if parts.count >= 3 {
                        let nameAndPid = String(parts[0])
                        guard let bytesIn = UInt64(parts[1]),
                              let bytesOut = UInt64(parts[2]) else {
                            continue
                        }
                        
                        if let lastDotIndex = nameAndPid.lastIndex(of: ".") {
                            let rawName = String(nameAndPid[..<lastDotIndex])
                            let pidStr = String(nameAndPid[nameAndPid.index(after: lastDotIndex)...])
                            if let pid = Int32(pidStr) {
                                currentProcessBytes[pid] = (bytesIn, bytesOut)
                                
                                var deltaTotal: UInt64 = 0
                                var speedDelta: UInt64 = 0
                                
                                if let prev = self.previousProcessBytes[pid] {
                                    let deltaIn = bytesIn >= prev.inBytes ? bytesIn - prev.inBytes : 0
                                    let deltaOut = bytesOut >= prev.outBytes ? bytesOut - prev.outBytes : 0
                                    deltaTotal = deltaIn + deltaOut
                                    speedDelta = deltaTotal
                                } else {
                                    // First time seeing PID: establish baseline only, do not add historical lifetime bytes!
                                    deltaTotal = 0
                                    speedDelta = 0
                                }
                                
                                let (appName, appIcon) = self.resolveAppInfo(pid: pid, rawName: rawName)
                                if let appIcon = appIcon {
                                    resolvedIcons[appName] = appIcon
                                }
                                
                                let speed = Double(speedDelta) / elapsed
                                currentRealtimeSpeeds[appName, default: 0.0] += speed
                                deltasPerApp[appName, default: 0] += deltaTotal
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.checkAndResetCycles()
                    self.previousProcessBytes = currentProcessBytes
                    self.previousTime = now
                    self.realtimeSpeeds = currentRealtimeSpeeds
                    
                    for (k, v) in resolvedIcons {
                        if self.appIcons[k] == nil {
                            self.appIcons[k] = v
                        }
                    }
                    
                    var updatedUsage = false
                    for (appName, delta) in deltasPerApp {
                        if delta > 0 {
                            self.dailyUsage[appName, default: 0] += delta
                            self.monthlyUsage[appName, default: 0] += delta
                            updatedUsage = true
                        }
                    }
                    if updatedUsage {
                        let totalDelta = deltasPerApp.values.reduce(UInt64(0), +)
                        self.hourlyUsage[self.hourKey(for: now), default: 0] += totalDelta
                        self.saveUsage()
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
