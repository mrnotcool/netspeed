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

    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

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
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
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
    private var statusButton: NSStatusBarButton!
    private var speedView: SpeedView!
    private var timer: Timer?
    private let monitor = NetworkMonitor()
    private let trafficDashboard = TrafficDashboardViewController()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private lazy var trafficPanel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 304, height: 498),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = trafficDashboard
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        return panel
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFontIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        statusButton = button
        statusButton.title = ""
        statusButton.image = nil

        speedView = SpeedView(frame: .zero)
        speedView.set(upload: "0 KB/s", download: "0 KB/s")
        speedView.translatesAutoresizingMaskIntoConstraints = false
        statusButton.addSubview(speedView)
        NSLayoutConstraint.activate([
            speedView.centerXAnchor.constraint(equalTo: statusButton.centerXAnchor),
            speedView.centerYAnchor.constraint(equalTo: statusButton.centerYAnchor),
        ])
        updateStatusItemLength()

        speedView.onLeftClick = { [weak self] in
            self?.toggleTrafficPanel()
        }
        speedView.onRightClick = { [weak self] event in
            self?.showContextMenu(with: event)
        }

        AppNetworkMonitor.shared.startMonitoring()

        // Use RunLoop.main with mode .common so timer continues firing during menu interaction
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        updateDisplay()
    }

    @objc private func updateDisplay() {
        let speed = monitor.readSpeed()
        speedView.set(upload: formatSpeed(speed.upload), download: formatSpeed(speed.download))
        updateStatusItemLength()
        if trafficPanel.isVisible {
            trafficDashboard.updateContent()
        }
    }

    private func updateStatusItemLength() {
        statusItem.length = max(28, speedView.intrinsicContentSize.width + 6)
    }

    private func toggleTrafficPanel() {
        if trafficPanel.isVisible {
            hideTrafficPanel()
            return
        }

        trafficDashboard.updateContent()
        positionTrafficPanel()
        trafficPanel.orderFrontRegardless()
        installDismissMonitors()
    }

    private func positionTrafficPanel() {
        guard let buttonWindow = statusButton.window else { return }
        let buttonRectInWindow = statusButton.convert(statusButton.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let panelSize = trafficPanel.frame.size
        let visibleFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? buttonRect

        var x = buttonRect.midX - panelSize.width / 2
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        var y = buttonRect.minY - panelSize.height - 4
        if y < visibleFrame.minY + 8 {
            y = buttonRect.maxY + 4
        }
        trafficPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.trafficPanel.isVisible else { return event }
            if event.window === self.trafficPanel || event.window === self.statusButton.window {
                return event
            }
            self.hideTrafficPanel()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideTrafficPanel()
            }
        }
    }

    private func hideTrafficPanel() {
        trafficPanel.orderOut(nil)
        removeDismissMonitors()
    }

    private func removeDismissMonitors() {
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func showContextMenu(with event: NSEvent) {
        if trafficPanel.isVisible {
            hideTrafficPanel()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let launchItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.isEnabled = true
        if #available(macOS 13.0, *) {
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchItem.isEnabled = false
            launchItem.title = "开机启动（需要 macOS 13+）"
        }
        menu.addItem(launchItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 NetSpeed", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: statusButton)
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
        hideTrafficPanel()
        AppNetworkMonitor.shared.stopMonitoring()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
