import Foundation

public struct Frame: Equatable {
    public let command: UInt16
    public let sequence: UInt8
    public let payload: [UInt8]
    public init(command: UInt16, sequence: UInt8, payload: [UInt8] = []) {
        self.command = command; self.sequence = sequence; self.payload = payload
    }
    public func encoded() throws -> [UInt8] {
        guard payload.count <= 248 else { throw ProtocolError.oversizedPayload }
        return [0xAA, UInt8(payload.count + 7), 0, 0,
                UInt8(truncatingIfNeeded: command), UInt8(command >> 8), sequence,
                UInt8(payload.count), 0] + payload
    }
}
public enum ProtocolError: Error { case oversizedPayload }
public enum ModeCommandFormat { case parentByte, parentWord, childWord }
public enum Commands {
    public static func queryANC(sequence: UInt8) -> Frame { Frame(command: 0x010C, sequence: sequence, payload: [1, 1]) }
    public static func setMode(_ mode: NoiseMode, sequence: UInt8, format: ModeCommandFormat) -> Frame {
        let child: UInt16
        switch mode { case .off: child = 8; case .cancellation: child = 16; case .transparency: child = 256 }
        switch format {
        case .parentByte:
            return Frame(command: 0x0404, sequence: sequence, payload: [1, 1, mode.commandValue])
        case .parentWord:
            return Frame(command: 0x0404, sequence: sequence, payload: [1, 1, mode.commandValue, 0])
        case .childWord:
            return Frame(command: 0x0404, sequence: sequence, payload: [1, 2, UInt8(truncatingIfNeeded: child), UInt8(child >> 8)])
        }
    }
}
public struct FrameDecoder {
    private var buffer: [UInt8] = []
    public init() {}
    public mutating func append(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0xAA) else { buffer.removeAll(); break }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 2 else { break }
            let length = Int(buffer[1]) + 2
            if length < 9 { buffer.removeFirst(); continue }
            guard buffer.count >= 9 else { break }
            let payloadLength = Int(buffer[7]) | Int(buffer[8]) << 8
            guard buffer[2] == 0, buffer[3] == 0, payloadLength + 9 == length else {
                buffer.removeFirst(); continue
            }
            guard buffer.count >= length else { break }
            frames.append(Frame(command: UInt16(buffer[4]) | UInt16(buffer[5]) << 8,
                                sequence: buffer[6], payload: Array(buffer[9..<length])))
            buffer.removeFirst(length)
        }
        return frames
    }
}
public struct BatteryValue: Equatable {
    public let percent: Int?
    public let charging: Bool
    public init(percent: Int?, charging: Bool) { self.percent = percent; self.charging = charging }
}
public struct BatteryReport {
    public let values: [UInt8: BatteryValue]
    public static func parse(_ frame: Frame) -> BatteryReport? {
        var payload = frame.payload
        if frame.command == 0x0204 {
            guard payload.count >= 2, payload[0] == 1,
                  payload.count == 2 + Int(payload[1]) * 2 else { return nil }
            payload = Array(payload.dropFirst(2))
        } else if frame.command == 0x8106 {
            guard payload.count >= 2, payload[0] == 0,
                  payload.count == 2 + Int(payload[1]) * 2 else { return nil }
            payload = Array(payload.dropFirst(2))
        } else { return nil }
        guard !payload.isEmpty, payload.count.isMultiple(of: 2) else { return nil }
        var values: [UInt8: BatteryValue] = [:]
        for offset in stride(from: 0, to: payload.count, by: 2) {
            let index = payload[offset], raw = payload[offset + 1]
            guard (1...3).contains(index) else { continue }
            let percent = Int(raw & 0x7F)
            values[index] = BatteryValue(percent: percent <= 100 ? percent : nil, charging: raw & 0x80 != 0)
        }
        return values.isEmpty ? nil : BatteryReport(values: values)
    }
}
public struct ANCReading {
    public let bitmap: UInt16
    public static func parse(_ frame: Frame) -> ANCReading? {
        var payload = frame.payload
        if frame.command == 0x0204 {
            // Event 02 is wearing and 04 is fit-test data, even if their bytes
            // happen to resemble the ANC envelope. Only event 03 is a mode.
            guard payload.first == 3 else { return nil }
            payload.removeFirst()
        } else if frame.command == 0x810C {
            guard payload.first == 0 else { return nil }
            payload.removeFirst()
        } else { return nil }
        guard (3...4).contains(payload.count), payload[0] == 1, payload[1] == 1 else { return nil }
        let value = UInt16(payload[2]) | (payload.count == 4 ? UInt16(payload[3]) << 8 : 0)
        guard value.nonzeroBitCount == 1 else { return nil }
        return ANCReading(bitmap: value)
    }
}
public struct CommandConfirmation {
    private let targets: Set<UInt16>
    private let querySequence: UInt8
    private let deadline: Date
    private var active = true
    public init(mode: NoiseMode, querySequence: UInt8, deadline: Date = .distantFuture) {
        self.targets = mode.reportedBitmaps; self.querySequence = querySequence; self.deadline = deadline
    }
    public init(target: UInt16, querySequence: UInt8, deadline: Date = .distantFuture) {
        self.targets = [target]; self.querySequence = querySequence
        self.deadline = deadline
    }
    public mutating func cancel() { active = false }
    public mutating func accept(_ frame: Frame, now: Date = Date()) -> Bool {
        guard active, now < deadline, frame.command == 0x810C,
              frame.sequence == querySequence, let reading = ANCReading.parse(frame), targets.contains(reading.bitmap) else { return false }
        active = false
        return true
    }
}
