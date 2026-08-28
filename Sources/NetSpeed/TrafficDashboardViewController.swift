import AppKit

private enum DashboardMetrics {
    static let width: CGFloat = 304
    static let height: CGFloat = 498
    static let horizontalInset: CGFloat = 13
    static let rowHeight: CGFloat = 22
    static let rankingRowHeight: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let sectionContentSpacing: CGFloat = 6
    static let cornerRadius: CGFloat = 20   // macOS 26 style: larger squircle radius
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

    static func chartGridLine(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.18)
    }

    static func chartAxisLabel(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.46)
            : NSColor.black.withAlphaComponent(0.26)
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
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        // 1. 流量图表模块
        let trafficHeader = NSView()
        trafficHeader.translatesAutoresizingMaskIntoConstraints = false
        let trafficTitle = makeLabel("流量", size: 11.5, weight: .semibold, color: .secondaryLabelColor)
        trafficTitle.translatesAutoresizingMaskIntoConstraints = false
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        rangeControl.target = self
        rangeControl.action = #selector(rangeDidChange)

        trafficHeader.addSubview(trafficTitle)
        trafficHeader.addSubview(rangeControl)
        NSLayoutConstraint.activate([
            trafficHeader.widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            trafficHeader.heightAnchor.constraint(equalToConstant: 23),
            trafficTitle.leadingAnchor.constraint(equalTo: trafficHeader.leadingAnchor),
            trafficTitle.centerYAnchor.constraint(equalTo: trafficHeader.centerYAnchor),
            rangeControl.trailingAnchor.constraint(equalTo: trafficHeader.trailingAnchor),
            rangeControl.centerYAnchor.constraint(equalTo: trafficHeader.centerYAnchor),
            rangeControl.widthAnchor.constraint(equalToConstant: 104),
            rangeControl.heightAnchor.constraint(equalToConstant: 22),
        ])
        content.addArrangedSubview(trafficHeader)
        content.setCustomSpacing(DashboardMetrics.sectionContentSpacing, after: trafficHeader)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(chartView)
        NSLayoutConstraint.activate([
            chartView.widthAnchor.constraint(equalToConstant: DashboardMetrics.width - DashboardMetrics.horizontalInset * 2),
            chartView.heightAnchor.constraint(equalToConstant: 88),
        ])
        content.setCustomSpacing(DashboardMetrics.sectionSpacing, after: chartView)

        // 2. 进程与应用（累计流量排行）
        let rankingTitle = makeLabel("进程与应用", size: 11.5, weight: .semibold, color: .secondaryLabelColor)
        content.addArrangedSubview(rankingTitle)
        content.setCustomSpacing(DashboardMetrics.sectionContentSpacing, after: rankingTitle)

        let rankingStack = NSStackView(views: rankingRows)
        rankingStack.orientation = .vertical
        rankingStack.alignment = .leading
        // Keep the section's total height while moving each row's invisible
        // trailing space between rows. The final row then ends at its visible
        // content edge, so both 16pt section gaps look the same.
        rankingStack.spacing = 10
        content.addArrangedSubview(rankingStack)
        content.setCustomSpacing(DashboardMetrics.sectionSpacing, after: rankingStack)

        // 3. 实时进程（实时网速，纯留白间隔无分割线）
        let realtimeTitle = makeLabel("实时进程", size: 11.5, weight: .semibold, color: .secondaryLabelColor)
        content.addArrangedSubview(realtimeTitle)
        content.setCustomSpacing(DashboardMetrics.sectionContentSpacing, after: realtimeTitle)

        let realtimeStack = NSStackView(views: realtimeRows)
        realtimeStack.orientation = .vertical
        realtimeStack.alignment = .leading
        realtimeStack.spacing = 0
        content.addArrangedSubview(realtimeStack)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DashboardMetrics.horizontalInset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DashboardMetrics.horizontalInset),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
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
    private static let cornerMask: NSImage = {
        let r = DashboardMetrics.cornerRadius
        let size = NSSize(width: r * 2 + 2, height: r * 2 + 2)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
            path.fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // This is a text-rich popover, so prefer the semantic popover material's
        // stronger blur and luminosity adjustment over the highly translucent HUD look.
        material = .popover
        blendingMode = .behindWindow
        state = .active
        // 使用 maskImage 确保 GPU 级别完美圆角，彻底根除 4 个角的三角形伪影
        maskImage = Self.cornerMask
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 绘制 macOS 菜单级的细微液态玻璃外边缘高光（0.5pt）
        let isDark = DashboardPalette.isDark(effectiveAppearance)
        let strokeColor = isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.white.withAlphaComponent(0.65)

        let insetRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: DashboardMetrics.cornerRadius - 0.5, yRadius: DashboardMetrics.cornerRadius - 0.5)
        path.lineWidth = 0.5
        strokeColor.setStroke()
        path.stroke()
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
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
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
        iconView.layer?.cornerRadius = 5
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.10
        iconView.layer?.shadowRadius = 1.5
        iconView.layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
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
        iconView.layer?.cornerRadius = 5.5
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.10
        iconView.layer?.shadowRadius = 1.5
        iconView.layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            progressView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            progressView.heightAnchor.constraint(equalToConstant: 3.5),
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

        let axisLabelGutter: CGFloat = 45
        let plotRect = NSRect(x: 0, y: 18, width: bounds.width - axisLabelGutter, height: bounds.height - 24)
        let rawMaximum = points.map(\.totalBytes).max() ?? 0
        let maximum = niceMaximum(max(rawMaximum, 1))

        let slotWidth = plotRect.width / CGFloat(points.count)
        let barWidth = range == .today ? min(6, slotWidth * 0.48) : min(5, slotWidth * 0.5)
        let firstCenter = plotRect.minX + barWidth / 2
        let lastCenter = plotRect.maxX - barWidth / 2
        DashboardMetrics.accent.setFill()

        for (index, point) in points.enumerated() {
            let centerX: CGFloat
            if points.count == 1 {
                centerX = plotRect.midX
            } else {
                centerX = firstCenter
                    + (lastCenter - firstCenter) * CGFloat(index) / CGFloat(points.count - 1)
            }
            let ratio = CGFloat(Double(point.totalBytes) / Double(maximum))
            let height = point.totalBytes == 0 ? 5 : max(5, plotRect.height * ratio)
            let rect = NSRect(x: centerX - barWidth / 2, y: plotRect.minY, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }

        drawGridLine(y: plotRect.maxY, label: ByteFormatter.axis(maximum), in: plotRect)
        drawGridLine(y: plotRect.midY, label: ByteFormatter.axis(maximum / 2), in: plotRect)
        drawXAxis(in: plotRect)
    }

    private func drawGridLine(y: CGFloat, label: String, in plotRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: plotRect.minX, y: y))
        path.line(to: NSPoint(x: plotRect.maxX, y: y))
        path.lineWidth = 1
        path.setLineDash([2, 3], count: 2, phase: 0)
        DashboardPalette.chartGridLine(effectiveAppearance).setStroke()
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: DashboardPalette.chartAxisLabel(effectiveAppearance),
        ]
        let labelSize = (label as NSString).size(withAttributes: attributes)
        let labelPoint = NSPoint(x: bounds.maxX - labelSize.width, y: y - 6)
        (label as NSString).draw(at: labelPoint, withAttributes: attributes)
    }

    private func drawXAxis(in plotRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: DashboardPalette.chartAxisLabel(effectiveAppearance),
        ]

        let labels: [(Int, String)]
        if range == .today {
            labels = [(0, "12AM"), (6, "6AM"), (12, "12PM"), (18, "6PM")]
        } else {
            let last = max(points.count - 1, 0)
            labels = [(0, "1"), (min(7, last), "8"), (min(14, last), "15"), (min(21, last), "22")]
        }

        for (index, text) in labels {
            let denominator = CGFloat(max(points.count - 1, 1))
            let centerX = plotRect.minX + plotRect.width * CGFloat(index) / denominator
            let size = (text as NSString).size(withAttributes: attributes)
            let idealX = centerX - size.width / 2
            let clampedX = min(max(idealX, plotRect.minX), plotRect.maxX - size.width)
            (text as NSString).draw(at: NSPoint(x: clampedX, y: 1), withAttributes: attributes)
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
        if bytes >= 1_000_000_000_000 {
            let scaled = value / 1_000_000_000_000
            return formattedAxis(scaled, unit: "TB")
        }
        if bytes >= 1_000_000_000 {
            let scaled = value / 1_000_000_000
            return formattedAxis(scaled, unit: "GB")
        }
        if bytes >= 1_000_000 {
            let scaled = value / 1_000_000
            return formattedAxis(scaled, unit: "MB")
        }
        if bytes >= 1_000 {
            let scaled = value / 1_000
            return formattedAxis(scaled, unit: "KB")
        }
        return "\(bytes) B"
    }

    private static func formattedAxis(_ value: Double, unit: String) -> String {
        let format = value.rounded() == value || value >= 10 ? "%.0f %@" : "%.1f %@"
        return String(format: format, value, unit)
    }
}
