import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

let plugged = PowerReading.decode([
    "ExternalConnected": true, "IsCharging": true, "Voltage": 12_000,
    "Amperage": 4_000, "CurrentCapacity": 64,
    "AdapterDetails": ["Watts": 100],
    "PowerTelemetryData": ["SystemPowerIn": 70_000, "SystemLoad": 22_000]
])
expect(plugged.menuBarWatts == 70, "Must show actual input, not the 100 W charger rating or 48 W into battery")
expect(plugged.batteryWatts == 48, "Battery charging conversion")
for current: NSNumber in [NSNumber(value: -2_000), NSNumber(value: UInt64.max - 1_999), NSNumber(value: UInt32.max - 1_999)] {
    let unplugged = PowerReading.decode([
        "ExternalConnected": false, "Voltage": 12_000, "Amperage": current,
        "PowerTelemetryData": ["SystemPowerIn": 70_000, "SystemLoad": 999_999]
    ])
    expect(unplugged.menuBarWatts == 24, "Signed battery draw, including unsigned encodings")
    expect(unplugged.inputWatts == nil, "Ignore stale input when unplugged")
}
let unavailable = PowerReading.decode(["ExternalConnected": true, "AdapterDetails": ["Watts": 100]])
expect(unavailable.menuBarWatts == nil, "Never substitute charger capacity for missing live measurement")
let zero = PowerReading.decode(["ExternalConnected": true, "IsCharging": false, "PowerTelemetryData": ["SystemPowerIn": 0]])
expect(zero.menuBarWatts == 0, "Preserve real zero readings and handle charge-paused state")
let fallback = PowerReading.decode(["ExternalConnected": true, "PowerTelemetryData": ["SystemVoltageIn": 20_000, "SystemCurrentIn": 3_500]])
expect(fallback.inputWatts == 70, "Input voltage/current fallback")
print("Passed power-source, unit-conversion, signed-current, zero, stale-value, and missing-telemetry checks.")

let now = Date(timeIntervalSince1970: 100)
var display = PowerDisplayState()
expect(display.value(for: plugged, now: now) == 70, "Normal charger display")
let changing = PowerReading.decode(["ExternalConnected": true, "Voltage": 12_000, "Amperage": 4_000], externalOverride: false)
expect(!changing.externalPower, "Current source overrides stale registry connection flag")
expect(display.value(for: changing, now: now.addingTimeInterval(1)) == nil, "Hide stale charge-direction zero immediately on unplug")
let discharging = PowerReading.decode(["ExternalConnected": false, "Voltage": 12_000, "Amperage": -2_000])
expect(display.value(for: discharging, now: now.addingTimeInterval(3)) == 24, "Show discharge as soon as sensor updates")
expect(display.value(for: zero, now: now.addingTimeInterval(4)) == nil, "Hide zero during charger negotiation on replug")
expect(display.value(for: plugged, now: now.addingTimeInterval(6)) == 70, "Show charger input immediately when available")
expect(display.value(for: zero, now: now.addingTimeInterval(7)) == nil, "Hide transient zero before source notification arrives")
expect(display.value(for: zero, now: now.addingTimeInterval(14)) == 0, "Allow a sustained real zero after settling deadline")
print("Passed plug/unplug transition, stale source, transient zero, recovery, and sustained zero checks.")
expect(PowerDisplayState.title(externalPower: true, input: 70, usage: 22) == "70.0 W  ·  ↘ 22.0 W", "Charging must show input and system use separately")
expect(PowerDisplayState.title(externalPower: false, input: nil, usage: 24) == "24.0 W", "Battery mode shows consumption once")
expect(PowerDisplayState.title(externalPower: true, input: nil, usage: 22) == "… W  ·  ↘ 22.0 W", "Pending input must not hide available consumption")
print("Passed simultaneous input/use display checks.")
let live = plugged.usingLiveSensors(input: 63.4, system: 18.7)
expect(live.inputWatts == 63.4 && live.systemWatts == 18.7, "Live sensors must replace cached values")
expect(live.liveInput && live.liveSystem, "Identify live source")
let unavailableLive = plugged.usingLiveSensors(input: .nan, system: .nan)
expect(unavailableLive.inputWatts == 70 && unavailableLive.systemWatts == 22, "Unavailable live sensors fall back to cache")
expect(!unavailableLive.liveInput && !unavailableLive.liveSystem, "Identify cached fallback honestly")
print("Passed live-sensor priority and unavailable-sensor fallback checks.")
var history = PowerHistory()
let origin = Date(timeIntervalSince1970: 1_000)
for second in stride(from: 0, through: 180, by: 2) {
    history.append(time: origin.addingTimeInterval(Double(second)), input: 70, usage: Double(second % 30))
}
expect(history.samples.count == 61, "Retain exactly the two-minute window at 2-second intervals")
expect(history.samples.first?.time == origin.addingTimeInterval(60), "Discard samples older than 120 seconds")
history.append(time: origin.addingTimeInterval(180.2), input: 65, usage: 20)
expect(history.samples.count == 60 && history.samples.last?.input == 65, "Coalesce bursts and enforce time cutoff")
history.append(time: origin.addingTimeInterval(400), input: 0, usage: 15)
expect(history.samples.count == 1, "Drop old history after a sleep gap")
history.append(time: origin.addingTimeInterval(402), input: .nan, usage: -1)
expect(history.samples.last?.input == nil && history.samples.last?.usage == nil, "Invalid samples must create graph gaps")
print("Passed two-minute history retention, notification coalescing, sleep-gap, and invalid-value checks.")
