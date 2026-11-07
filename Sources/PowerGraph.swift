import AppKit

final class PowerGraphView: NSView {
    var samples: [PowerSample] = []
    var now = Date()
    private let usageColor = NSColor.systemTeal
    private let inputColor = NSColor.systemOrange

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let plot = NSRect(x: 50, y: 54, width: bounds.width - 72, height: bounds.height - 126)
        let visible = samples.filter { now.timeIntervalSince($0.time) <= PowerHistory.duration }
        let maxValue = visible.flatMap { [$0.input, $0.usage].compactMap { $0 } }.max() ?? 0
        let ceiling = max(10, ceil(maxValue / 10) * 10)
        let latest = visible.last

        func text(_ string: String, x: CGFloat, y: CGFloat, color: NSColor = .secondaryLabelColor, size: CGFloat = 11, weight: NSFont.Weight = .regular) {
            (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
                .foregroundColor: color
            ])
        }
        func value(_ watts: Double?) -> String { watts.map { String(format: "%.1f W", $0) } ?? "— W" }

        text("Mac use", x: 22, y: bounds.height - 30, color: usageColor, size: 12, weight: .medium)
        text(value(latest?.usage), x: 22, y: bounds.height - 52, color: .labelColor, size: 19, weight: .semibold)
        text("Charger input", x: bounds.width / 2 + 2, y: bounds.height - 30, color: inputColor, size: 12, weight: .medium)
        text(value(latest?.input), x: bounds.width / 2 + 2, y: bounds.height - 52, color: .labelColor, size: 19, weight: .semibold)

        for step in 0...4 {
            let fraction = Double(step) / 4
            let y = plot.minY + CGFloat(fraction) * plot.height
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.lineWidth = 0.5
            line.stroke()
            let tick = ceiling * fraction
            let label = String(format: tick.rounded() == tick ? "%.0f" : "%.1f", tick)
            let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            text(label, x: plot.minX - width - 10, y: y - 6)
        }
        text("W", x: 18, y: plot.maxY + 5)
        for (index, label) in ["−2m", "−90s", "−60s", "−30s", "Now"].enumerated() {
            let x = plot.minX + CGFloat(index) * plot.width / 4
            text(label, x: x - (index == 4 ? 23 : 12), y: plot.minY - 22)
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot.insetBy(dx: -2, dy: -2)).addClip()
        func series(_ key: KeyPath<PowerSample, Double?>, color: NSColor) {
            let path = NSBezierPath()
            var previous: PowerSample?
            var lastPoint: NSPoint?
            for sample in visible {
                guard let watts = sample[keyPath: key] else { previous = nil; continue }
                let age = now.timeIntervalSince(sample.time)
                let point = NSPoint(x: plot.maxX - CGFloat(age / PowerHistory.duration) * plot.width,
                                    y: plot.minY + CGFloat(watts / ceiling) * plot.height)
                if let previous, sample.time.timeIntervalSince(previous.time) <= 5 { path.line(to: point) }
                else { path.move(to: point) }
                previous = sample
                lastPoint = point
            }
            color.setStroke()
            path.lineWidth = 2
            path.lineJoinStyle = .round
            path.stroke()
            if let point = lastPoint, let last = previous, now.timeIntervalSince(last.time) <= 5 {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
            }
        }
        series(\.input, color: inputColor)
        series(\.usage, color: usageColor)
        NSGraphicsContext.restoreGraphicsState()

        if visible.count < 2 {
            text("Collecting power history…", x: plot.midX - 82, y: plot.midY, size: 12)
        }
        let available = visible.first.map { min(120, max(0, Int(now.timeIntervalSince($0.time)))) } ?? 0
        text(available < 118 ? "Collecting · \(available)s of 2 minutes" : "Last 2 minutes", x: 22, y: 12)
        text("2s updates", x: bounds.width - 88, y: 12)
        setAccessibilityLabel("Power history over the last two minutes. Mac use \(value(latest?.usage)); charger input \(value(latest?.input)).")
    }
}
