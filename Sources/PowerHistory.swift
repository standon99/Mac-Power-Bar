import Foundation

struct PowerSample {
    let time: Date
    let input: Double?
    let usage: Double?
}

struct PowerHistory {
    private(set) var samples: [PowerSample] = []
    static let duration: TimeInterval = 120

    mutating func append(time: Date = Date(), input: Double?, usage: Double?) {
        func valid(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && (0...500).contains($0) ? $0 : nil }
        }
        let sample = PowerSample(time: time, input: valid(input), usage: valid(usage))
        // Source notifications and opening the menu can cause extra reads.
        // Coalesce those without adding another timer or unbounded history.
        if let last = samples.last, time.timeIntervalSince(last.time) < 1 {
            samples[samples.count - 1] = sample
        } else { samples.append(sample) }
        samples.removeAll { $0.time < time.addingTimeInterval(-Self.duration) }
        if samples.count > 128 { samples.removeFirst(samples.count - 128) }
    }
}
