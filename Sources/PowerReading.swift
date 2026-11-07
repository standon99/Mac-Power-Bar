import Foundation
import IOKit
import IOKit.ps

// Hide briefly inconsistent sensor values while the charger negotiates or the
// battery gauge changes direction. Never invent a wattage or hold one forever.
struct PowerDisplayState {
    private var previousExternal: Bool?
    private var previousWatts: Double?
    private var settlingUntil: Date?

    mutating func value(for reading: PowerReading, now: Date = Date()) -> Double? {
        value(externalPower: reading.externalPower, watts: reading.menuBarWatts, now: now)
    }

    mutating func value(externalPower: Bool, watts value: Double?, now: Date = Date()) -> Double? {
        let sourceChanged = previousExternal != nil && previousExternal != externalPower
        let suddenZero = value == 0 && (previousWatts ?? 0) > 0
        if sourceChanged || (suddenZero && settlingUntil == nil) {
            settlingUntil = now.addingTimeInterval(6)
        }
        previousExternal = externalPower
        if let value, value > 0 {
            settlingUntil = nil
            previousWatts = value
            return value
        }
        if let deadline = settlingUntil, now < deadline { return nil }
        settlingUntil = nil
        previousWatts = value
        return value
    }

    static func title(externalPower: Bool, input: Double?, usage: Double?) -> String {
        func format(_ watts: Double?) -> String {
            watts.map { String(format: "%.1f W", $0) } ?? "… W"
        }
        return externalPower ? "\(format(input))  ·  ↘ \(format(usage))" : format(usage)
    }
}

struct PowerReading {
    let externalPower: Bool
    let charging: Bool
    let percentage: Int?
    let inputWatts: Double?
    let systemWatts: Double?
    let batteryWatts: Double?
    let adapterRating: Double?
    var liveInput = false
    var liveSystem = false

    func usingLiveSensors(input: Double, system: Double) -> PowerReading {
        var result = self
        let validInput = input.isFinite && (0...500).contains(input)
        let validSystem = system.isFinite && (0...500).contains(system)
        result.liveInput = externalPower && validInput
        result.liveSystem = validSystem
        return PowerReading(
            externalPower: externalPower, charging: charging, percentage: percentage,
            inputWatts: result.liveInput ? input : inputWatts,
            systemWatts: validSystem ? system : systemWatts,
            batteryWatts: batteryWatts, adapterRating: adapterRating,
            liveInput: result.liveInput, liveSystem: result.liveSystem
        )
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Double? {
        guard let n = dict[key] as? NSNumber else { return nil }
        let value = n.doubleValue
        return value.isFinite ? value : nil
    }

    private static func watts(_ dict: [String: Any], _ key: String) -> Double? {
        guard let raw = number(dict, key), raw >= 0, raw <= 500_000 else { return nil }
        return raw / 1_000
    }

    static func decode(_ properties: [String: Any], externalOverride: Bool? = nil) -> PowerReading {
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = properties["AdapterDetails"] as? [String: Any] ?? [:]
        let external = externalOverride ?? (properties["ExternalConnected"] as? NSNumber)?.boolValue ?? false
        let charging = (properties["IsCharging"] as? NSNumber)?.boolValue ?? false

        // IORegistry can represent a negative battery current as an unsigned
        // 64-bit or 32-bit two's-complement number. Reject implausible values.
        var battery: Double?
        if let voltage = number(properties, "Voltage"), voltage > 0, voltage < 30_000,
           let current = properties["Amperage"] as? NSNumber {
            var milliamps = Int64(bitPattern: current.uint64Value)
            if milliamps > 100_000 {
                milliamps = Int64(Int32(truncatingIfNeeded: current.uint64Value))
            }
            if (-50_000...50_000).contains(milliamps) {
                battery = voltage * Double(milliamps) / 1_000_000
            }
        }

        var input: Double?
        if external {
            input = watts(telemetry, "SystemPowerIn")
            if input == nil, let mv = number(telemetry, "SystemVoltageIn"),
               let ma = number(telemetry, "SystemCurrentIn"),
               mv > 0, mv < 60_000, ma >= 0, ma < 20_000 {
                input = mv * ma / 1_000_000
            }
        }
        let percent = number(properties, "CurrentCapacity").flatMap {
            (0...100).contains($0) ? Int($0) : nil
        }
        let rating = number(adapter, "Watts").flatMap { (0...500).contains($0) ? $0 : nil }
        return PowerReading(
            externalPower: external, charging: charging, percentage: percent,
            inputWatts: input,
            systemWatts: external ? watts(telemetry, "SystemLoad") : battery.map { max(0, -$0) },
            batteryWatts: battery, adapterRating: external ? rating : nil
        )
    }

    static func read() -> PowerReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        // The power-source notification can precede AppleSmartBattery's update.
        // Prefer the current power-source API for the icon and direction.
        var external: Bool?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            if source as String == kIOPSACPowerValue { external = true }
            else if source as String == kIOPSBatteryPowerValue { external = false }
        }
        return decode(dictionary, externalOverride: external).usingLiveSensors(
            input: powerbar_smc_input(), system: powerbar_smc_system()
        )
    }

    var menuBarWatts: Double? { externalPower ? inputWatts : systemWatts }
    var formattedWatts: String {
        guard let watts = menuBarWatts else { return "— W" }
        return String(format: "%.1f W", watts)
    }
}
