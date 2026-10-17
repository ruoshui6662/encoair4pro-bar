import Foundation

public enum BatterySyncAction: Equatable { case none, query, reconnect }

public struct BatterySync {
    private var lastQuery: Date?
    private var pending: (sequence: UInt8, deadline: Date)?
    public init() {}
    public mutating func queried(sequence: UInt8, at date: Date) {
        lastQuery = date
        pending = (sequence, date.addingTimeInterval(8))
    }
    public mutating func received(sequence: UInt8) {
        if pending?.sequence == sequence { pending = nil }
    }
    public func action(at date: Date, panelVisible: Bool, blocked: Bool, urgent: Bool = false) -> BatterySyncAction {
        guard !blocked else { return .none }
        if let pending { return date >= pending.deadline ? .reconnect : .none }
        let interval: Double = urgent ? 1 : panelVisible ? 5 : 30
        return lastQuery.map { date.timeIntervalSince($0) >= interval } ?? true ? .query : .none
    }
}

public enum CaseLid {
    public static func isOpen(in frame: Frame) -> Bool? {
        let p = frame.payload
        guard (frame.command == 0x0204 && p.first == 2) || (frame.command == 0x8109 && p.first == 0),
              p.count >= 2, p.count == 2 + Int(p[1]) * 2 else { return nil }
        for offset in stride(from: 2, to: p.count, by: 2) {
            if p[offset] == 3 { return p[offset + 1] & 4 != 0 }
        }
        return nil
    }
}
