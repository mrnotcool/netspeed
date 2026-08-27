import Cocoa
import CoreText
import ServiceManagement

// MARK: - 两行速度文本视图
final class SpeedView: NSView {
    private var uploadText: String = ""
    private var downloadText: String = ""

    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private let font = NSFont.menuBarFont(ofSize: 9)
    private let baselineDistance: CGFloat = 9
    private let contentWidth: CGFloat = 45

    override init(frame: NSRect) {
        super.init(frame: frame)
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
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: contentWidth, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            super.draw(dirtyRect)
            // 深色外观使用更高亮纯白，浅色外观使用标准主文字色
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let primaryColor: NSColor = isDark ? NSColor(calibratedWhite: 0.98, alpha: 1.0) : .labelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: primaryColor,
            ]

            let uploadLine = makeLine(text: uploadText, attributes: attributes)
            let downloadLine = makeLine(text: downloadText, attributes: attributes)
            let downloadBounds = glyphBounds(for: downloadLine)
            let uploadBounds = glyphBounds(for: uploadLine).offsetBy(dx: 0, dy: baselineDistance)
            let textBounds = downloadBounds.union(uploadBounds)
            let bottomBaseline = bounds.midY - textBounds.midY

            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.clip(to: bounds)
            context.textMatrix = .identity
            draw(line: uploadLine, baseline: bottomBaseline + baselineDistance, in: context)
            draw(line: downloadLine, baseline: bottomBaseline, in: context)
            context.restoreGState()
        }
    }

    private func makeLine(text: String, attributes: [NSAttributedString.Key: Any]) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private func glyphBounds(for line: CTLine) -> CGRect {
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .excludeTypographicLeading])
        guard !bounds.isNull, !bounds.isEmpty else {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            return CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
        }
        return bounds
    }

    private func draw(line: CTLine, baseline: CGFloat, in context: CGContext) {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: bounds.maxX - width, y: baseline)
        CTLineDraw(line, context)
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
    private let statusItemLeftPadding: CGFloat = 4
    private let statusItemRightPadding: CGFloat = 1

    // 无箭头、纯正 macOS 菜单级液态玻璃悬浮面板
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
        panel.animationBehavior = .default
        panel.isReleasedWhenClosed = false
        return panel
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            speedView.trailingAnchor.constraint(
                equalTo: statusButton.trailingAnchor,
                constant: -statusItemRightPadding
            ),
            speedView.centerYAnchor.constraint(
                equalTo: statusButton.centerYAnchor
            ),
        ])
        updateStatusItemLength()

        speedView.onLeftClick = { [weak self] in
            self?.toggleTrafficPanel()
        }
        speedView.onRightClick = { [weak self] event in
            self?.showContextMenu(with: event)
        }

        AppNetworkMonitor.shared.startMonitoring()

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
        if trafficPanel.isVisible {
            trafficDashboard.updateContent()
        }
    }

    private func updateStatusItemLength() {
        statusItem.length = speedView.intrinsicContentSize.width
            + statusItemLeftPadding
            + statusItemRightPadding
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
