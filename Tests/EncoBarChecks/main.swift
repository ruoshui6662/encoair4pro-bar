import Foundation
import CoreBluetooth
import EncoCore

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    if !condition() { failures += 1; print("FAIL: \(description)") }
}
func run(until predicate: () -> Bool, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
}

// Regression: reopening the menu must not disable controls while a battery
// reply is slow. The click must issue the requested mode before that reply.
let model = EarbudModel(probe: true, authorization: { .allowedAlways })
model.connect()
run(until: { model.canControl }, timeout: 1.5)
check(model.canControl, "initial identification completes before controls enable")
let connection = RFCOMMTransport.latest!
let readyAt = Date()
run(until: { Date().timeIntervalSince(readyAt) > 1.1 }, timeout: 1.2)
connection.holdBattery = true
model.refresh()
check(model.canControl, "opening an identified connected device keeps mode buttons enabled")
let beforeClick = connection.sent.count
model.setMode(.transparency)
check(connection.sent.dropFirst(beforeClick).contains { $0.command == 0x0404 && $0.payload == [1, 1, 4] },
      "mode click writes immediately despite a pending battery reply")
check(model.pendingMode == .transparency && model.currentMode == .off,
      "click is pending until a fresh mode readback confirms it")
run(until: { model.pendingMode == nil && model.currentMode == .transparency }, timeout: 0.2)
check(model.pendingMode == nil && model.currentMode == .transparency,
      "successful ACK triggers confirmation without an artificial half-second wait")
model.shutdown()

// Unknown hardware must still wait for the complete initial identification.
let initial = EarbudModel(probe: true, authorization: { .allowedAlways })
initial.connect()
RFCOMMTransport.latest!.holdBattery = true
run(until: { initial.productID != nil && initial.currentMode != nil }, timeout: 1.1)
check(!initial.canControl, "incomplete first connection remains protected")
initial.setMode(.cancellation)
check(!RFCOMMTransport.latest!.sent.contains { $0.command == 0x0404 }, "uninitialized controls send no mode write")
initial.shutdown()

let noACK = EarbudModel(probe: true, authorization: { .allowedAlways })
noACK.connect()
run(until: { noACK.canControl }, timeout: 1.5)
RFCOMMTransport.latest!.omitSetACK = true
noACK.setMode(.transparency)
run(until: { noACK.pendingMode == nil }, timeout: 0.8)
check(noACK.currentMode == .transparency && noACK.pendingMode == nil,
      "firmware without a set ACK still confirms through fallback readback")
noACK.shutdown()

let rejected = EarbudModel(probe: true, authorization: { .allowedAlways })
rejected.connect()
run(until: { rejected.canControl }, timeout: 1.5)
RFCOMMTransport.latest!.rejectSet = true
rejected.setMode(.transparency)
run(until: { rejected.pendingMode == nil }, timeout: 0.2)
check(rejected.currentMode == .off && rejected.pendingMode == nil && rejected.message?.contains("拒绝") == true,
      "rejected ACK preserves the actual mode and ends pending feedback")
rejected.shutdown()

// A valid case reading survives unknown firmware reports, but disconnected
// UI must hide it without deleting the history needed by the next connection.
let batteryDisplay = EarbudModel(probe: true, authorization: { .allowedAlways })
batteryDisplay.connect()
run(until: { batteryDisplay.canControl }, timeout: 1.5)
let batteryChannel = RFCOMMTransport.latest!
check(batteryDisplay.displayedBattery(for: 3) == nil, "unknown case report never invents a case percentage")
batteryChannel.onFrame?(Frame(command: 0x0204, sequence: 0, payload: [1, 3, 1, 100, 2, 90, 3, 83]))
check(batteryDisplay.displayedBattery(for: 3)?.percent == 83, "connected case notification appears immediately")
check(batteryDisplay.displayedBatteryDate(for: 3) != nil, "valid case reading has its own timestamp")
batteryChannel.onFrame?(Frame(command: 0x0204, sequence: 0, payload: [1, 3, 1, 100, 2, 90, 3, 0]))
check(batteryDisplay.displayedBattery(for: 3)?.percent == 83, "unavailable case report preserves last valid connected display")
batteryChannel.onError?("fixture disconnect")
check(!batteryDisplay.controlOpen && batteryDisplay.caseBattery.reading?.percent == 83, "disconnect retains valid history internally")
check(batteryDisplay.displayedBattery(for: 3) == nil, "disconnected case column hides retained history")
check(batteryDisplay.displayedBatteryDate(for: 3) == nil, "disconnected tooltip hides historical timestamp")
check(batteryDisplay.displayedBattery(for: 1) == nil && batteryDisplay.displayedBattery(for: 2) == nil,
      "all three columns consistently show unknown while disconnected")
batteryDisplay.connect()
run(until: { batteryDisplay.canControl }, timeout: 1.5)
RFCOMMTransport.latest!.onFrame?(Frame(command: 0x0204, sequence: 0, payload: [1, 1, 3, 74]))
check(batteryDisplay.displayedBattery(for: 3)?.percent == 74, "new connection accepts and shows a fresh case report")
batteryDisplay.shutdown()

// Air4 Pro capture: both buds report state 1 (out of case, out of ear),
// SET is ACKed with 00 but the subsequent mode read remains Off.
let outOfEar = EarbudModel(probe: true, authorization: { .allowedAlways })
outOfEar.connect()
run(until: { outOfEar.canControl }, timeout: 1.5)
let wearChannel = RFCOMMTransport.latest!
wearChannel.wearingPayload = [0, 3, 1, 1, 2, 1, 3, 4]
wearChannel.ignoreModeSet = true
outOfEar.setMode(.transparency)
run(until: { outOfEar.pendingMode == nil }, timeout: 0.3)
check(outOfEar.pendingMode == nil && outOfEar.message?.contains("佩戴") == true,
      "ACKed but ignored out-of-ear switch ends promptly with an actionable wearing message")
check(outOfEar.currentMode == .off, "out-of-ear rejection never invents a successful mode")
wearChannel.wearingPayload = [0, 3, 1, 3, 2, 3, 3, 4]
wearChannel.ignoreModeSet = false
outOfEar.setMode(.transparency)
run(until: { outOfEar.pendingMode == nil }, timeout: 0.3)
check(outOfEar.currentMode == .transparency && outOfEar.pendingMode == nil,
      "the next click after wearing succeeds without reconnecting or waiting for a stale timeout")
wearChannel.onFrame?(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 1, 1, 1]))
check(outOfEar.currentMode == .transparency,
      "partial out-of-ear notification never masquerades as the Off mode")
outOfEar.shutdown()

let wearUnknown = EarbudModel(probe: true, authorization: { .allowedAlways })
wearUnknown.connect()
run(until: { wearUnknown.canControl }, timeout: 1.5)
RFCOMMTransport.latest!.wearingPayload = nil
wearUnknown.setMode(.transparency)
run(until: { wearUnknown.pendingMode == nil }, timeout: 0.3)
check(wearUnknown.currentMode == .transparency && wearUnknown.pendingMode == nil,
      "missing wear query never delays or blocks a successful actual mode readback")
wearUnknown.shutdown()

// A newer reinsertion push supersedes the operation's out-of-ear query.
// Delay real mode readback to reproduce the ordering observed in hardware.
let reinsertion = EarbudModel(probe: true, authorization: { .allowedAlways })
reinsertion.connect()
run(until: { reinsertion.canControl }, timeout: 1.5)
let changingWear = RFCOMMTransport.latest!
changingWear.holdModeReply = true
changingWear.ignoreModeSet = true
changingWear.wearingPayload = [0, 3, 1, 1, 2, 1, 3, 4]
reinsertion.setMode(.transparency)
run(until: { reinsertion.inEar[1] == false && changingWear.sent.last?.command == 0x010C }, timeout: 0.2)
let delayedQuery = changingWear.sent.last(where: { $0.command == 0x010C })!.sequence
changingWear.onFrame?(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 1, 1, 3]))
changingWear.onFrame?(Frame(command: 0x810C, sequence: delayedQuery, payload: [0, 1, 1, 1]))
check(reinsertion.pendingMode == .transparency && reinsertion.message == nil,
      "newer in-ear push invalidates out-of-ear failure evidence before delayed mode readback")
reinsertion.shutdown()

let wearRejected = EarbudModel(probe: true, authorization: { .allowedAlways })
wearRejected.connect()
run(until: { wearRejected.canControl }, timeout: 1.5)
RFCOMMTransport.latest!.setACKStatus = 14
wearRejected.setMode(.cancellation)
run(until: { wearRejected.pendingMode == nil }, timeout: 0.2)
check(wearRejected.message?.contains("佩戴") == true && wearRejected.currentMode == .off,
      "wear-related firmware rejection explains the required action")
wearRejected.shutdown()
print("Model latency checks: \(failures) failures")
exit(failures == 0 ? 0 : 1)
