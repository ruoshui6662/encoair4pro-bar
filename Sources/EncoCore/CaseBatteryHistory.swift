import Foundation

public struct CaseBatteryReading: Codable, Equatable {
    public let percent: Int
    public let reportedAt: Date
    public init(percent: Int, reportedAt: Date) { self.percent = percent; self.reportedAt = reportedAt }
}

public struct CaseBatteryHistory {
    public private(set) var reading: CaseBatteryReading?
    public init(restoring reading: CaseBatteryReading? = nil) {
        self.reading = reading.flatMap { (1...100).contains($0.percent) ? $0 : nil }
    }
    public mutating func receive(_ value: BatteryValue?, at date: Date) {
        // Air4 Pro reports case 0 when no case charge is available over the buds.
        // A missing/unknown report must not replace an earlier open-case reading.
        guard let percent = value?.percent, (1...100).contains(percent) else { return }
        reading = CaseBatteryReading(percent: percent, reportedAt: date)
    }
}
