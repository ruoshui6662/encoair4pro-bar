import AppKit
import EncoCore

/// Explicit developer-only diagnostics, hosted by AppKit so Bluetooth callbacks
/// have the same event loop and privacy identity as the normal application.
final class ProtocolProbe {
    private let transport = RFCOMMTransport()
    private var sequence: UInt8 = 0
    private let output: URL
    private let payload: [UInt8]?

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--protocol-probe"), arguments.indices.contains(index + 1) else { return nil }
        output = URL(fileURLWithPath: arguments[index + 1])
        if let index = arguments.firstIndex(of: "--payload") {
            guard arguments.indices.contains(index + 1) else { return nil }
            let parts = arguments[index + 1].split(separator: ",")
            let bytes = parts.compactMap { UInt8($0, radix: 16) }
            guard bytes.count == parts.count, (3...4).contains(bytes.count), bytes[0] == 1,
                  [UInt8(1), 2].contains(bytes[1]) else { return nil }
            let value = UInt16(bytes[2]) | (bytes.count == 4 ? UInt16(bytes[3]) << 8 : 0)
            guard [UInt16(1), 2, 4, 8, 16, 32, 64, 128, 256].contains(value) else { return nil }
            payload = bytes
        } else { payload = nil }
        try? Data().write(to: output)
    }

    func start() {
        transport.log = { [weak self] in self?.record($0) }
        transport.onError = { [weak self] in self?.record("ERROR " + $0) }
        transport.onFrame = { [weak self] frame in
            // Unsolicited device-list events include addresses and names.
            // Keep only the status fields used by this narrow diagnostic.
            let response = [UInt16(0x8100), 0x8103, 0x8106, 0x8109, 0x810C, 0x8404].contains(frame.command)
            let statusEvent = frame.command == 0x0204 && frame.payload.first.map { [UInt8(1), 2, 3, 4].contains($0) } == true
            guard response || statusEvent else { return }
            self?.record(String(format: "RX %04X #%02X ", frame.command, frame.sequence) + frame.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        transport.onOpen = { [weak self] in self?.readAndTest() }
        transport.connect()
        later(30) { [weak self] in self?.stop(); NSApp.terminate(nil) }
    }

    func stop() { transport.stop() }

    private func readAndTest() {
        send(0x0100)
        later(0.3) { self.send(0x0103) }
        later(0.6) { self.send(0x0106) }
        later(0.9) { self.send(0x0109) }
        later(1.2) { self.send(0x010C, [1, 1]) }
        later(1.5) { self.send(0x010C, [1, 2]) }
        later(1.8) { self.send(0x010C, [4, 1]) }
        if let payload {
            later(2.2) { self.send(0x0404, payload) }
            for second in [3.0, 4.5, 6.0] {
                later(second) { self.send(0x010C, [1, 1]) }
                later(second + 0.3) { self.send(0x010C, [1, 2]) }
            }
        }
        later(8) { [weak self] in self?.stop(); NSApp.terminate(nil) }
    }

    private func send(_ command: UInt16, _ bytes: [UInt8] = []) {
        sequence += 1
        do {
            try transport.send(Frame(command: command, sequence: sequence, payload: bytes))
            record(String(format: "TX %04X #%02X ", command, sequence) + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        } catch { record("ERROR \(error)") }
    }
    private func later(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
    private func record(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8), let file = try? FileHandle(forWritingTo: output) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
    }
}
