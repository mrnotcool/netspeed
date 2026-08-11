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
    // App Name -> 30-Day Cumulative Bytes
    private(set) var monthlyUsage: [String: UInt64] = [:]
    
    private let defaults = UserDefaults.standard
    private let cycleStartDateKey = "NetSpeed_CycleStartDate"
    private let monthlyUsageKey = "NetSpeed_MonthlyUsage"
    
    private init() {
        loadMonthlyUsage()
        checkAndResetCycle()
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
    
    private func checkAndResetCycle() {
        let now = Date()
        if let startDate = defaults.object(forKey: cycleStartDateKey) as? Date {
            let elapsed = now.timeIntervalSince(startDate)
            // 30 days = 30 * 86400 seconds
            if elapsed >= 30 * 86400 {
                resetCycle(startDate: now)
            }
        } else {
            resetCycle(startDate: now)
        }
    }
    
    private func resetCycle(startDate: Date) {
        defaults.set(startDate, forKey: cycleStartDateKey)
        monthlyUsage.removeAll()
        defaults.set([String: String](), forKey: monthlyUsageKey)
    }
    
    private func loadMonthlyUsage() {
        if let saved = defaults.dictionary(forKey: monthlyUsageKey) as? [String: String] {
            var usage: [String: UInt64] = [:]
            for (k, v) in saved {
                if let val = UInt64(v) {
                    let nameKey = (k == "Browser Helper" || k == "Browser Helper (Renderer)") ? "Dia" : k
                    usage[nameKey, default: 0] += val
                }
            }
            monthlyUsage = usage
        }
    }
    
    private func saveMonthlyUsage() {
        var toSave: [String: String] = [:]
        for (k, v) in monthlyUsage {
            toSave[k] = String(v)
        }
        defaults.set(toSave, forKey: monthlyUsageKey)
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
        if lower.contains("node") || lower.contains("zsh") || lower.contains("bash") || lower.contains("python") || lower.contains("server") {
            symbolName = "terminal"
        } else {
            symbolName = "gearshape"
        }
        
        if #available(macOS 11.0, *), let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            return symbolImage
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
                                    let deltaIn = bytesIn >= prev.inBytes ? bytesIn - prev.inBytes : bytesIn
                                    let deltaOut = bytesOut >= prev.outBytes ? bytesOut - prev.outBytes : bytesOut
                                    deltaTotal = deltaIn + deltaOut
                                    speedDelta = deltaTotal
                                } else {
                                    deltaTotal = bytesIn + bytesOut
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
                    self.checkAndResetCycle()
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
                            self.monthlyUsage[appName, default: 0] += delta
                            updatedUsage = true
                        }
                    }
                    if updatedUsage {
                        self.saveMonthlyUsage()
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
        let sorted = monthlyUsage.map { (name, total) in
            let icon = appIcons[name] ?? findAppIcon(appName: name)
            return AppTrafficInfo(name: name, icon: icon, totalBytes: total)
        }.sorted { $0.totalBytes > $1.totalBytes }
        
        return Array(sorted.prefix(limit))
    }
}
