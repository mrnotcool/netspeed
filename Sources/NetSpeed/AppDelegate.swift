import Cocoa
import CoreText
import ServiceManagement

// MARK: - 注册字体
private func registerFontIfNeeded() {
    guard let url = Bundle.main.url(forResource: "SF-Compact-Display-Medium", withExtension: "otf") else {
        print("Warning: Font file not found in bundle")
        return
    }
    var error: Unmanaged<CFError>?
    let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    if !success {
        let msg = error?.takeRetainedValue().localizedDescription ?? "unknown error"
        print("Warning: Font registration failed: \(msg)")
    }
}

// MARK: - 两行速度文本视图
final class SpeedView: NSView {
    private var uploadText: String = ""
    private var downloadText: String = ""

    weak var popupMenu: NSMenu?

    private let font: NSFont = {
        if let f = NSFont(name: "SFCompactDisplay-Regular", size: 9) { return f }
        return .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    }()

    private let lineH: CGFloat
    private let baselineOffset: CGFloat  // 从行底到字型基线的标准距离
    private let rightPad: CGFloat = 2
    private let kern: CGFloat = 0.25

    override init(frame: NSRect) {
        lineH = ceil(font.capHeight - font.descender)
        baselineOffset = -font.descender    // descender 为负值，取反即为基线距行底的距离
        super.init(frame: frame)
        registerFontIfNeeded()
    }
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        if let popupMenu {
            NSMenu.popUpContextMenu(popupMenu, with: event, for: self)
        }
    }

    func set(upload: String, download: String) {
        uploadText = upload
        downloadText = download
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let numAttr: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        let unitAttr: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]

        func lineWidth(_ text: String) -> CGFloat {
            let parts = text.split(separator: " ", maxSplits: 1)
            let numStr = String(parts.first ?? "0")
            let unitStr = parts.count > 1 ? String(parts[1]) : ""
            let numW = (numStr as NSString).size(withAttributes: numAttr).width
            let unitW = (unitStr as NSString).size(withAttributes: unitAttr).width
            return numW + 1.5 + unitW
        }

        let maxW = max(lineWidth(uploadText), lineWidth(downloadText))
        return NSSize(width: ceil(maxW + rightPad), height: lineH * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            super.draw(dirtyRect)
            let primaryColor = NSColor.labelColor

            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: primaryColor,
                .kern: kern,
            ]
            let unitAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: primaryColor,
                .kern: kern,
            ]

            drawLine(text: uploadText,   lineBottom: lineH, attr: attr, unitAttr: unitAttr)
            drawLine(text: downloadText, lineBottom: 0,     attr: attr, unitAttr: unitAttr)
        }
    }

    private func drawLine(text: String, lineBottom: CGFloat, attr: [NSAttributedString.Key: Any], unitAttr: [NSAttributedString.Key: Any]) {
        let parts = text.split(separator: " ", maxSplits: 1)
        let numStr = String(parts.first ?? "0")
        let unitStr = parts.count > 1 ? String(parts[1]) : ""

        let numSize = (numStr as NSString).size(withAttributes: attr)
        let unitSize = (unitStr as NSString).size(withAttributes: unitAttr)
        let gap: CGFloat = 1.5
        let totalW = numSize.width + gap + unitSize.width

        let x = self.bounds.width - totalW - rightPad
        let baseline = lineBottom + baselineOffset

        (numStr as NSString).draw(at: NSPoint(x: x, y: baseline), withAttributes: attr)
        if !unitStr.isEmpty {
            (unitStr as NSString).draw(at: NSPoint(x: x + numSize.width + gap, y: baseline), withAttributes: unitAttr)
        }
    }
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var speedView: SpeedView!
    private var timer: Timer?
    private let monitor = NetworkMonitor()

    private var realtimeMenuItems: [NSMenuItem] = []
    private var monthlyMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFontIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        speedView = SpeedView(frame: .zero)
        speedView.set(upload: "0 KB/s", download: "0 KB/s")
        statusItem.view = speedView

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        speedView.popupMenu = menu

        AppNetworkMonitor.shared.startMonitoring()

        // Use RunLoop.main with mode .common so timer continues firing during menu interaction
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        updateDisplay()
    }

    @objc private func dummyAction() {
        // No-op for informational items
    }

    @objc private func updateDisplay() {
        let speed = monitor.readSpeed()
        speedView.set(upload: formatSpeed(speed.upload), download: formatSpeed(speed.download))
        updateOpenMenuItems()
    }

    private func updateOpenMenuItems() {
        guard !realtimeMenuItems.isEmpty else { return }

        let topRealtime = AppNetworkMonitor.shared.topRealtimeApps(limit: 5)
        for i in 0..<5 {
            if i < realtimeMenuItems.count {
                if i < topRealtime.count {
                    let info = topRealtime[i]
                    updateMenuItem(realtimeMenuItems[i], appName: info.name, valueStr: formatSpeed(info.bytesPerSec), icon: info.icon)
                } else {
                    updateMenuItem(realtimeMenuItems[i], appName: "-", valueStr: "0 KB/s", icon: nil)
                }
            }
        }

        let topMonthly = AppNetworkMonitor.shared.topMonthlyApps(limit: 5)
        for i in 0..<5 {
            if i < monthlyMenuItems.count {
                if i < topMonthly.count {
                    let info = topMonthly[i]
                    updateMenuItem(monthlyMenuItems[i], appName: info.name, valueStr: formatBytes(info.totalBytes), icon: info.icon)
                } else {
                    updateMenuItem(monthlyMenuItems[i], appName: "-", valueStr: "0 B", icon: nil)
                }
            }
        }
    }

    private func updateMenuItem(_ item: NSMenuItem, appName: String, valueStr: String, icon: NSImage?) {
        let displayName: String
        if appName.count > 13 {
            displayName = String(appName.prefix(12)) + "…"
        } else {
            displayName = appName
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .right, location: 180)]

        let attrStr = NSMutableAttributedString()

        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .light),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        attrStr.append(NSAttributedString(string: displayName, attributes: nameAttr))
        attrStr.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraphStyle]))

        let valAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .light),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        attrStr.append(NSAttributedString(string: valueStr, attributes: valAttr))

        item.attributedTitle = attrStr

        let resolvedIcon = icon ?? AppNetworkMonitor.shared.findAppIcon(appName: appName)
        let iconCopy = resolvedIcon.copy() as! NSImage
        iconCopy.size = NSSize(width: 16, height: 16)
        item.image = iconCopy
    }

    private func formatSpeed(_ bps: Double) -> String {
        if bps >= 1_000_000_000_000 {
            return String(format: "%.2f TB/s", bps / 1_000_000_000_000)
        } else if bps >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bps / 1_000_000_000)
        } else if bps >= 1_000_000 {
            return String(format: "%.1f MB/s", bps / 1_000_000)
        } else {
            return String(format: "%.0f KB/s", bps / 1_000)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let doubleBytes = Double(bytes)
        if bytes >= 1_000_000_000_000 {
            return String(format: "%.2f TB", doubleBytes / 1_000_000_000_000)
        } else if bytes >= 1_000_000_000 {
            return String(format: "%.2f GB", doubleBytes / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.1f MB", doubleBytes / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.0f KB", doubleBytes / 1_000)
        } else {
            return "\(bytes) B"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        AppNetworkMonitor.shared.stopMonitoring()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.autoenablesItems = false
        menu.removeAllItems()
        realtimeMenuItems.removeAll()
        monthlyMenuItems.removeAll()

        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.5
        ]

        // 1. REALTIME TRAFFIC Header
        let header1 = NSMenuItem(title: "REALTIME TRAFFIC", action: #selector(dummyAction), keyEquivalent: "")
        header1.target = self
        header1.attributedTitle = NSAttributedString(string: "REALTIME TRAFFIC", attributes: headerAttr)
        header1.isEnabled = true
        menu.addItem(header1)

        // 实时流量前5名
        let topRealtime = AppNetworkMonitor.shared.topRealtimeApps(limit: 5)
        for i in 0..<5 {
            let item = NSMenuItem(title: "", action: #selector(dummyAction), keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            if i < topRealtime.count {
                let info = topRealtime[i]
                updateMenuItem(item, appName: info.name, valueStr: formatSpeed(info.bytesPerSec), icon: info.icon)
            } else {
                updateMenuItem(item, appName: "-", valueStr: "0 KB/s", icon: nil)
            }
            realtimeMenuItems.append(item)
            menu.addItem(item)
        }

        // 分隔线
        menu.addItem(NSMenuItem.separator())

        // 2. 30-DAY TRAFFIC Header
        let header2 = NSMenuItem(title: "30-DAY TRAFFIC", action: #selector(dummyAction), keyEquivalent: "")
        header2.target = self
        header2.attributedTitle = NSAttributedString(string: "30-DAY TRAFFIC", attributes: headerAttr)
        header2.isEnabled = true
        menu.addItem(header2)

        // 累计流量前5名
        let topMonthly = AppNetworkMonitor.shared.topMonthlyApps(limit: 5)
        for i in 0..<5 {
            let item = NSMenuItem(title: "", action: #selector(dummyAction), keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            if i < topMonthly.count {
                let info = topMonthly[i]
                updateMenuItem(item, appName: info.name, valueStr: formatBytes(info.totalBytes), icon: info.icon)
            } else {
                updateMenuItem(item, appName: "-", valueStr: "0 B", icon: nil)
            }
            monthlyMenuItems.append(item)
            menu.addItem(item)
        }

        // 分隔线
        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.isEnabled = true
        if #available(macOS 13.0, *) {
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchItem.isEnabled = false
            launchItem.title = "Launch at Login (macOS 13+)"
        }
        menu.addItem(launchItem)

        // 分隔线
        menu.addItem(NSMenuItem.separator())

        // Quit NetSpeed
        let quitItem = NSMenuItem(title: "Quit NetSpeed", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
    }

    func menuDidClose(_ menu: NSMenu) {
        realtimeMenuItems.removeAll()
        monthlyMenuItems.removeAll()
    }
}
