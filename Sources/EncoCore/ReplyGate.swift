public struct ReplyGate {
    private var latest: [UInt16: UInt8] = [:]
    public init() {}
    public mutating func issued(command: UInt16, sequence: UInt8) { latest[command] = sequence }
    public func accepts(_ frame: Frame) -> Bool {
        frame.command & 0x8000 == 0 || latest[frame.command & 0x7FFF] == frame.sequence
    }
}
