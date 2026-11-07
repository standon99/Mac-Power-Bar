import AppKit

// Render the real AppKit pane without capturing the desktop or personal data.
// The preview uses sample data, rather than a live recording.
let now = Date(timeIntervalSince1970: 1_794_092_800)
var history = PowerHistory()
for second in stride(from: -120, through: 0, by: 2) {
    let t = Double(second + 120)
    let usage = 18 + 3 * sin(t / 11) + 2 * sin(t / 3.7) + (t > 55 && t < 82 ? 15 : 0)
    history.append(time: now.addingTimeInterval(Double(second)), input: 59 + sin(t / 14) * 2, usage: usage)
}
let latest = history.samples.last!
let input = latest.input!
let usage = latest.usage!
let reading = PowerReading.decode([
    "ExternalConnected": true, "IsCharging": true, "CurrentCapacity": 84,
    "Voltage": 12_500, "Amperage": Int((input - usage) * 1_000_000 / 12_500),
    "AdapterDetails": ["Watts": 100]
]).usingLiveSensors(input: input, system: usage)
let appearance = NSAppearance(named: .darkAqua)!
var rendered: Data?
appearance.performAsCurrentDrawingAppearance {
    let pane = PowerPaneController()
    pane.view.appearance = appearance
    pane.update(reading: reading, input: input, usage: usage, samples: history.samples, now: now, loginEnabled: false)
    pane.setGraphExpanded(true)
    let size = pane.view.bounds.size
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.windowBackgroundColor.setFill()
    NSRect(origin: .zero, size: size).fill()
    pane.view.cacheDisplay(in: pane.view.bounds, to: bitmap)
    NSGraphicsContext.restoreGraphicsState()
    rendered = bitmap.representation(using: .png, properties: [:])
}
guard let rendered else { fatalError("Couldn't render preview") }
let destination = CommandLine.arguments.dropFirst().first ?? "docs/powerbar.png"
try rendered.write(to: URL(fileURLWithPath: destination))
print(destination)
