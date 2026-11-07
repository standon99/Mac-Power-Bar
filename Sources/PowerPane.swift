import AppKit

private final class TopDownView: NSView {
    override var isFlipped: Bool { true }
}

final class PowerPaneController: NSViewController {
    var onResize: ((NSSize) -> Void)?
    var onLogin: (() -> Void)?
    var onQuit: (() -> Void)?
    private(set) var graphExpanded = false
    private let graph = PowerGraphView()
    private var samples: [PowerSample] = []
    private var sampledAt = Date()
    private let source = NSTextField(labelWithString: "Reading power…")
    private let macValue = NSTextField(labelWithString: "— W")
    private let chargerValue = NSTextField(labelWithString: "— W")
    private let batteryValue = NSTextField(labelWithString: "—")
    private let flowValue = NSTextField(labelWithString: "— W")
    private let capacityValue = NSTextField(labelWithString: "— W")
    private let graphToggle = NSButton(checkboxWithTitle: "Graph · Last 2 minutes", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let quit = NSButton(title: "Quit", target: nil, action: nil)
    private let footer = NSTextField(labelWithString: "Updates every 2 seconds")

    override func loadView() {
        view = TopDownView(frame: NSRect(x: 0, y: 0, width: 440, height: 288))
        let heading = NSTextField(labelWithString: "PowerBar")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.frame = NSRect(x: 18, y: 14, width: 390, height: 20)
        view.addSubview(heading)
        source.font = .systemFont(ofSize: 11)
        source.textColor = .secondaryLabelColor
        source.frame = NSRect(x: 18, y: 37, width: 402, height: 16)
        view.addSubview(source)
        let rows: [(String, NSTextField)] = [
            ("Mac power use", macValue), ("Charger input", chargerValue),
            ("Battery", batteryValue), ("Battery power", flowValue),
            ("Charger capacity", capacityValue)
        ]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(65 + index * 24)
            let label = NSTextField(labelWithString: row.0)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 18, y: y, width: 155, height: 18)
            view.addSubview(label)
            row.1.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            row.1.alignment = .right
            row.1.frame = NSRect(x: 170, y: y, width: 250, height: 18)
            view.addSubview(row.1)
        }
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 18, y: 190, width: 404, height: 1)
        view.addSubview(separator)
        graphToggle.target = self
        graphToggle.action = #selector(toggleGraph)
        graphToggle.frame = NSRect(x: 16, y: 201, width: 300, height: 24)
        view.addSubview(graphToggle)
        graph.frame = NSRect(x: 0, y: 235, width: 440, height: 260)
        graph.isHidden = true
        view.addSubview(graph)
        login.target = self
        login.action = #selector(toggleLogin)
        view.addSubview(login)
        quit.target = self
        quit.action = #selector(quitApp)
        quit.bezelStyle = .rounded
        view.addSubview(quit)
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        view.addSubview(footer)
        resizePane()
    }

    private func resizePane() {
        let size = NSSize(width: 440, height: graphExpanded ? 556 : 288)
        view.setFrameSize(size)
        graph.isHidden = !graphExpanded
        graphToggle.state = graphExpanded ? .on : .off
        login.frame = NSRect(x: 16, y: size.height - 47, width: 220, height: 22)
        quit.frame = NSRect(x: 352, y: size.height - 49, width: 72, height: 26)
        footer.frame = NSRect(x: 18, y: size.height - 22, width: 400, height: 15)
        preferredContentSize = size
        onResize?(size)
    }

    @objc private func toggleGraph() {
        setGraphExpanded(!graphExpanded)
    }

    func setGraphExpanded(_ expanded: Bool) {
        graphExpanded = expanded
        resizePane()
        if graphExpanded { updateGraph() }
    }
    @objc private func toggleLogin() { onLogin?() }
    @objc private func quitApp() { onQuit?() }

    private func updateGraph() {
        graph.samples = samples
        graph.now = sampledAt
        graph.needsDisplay = true
    }

    func update(reading: PowerReading?, input: Double?, usage: Double?, samples: [PowerSample], now: Date, loginEnabled: Bool) {
        _ = view
        self.samples = samples
        sampledAt = now
        func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "Updating…" }
        macValue.stringValue = watts(usage)
        chargerValue.stringValue = reading?.externalPower == true ? watts(input) : "Not connected"
        if let reading {
            let live = reading.liveSystem && (!reading.externalPower || reading.liveInput)
            source.stringValue = "\(reading.externalPower ? "Connected to power" : "Running on battery") · \(live ? "Live readings" : "Delayed readings")"
            batteryValue.stringValue = "\(reading.percentage.map(String.init) ?? "—")% · \(reading.charging ? "Charging" : reading.externalPower ? "Not charging" : "Discharging")"
            if let power = reading.batteryWatts { flowValue.stringValue = "\(watts(abs(power))) \(power >= 0 ? "in" : "out")" }
            else { flowValue.stringValue = "Unavailable" }
            capacityValue.stringValue = reading.externalPower ? watts(reading.adapterRating) : "—"
        } else {
            source.stringValue = "Power readings unavailable"
            batteryValue.stringValue = "—"
            flowValue.stringValue = "—"
            capacityValue.stringValue = "—"
        }
        login.state = loginEnabled ? .on : .off
        footer.stringValue = "2s updates · Last read \(now.formatted(date: .omitted, time: .standard))"
        if graphExpanded { updateGraph() }
    }
}
