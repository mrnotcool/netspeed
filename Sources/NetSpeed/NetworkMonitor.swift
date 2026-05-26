import Foundation
import Darwin

struct NetworkSpeed {
    let download: Double // bytes per second
    let upload: Double   // bytes per second
}

final class NetworkMonitor {
    private var previousRecv: UInt64 = 0
    private var previousSent: UInt64 = 0
    private var previousTime: Date = .init()
    private var initialized = false

    private func totalBytes() -> (recv: UInt64, sent: UInt64)? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let start = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var totalRecv: UInt64 = 0
        var totalSent: UInt64 = 0

        var cursor = start
        while true {
            let iface = cursor.pointee
            if iface.ifa_addr.pointee.sa_family == AF_LINK {
                let name = String(cString: iface.ifa_name)
                if name.hasPrefix("en"), let n = Int(name.dropFirst(2)), n <= 9 {
                    guard let ifaData = iface.ifa_data else { continue }
                    let data = ifaData.assumingMemoryBound(to: if_data.self).pointee
                    totalRecv += UInt64(data.ifi_ibytes)
                    totalSent += UInt64(data.ifi_obytes)
                }
            }
            guard let next = iface.ifa_next else { break }
            cursor = next
        }

        return (totalRecv, totalSent)
    }

    func readSpeed() -> NetworkSpeed {
        guard let current = totalBytes() else {
            return .init(download: 0, upload: 0)
        }

        let now = Date()

        if !initialized {
            previousRecv = current.recv
            previousSent = current.sent
            previousTime = now
            initialized = true
            return .init(download: 0, upload: 0)
        }

        let elapsed = now.timeIntervalSince(previousTime)
        guard elapsed > 0 else { return .init(download: 0, upload: 0) }

        // Reset baseline if system was asleep or clock jumped
        if elapsed > 5.0 {
            previousRecv = current.recv
            previousSent = current.sent
            previousTime = now
            return .init(download: 0, upload: 0)
        }

        // Handle counter wrap / interface reset
        let downDiff = current.recv >= previousRecv ? current.recv - previousRecv : 0
        let upDiff   = current.sent >= previousSent ? current.sent - previousSent : 0

        let downSpeed = Double(downDiff) / elapsed
        let upSpeed   = Double(upDiff) / elapsed

        previousRecv = current.recv
        previousSent = current.sent
        previousTime = now

        return .init(download: downSpeed, upload: upSpeed)
    }
}
