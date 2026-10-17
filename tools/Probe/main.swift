import Foundation
import EncoCore

// Narrow hardware diagnostic: only status queries and the documented noise-control command.
// This executable has no AppKit UI and shares the production transport and frame codec.
let transport = RFCOMMTransport()
var sequence: UInt8 = 0
var original: [UInt8: UInt16] = [:]
let args = CommandLine.arguments
transport.synchronousDiagnosticOpen = args.contains("--sync")
let payload: [UInt8]? = args.firstIndex(of: "--payload").flatMap { index in
    guard args.indices.contains(index + 1) else { return nil }
    let parts = args[index + 1].split(separator: ",")
    let bytes = parts.compactMap { UInt8($0, radix: 16) }
    guard bytes.count == parts.count, (3...4).contains(bytes.count), bytes[0] == 1,
          [UInt8(1), 2].contains(bytes[1]) else { return nil }
    let value = UInt16(bytes[2]) | (bytes.count == 4 ? UInt16(bytes[3]) << 8 : 0)
    guard [UInt16(1), 2, 4, 8, 16, 32, 64, 128, 256].contains(value) else { return nil }
    return bytes
}
if args.contains("--payload") && payload == nil { fputs("Invalid noise-control payload\n", stderr); exit(2) }

func send(_ command: UInt16, _ bytes: [UInt8] = []) {
    sequence += 1
    do {
        try transport.send(Frame(command: command, sequence: sequence, payload: bytes))
        print(String(format: "TX %04X #%02X ", command, sequence), bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        fflush(stdout)
    } catch { print("ERROR", error); fflush(stdout) }
}
func later(_ seconds: Double, _ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
}
transport.log = { print($0); fflush(stdout) }
transport.onError = { print("ERROR", $0); fflush(stdout) }
transport.onFrame = { frame in
    print(String(format: "RX %04X #%02X ", frame.command, frame.sequence), frame.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
    fflush(stdout)
    let p = frame.payload
    if frame.command == 0x810C, frame.sequence <= 5, (4...5).contains(p.count), p[0] == 0, p[1] == 1 {
        original[p[2]] = UInt16(p[3]) | (p.count == 5 ? UInt16(p[4]) << 8 : 0)
    }
}
transport.onOpen = {
    send(0x0100)
    later(0.3) { send(0x0103) }
    later(0.6) { send(0x0106) }
    later(0.9) { send(0x010C, [1, 1]) }
    later(1.2) { send(0x010C, [1, 2]) }
    if let payload {
        later(2.2) {
            guard original[payload[1]] != nil else { print("No original mode; skipping write"); return }
            send(0x0404, payload)
        }
        for time in [2.8, 4.0, 5.5] {
            later(time) { send(0x010C, [1, 1]) }
            later(time + 0.3) { send(0x010C, [1, 2]) }
        }
        later(7) {
            guard let old = original[payload[1]] else { return }
            var restore: [UInt8] = [1, payload[1], UInt8(truncatingIfNeeded: old)]
            if payload.count == 4 || old > 255 { restore.append(UInt8(old >> 8)) }
            print("RESTORE original mode")
            send(0x0404, restore)
        }
        later(7.8) { send(0x010C, [1, 1]) }
        later(8.1) { send(0x010C, [1, 2]) }
    }
    later(10) { transport.stop(); exit(0) }
}
transport.connect()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
transport.stop()
