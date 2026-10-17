import Foundation
import EncoCore

// Only the physical Bluetooth boundary is replaced. EarbudModel, reply gates,
// timers and protocol parsers run unchanged against captured Air4 Pro payloads.
final class RFCOMMTransport {
    static var latest: RFCOMMTransport?
    var onOpen: (() -> Void)?
    var onDeviceSelected: ((String) -> Void)?
    var onChannelOpening: (() -> Void)?
    var onFrame: ((Frame) -> Void)?
    var onError: ((String) -> Void)?
    var log: ((String) -> Void)?
    var sent: [Frame] = []
    var holdBattery = false
    var omitSetACK = false
    var rejectSet = false
    var setACKStatus: UInt8 = 0
    var ignoreModeSet = false
    var holdModeReply = false
    var wearingPayload: [UInt8]? = [0, 3, 1, 3, 2, 3, 3, 4]
    private var mode: UInt8 = 1

    func connect() { Self.latest = self; onOpen?() }
    func stop() { onFrame = nil }
    func send(_ frame: Frame) throws {
        sent.append(frame)
        let payload: [UInt8]
        switch frame.command {
        case 0x0103: payload = [0, 0x10, 0x7C, 0x06]
        case 0x0106:
            if holdBattery { return }
            payload = [0, 3, 1, 100, 2, 100, 3, 0]
        case 0x010C:
            if holdModeReply { return }
            payload = [0, 1, 1, mode]
        case 0x0109:
            guard let wearingPayload else { return }
            payload = wearingPayload
        case 0x0404:
            if rejectSet {
                payload = [1]
                break
            }
            if setACKStatus != 0 { payload = [setACKStatus]; break }
            if !ignoreModeSet { mode = frame.payload.last ?? mode }
            if omitSetACK { return }
            payload = [0]
        default: return
        }
        let reply = Frame(command: frame.command | 0x8000, sequence: frame.sequence, payload: payload)
        DispatchQueue.main.async { [weak self] in self?.onFrame?(reply) }
    }
}
