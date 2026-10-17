import Foundation

/// Air4 Pro: query 8109 has status/count/pairs; push 0204 event 02 has count/pairs.
/// Bit 0 means out of case, bit 1 in ear; lid and reminder bits are independent.
public struct WearingReport {
    public let inEar: [UInt8: Bool]
    public var bothOutOfEar: Bool { inEar[1] == false && inEar[2] == false }

    public static func parse(_ frame: Frame) -> WearingReport? {
        let p = frame.payload
        guard (frame.command == 0x8109 && p.first == 0)
                || (frame.command == 0x0204 && p.first == 2),
              p.count >= 2, p.count == 2 + Int(p[1]) * 2 else { return nil }
        var values: [UInt8: Bool] = [:]
        for offset in stride(from: 2, to: p.count, by: 2) {
            let component = p[offset], raw = p[offset + 1]
            guard component == 1 || component == 2 else { continue }
            guard values[component] == nil else { return nil }
            guard raw & 0xF0 == 0, [UInt8(0), 1, 3, 4, 5, 7].contains(raw & 7) else { continue }
            values[component] = raw & 3 == 3
        }
        return values.isEmpty ? nil : WearingReport(inEar: values)
    }
}
