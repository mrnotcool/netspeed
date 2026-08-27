import AppKit

private enum DashboardMetrics {
    static let width: CGFloat = 332
    static let height: CGFloat = 520
    static let horizontalInset: CGFloat = 14
    static let rowHeight: CGFloat = 25
    static let rankingRowHeight: CGFloat = 35
    static let accent = NSColor(calibratedRed: 0.02, green: 0.72, blue: 0.84, alpha: 1)
}

private enum DashboardPalette {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func softGray(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor(calibratedWhite: 0.72, alpha: 0.24)
            : NSColor(calibratedWhite: 0.46, alpha: 0.16)
    }

    static func faintGray(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor(calibratedWhite: 0.82, alpha: 0.10)
            : NSColor(calibratedWhite: 0.50, alpha: 0.07)
    }

    static func hairline(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor(calibratedWhite: 0.55, alpha: 0.12)
    }
}

final class TrafficDashboardViewController: NSViewController {
    private let monitor: AppNetworkMonitor
    private var selectedRange: TrafficRange = .today

    private let realtimeRows = (0..<5).map { _ in RealtimeTrafficRowView() }
    private let rankingRows = (0..<5).map { _ in TrafficRankingRowView() }
    private let chartView = TrafficBarChartView()

    private lazy var rangeControl = makeSegmentedControl(labels: ["今日", "本月"], selected: 0)

    init(monitor: AppNetworkMonitor = .shared) {
        self.monitor = monitor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = LiquidGlassBackgroundView(
            frame: NSRect(x: 0, y: 0, width: DashboardMetrics.width, height: DashboardMetrics.height)
        )
        view = root
        buildInterface()
    }

    private func buildInterface() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        let realtimeTitle = makeLabel("进程与客户端", size: 12.5, weight: .medium, color: .secondaryLabelColor)
        content.addArrangedSubview(realtimeTitle)
        content.setCustomSpacing(5, after: realtimeTitle)

        let realtimeDivider = makeDivider()
        content.addArrangedSubview(realtimeDivider)

        let realtimeStack = NSStackView(views: realtimeRows)
        realtimeStack.orientation = .vertical
        realtimeStack.alignment = .leading
        realtimeStack.spacing = 0
        content.addArrangedSubview(realtimeStack)

        let sectionDivider = makeDivider()
        content.addArrangedSubview(sectionDivider)
        content.setCustomSpacing(10, after: sectionDivider)

        let trafficHeader = NSView()
        trafficHeader.translatesAutoresizingMaskIntoConstraints = false
        let trafficTitle = makeLabel("流量", size: 12.5, weight: .semibold, color: .secondaryLabelColor)
        trafficTitle.translatesAutoresizingMaskIntoConstraints = false
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        rangeControl.target = self
        rangeControl.action = #selector(rangeDidChange)

        trafficHeader.addSubview(trafficTitle)
        trafficHeader.addSubview(rangeControl)
        NSLayoutConstraint.activate([
            trafficHeader.widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            trafficHeader.heightAnchor.constraint(equalToConstant: 25),
            trafficTitle.leadingAnchor.constraint(equalTo: trafficHeader.leadingAnchor),
            trafficTitle.centerYAnchor.constraint(equalTo: trafficHeader.centerYAnchor),
            rangeControl.trailingAnchor.constraint(equalTo: trafficHeader.trailingAnchor),
            rangeControl.centerYAnchor.constraint(equalTo: trafficHeader.centerYAnchor),
            rangeControl.widthAnchor.constraint(equalToConstant: 112),
            rangeControl.heightAnchor.constraint(equalToConstant: 24),
        ])
        content.addArrangedSubview(trafficHeader)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(chartView)
        NSLayoutConstraint.activate([
            chartView.widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            chartView.heightAnchor.constraint(equalToConstant: 94),
        ])

        let rankingTitle = makeLabel("进程与应用", size: 12.5, weight: .semibold, color: .secondaryLabelColor)
        content.addArrangedSubview(rankingTitle)
        content.setCustomSpacing(3, after: rankingTitle)

        let rankingStack = NSStackView(views: rankingRows)
        rankingStack.orientation = .vertical
        rankingStack.alignment = .leading
        rankingStack.spacing = 0
        content.addArrangedSubview(rankingStack)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DashboardMetrics.horizontalInset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DashboardMetrics.horizontalInset),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            realtimeDivider.widthAnchor.constraint(equalTo: content.widthAnchor),
            sectionDivider.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])

        updateContent()
    }

    func updateContent() {
        guard isViewLoaded else { return }

        let realtime = monitor.topRealtimeApps(limit: 5)
        for (index, row) in realtimeRows.enumerated() {
            row.update(info: index < realtime.count ? realtime[index] : nil)
        }

        let ranking = monitor.topTrafficApps(range: selectedRange, limit: 5)
        let maximum = ranking.first?.totalBytes ?? 0
        for (index, row) in rankingRows.enumerated() {
            row.update(info: index < ranking.count ? ranking[index] : nil, maximumBytes: maximum)
        }

        chartView.update(points: monitor.trafficChartPoints(range: selectedRange), range: selectedRange)
    }

    @objc private func rangeDidChange() {
        selectedRange = rangeControl.selectedSegment == 0 ? .today : .month
        updateContent()
    }

    private func makeSegmentedControl(labels: [String], selected: Int) -> SurgeSegmentedControl {
        SurgeSegmentedControl(labels: labels, selectedSegment: selected)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeDivider() -> NSView {
        let divider = SoftDividerView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }
}

private final class LiquidGlassBackgroundView: NSVisualEffectView {
    private let tintView = GlassTintView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dark = DashboardPalette.isDark(effectiveAppearance)
        let borderRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let border = NSBezierPath(roundedRect: borderRect, xRadius: 17.5, yRadius: 17.5)
        (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.72)).setStroke()
        border.lineWidth = 1
        border.stroke()

        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 18, y: bounds.maxY - 1.5))
        highlight.line(to: NSPoint(x: bounds.maxX - 18, y: bounds.maxY - 1.5))
        NSColor.white.withAlphaComponent(dark ? 0.12 : 0.55).setStroke()
        highlight.lineWidth = 1
        highlight.stroke()
    }
}

private final class GlassTintView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dark = DashboardPalette.isDark(effectiveAppearance)
        let top = dark
            ? NSColor(calibratedWhite: 0.20, alpha: 0.48)
            : NSColor.white.withAlphaComponent(0.78)
        let bottom = dark
            ? NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 0.38)
            : NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.0, alpha: 0.58)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
    }
}

private final class SoftDividerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        DashboardPalette.hairline(effectiveAppearance).setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

private final class SurgeSegmentedControl: NSControl {
    private let labels: [String]
    var selectedSegment: Int {
        didSet { needsDisplay = true }
    }

    init(labels: [String], selectedSegment: Int) {
        self.labels = labels
        self.selectedSegment = selectedSegment
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.radioGroup)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard !labels.isEmpty else { return }
        let location = convert(event.locationInWindow, from: nil)
        let segmentWidth = bounds.width / CGFloat(labels.count)
        let segment = min(max(Int(location.x / segmentWidth), 0), labels.count - 1)
        selectedSegment = segment
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !labels.isEmpty else { return }

        let isDark = DashboardPalette.isDark(effectiveAppearance)
        let outerRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 6, yRadius: 6)
        (isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.40)).setFill()
        outerPath.fill()
        (isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.white.withAlphaComponent(0.68)).setStroke()
        outerPath.lineWidth = 1
        outerPath.stroke()

        let segmentWidth = bounds.width / CGFloat(labels.count)
        if labels.indices.contains(selectedSegment) {
            let selectedRect = NSRect(
                x: CGFloat(selectedSegment) * segmentWidth + 2,
                y: 2,
                width: segmentWidth - 4,
                height: bounds.height - 4
            )
            let selectedPath = NSBezierPath(roundedRect: selectedRect, xRadius: 5, yRadius: 5)
            (isDark
                ? NSColor(calibratedWhite: 0.72, alpha: 0.42)
                : NSColor(calibratedWhite: 0.66, alpha: 0.62)).setFill()
            selectedPath.fill()
        }

        for (index, label) in labels.enumerated() {
            let isSelected = index == selectedSegment
            let color: NSColor
            if isSelected {
                color = .white
            } else {
                color = .secondaryLabelColor
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            let centerX = CGFloat(index) * segmentWidth + segmentWidth / 2
            let point = NSPoint(x: centerX - size.width / 2, y: (bounds.height - size.height) / 2)
            (label as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}

private final class RealtimeTrafficRowView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "-")
    private let valueLabel = NSTextField(labelWithString: "0 B/s")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5.5
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.10
        iconView.layer?.shadowRadius = 1.5
        iconView.layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        nameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            heightAnchor.constraint(equalToConstant: DashboardMetrics.rowHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(info: AppSpeedInfo?) {
        nameLabel.stringValue = info?.name ?? "-"
        iconView.image = info?.icon
        iconView.isHidden = info == nil
        valueLabel.stringValue = ByteFormatter.speed(info?.bytesPerSec ?? 0)
    }
}

private final class TrafficRankingRowView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "-")
    private let valueLabel = NSTextField(labelWithString: "0 B")
    private let progressView = RelativeTrafficBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.10
        iconView.layer?.shadowRadius = 1.5
        iconView.layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        nameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(valueLabel)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            heightAnchor.constraint(equalToConstant: DashboardMetrics.rankingRowHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            progressView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(info: AppTrafficInfo?, maximumBytes: UInt64) {
        nameLabel.stringValue = info?.name ?? "-"
        iconView.image = info?.icon
        iconView.isHidden = info == nil
        let bytes = info?.totalBytes ?? 0
        valueLabel.stringValue = ByteFormatter.bytes(bytes)
        progressView.progress = maximumBytes > 0 ? CGFloat(Double(bytes) / Double(maximumBytes)) : 0
    }
}

private final class RelativeTrafficBarView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard progress > 0 else { return }
        DashboardPalette.faintGray(effectiveAppearance).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let width = max(bounds.height, bounds.width * min(max(progress, 0), 1))
        DashboardPalette.softGray(effectiveAppearance).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                     xRadius: bounds.height / 2,
                     yRadius: bounds.height / 2).fill()
    }
}

private final class TrafficBarChartView: NSView {
    private var points: [TrafficChartPoint] = []
    private var range: TrafficRange = .today

    func update(points: [TrafficChartPoint], range: TrafficRange) {
        self.points = points
        self.range = range
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !points.isEmpty else { return }

        let plotRect = NSRect(x: 0, y: 19, width: bounds.width - 47, height: bounds.height - 25)
        let rawMaximum = points.map(\.totalBytes).max() ?? 0
        let maximum = niceMaximum(max(rawMaximum, 1))

        drawGridLine(y: plotRect.maxY, label: ByteFormatter.axis(maximum), in: plotRect)
        drawGridLine(y: plotRect.midY, label: ByteFormatter.axis(maximum / 2), in: plotRect)

        let slotWidth = plotRect.width / CGFloat(points.count)
        let barWidth = range == .today ? min(6, slotWidth * 0.48) : min(5, slotWidth * 0.5)
        DashboardMetrics.accent.setFill()

        for (index, point) in points.enumerated() {
            let centerX = plotRect.minX + slotWidth * (CGFloat(index) + 0.5)
            let ratio = CGFloat(Double(point.totalBytes) / Double(maximum))
            let height = point.totalBytes == 0 ? 5 : max(5, plotRect.height * ratio)
            let rect = NSRect(x: centerX - barWidth / 2, y: plotRect.minY, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }

        drawXAxis(in: plotRect, slotWidth: slotWidth)
    }

    private func drawGridLine(y: CGFloat, label: String, in plotRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: plotRect.minX, y: y))
        path.line(to: NSPoint(x: plotRect.maxX, y: y))
        path.lineWidth = 1
        path.setLineDash([2, 3], count: 2, phase: 0)
        DashboardPalette.hairline(effectiveAppearance).setStroke()
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.72),
        ]
        (label as NSString).draw(at: NSPoint(x: plotRect.maxX + 7, y: y - 6), withAttributes: attributes)
    }

    private func drawXAxis(in plotRect: NSRect, slotWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.72),
        ]

        let labels: [(Int, String)]
        if range == .today {
            labels = [(0, "12AM"), (6, "6AM"), (12, "12PM"), (18, "6PM")]
        } else {
            let last = max(points.count - 1, 0)
            labels = [(0, "1"), (min(7, last), "8"), (min(14, last), "15"), (min(21, last), "22")]
        }

        for (index, text) in labels {
            let centerX = plotRect.minX + slotWidth * (CGFloat(index) + 0.5)
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: centerX - size.width / 2, y: 1), withAttributes: attributes)
        }
    }

    private func niceMaximum(_ value: UInt64) -> UInt64 {
        let raw = Double(value)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let ceiling: Double
        if normalized <= 1 { ceiling = 1 }
        else if normalized <= 2 { ceiling = 2 }
        else if normalized <= 5 { ceiling = 5 }
        else { ceiling = 10 }
        return UInt64(ceiling * magnitude)
    }
}

enum ByteFormatter {
    static func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
        }
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if bytes >= 1_000_000_000_000 { return String(format: "%.2f TB", value / 1_000_000_000_000) }
        if bytes >= 1_000_000_000 { return String(format: "%.2f GB", value / 1_000_000_000) }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0f KB", value / 1_000) }
        return "\(bytes) B"
    }

    static func axis(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if bytes >= 1_000_000_000 { return String(format: "%.0f GB", value / 1_000_000_000) }
        if bytes >= 1_000_000 { return String(format: "%.0f MB", value / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0f KB", value / 1_000) }
        return "\(bytes) B"
    }
}
