import Foundation
import CoreGraphics
import EncoCore

var failures = 0
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { failures += 1; print("FAIL \(file):\(line): \(a) != \(b)") } }
func XCTAssertNil<T>(_ value: T?, line: UInt = #line) { if value != nil { failures += 1; print("FAIL nil at \(line)") } }
func XCTAssertFalse(_ value: Bool, line: UInt = #line) { XCTAssertEqual(value, false, line: line) }
func XCTAssertTrue(_ value: Bool, line: UInt = #line) { XCTAssertEqual(value, true, line: line) }
struct CheckError: Error {}
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { failures += 1; throw CheckError() }; return value }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, line: UInt = #line) { do { _ = try expression(); failures += 1; print("FAIL expected throw at \(line)") } catch {} }

final class ProtocolTests {
    func testLegacyMigrationOnlySelectsOwnedBundleAtExactLocation() throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: home) }
        let legacy = home.appendingPathComponent("Applications/EncoBar.app")
        let contents = legacy.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = contents.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "other.app"], format: .xml, options: 0).write(to: info)
        XCTAssertNil(UninstallLayout.legacyApplication(home: home))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.encobar.air4pro"], format: .xml, options: 0).write(to: info)
        XCTAssertEqual(UninstallLayout.legacyApplication(home: home)?.path, legacy.path)
        let elsewhere = home.appendingPathComponent("SourceBackup.app")
        try manager.moveItem(at: legacy, to: elsewhere)
        try manager.createSymbolicLink(at: legacy, withDestinationURL: elsewhere)
        XCTAssertNil(UninstallLayout.legacyApplication(home: home))
        try manager.removeItem(at: home.appendingPathComponent("Applications"))
        let linkedApps = home.appendingPathComponent("LinkedApplications")
        try manager.createDirectory(at: linkedApps, withIntermediateDirectories: true)
        try manager.moveItem(at: elsewhere, to: linkedApps.appendingPathComponent("EncoBar.app"))
        try manager.createSymbolicLink(at: home.appendingPathComponent("Applications"), withDestinationURL: linkedApps)
        XCTAssertNil(UninstallLayout.legacyApplication(home: home))
    }

    func testSystemUninstallRejectsOtherApplicationsAndQuotesUserPath() throws {
        let home = URL(fileURLWithPath: "/Users/Example User", isDirectory: true)
        let token = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        XCTAssertNil(UninstallLayout.systemRemovalCommand(application: home.appendingPathComponent("Applications/EncoBar.app"), home: home, token: token))
        XCTAssertNil(UninstallLayout.systemRemovalCommand(application: URL(fileURLWithPath: "/Applications/Other.app"), home: home, token: token))
        let command = try XCTUnwrap(UninstallLayout.systemRemovalCommand(application: URL(fileURLWithPath: "/Applications/EncoBar.app"), home: home, token: token))
        XCTAssertTrue(command.contains("'/Applications/EncoBar.app'"))
        XCTAssertTrue(command.contains("'/Users/Example User/.Trash/EncoBar-12345678-1234-1234-1234-123456789ABC.app'"))
        let value = "space ' quote \" dollar $() newline\nend"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + UninstallLayout.shellLiteral(value)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), value)
    }

    func testWearingReportsPreserveUnknownAndDecodeIndependentFlags() {
        let out = WearingReport.parse(Frame(command: 0x8109, sequence: 4, payload: [0, 3, 1, 1, 2, 1, 3, 4]))
        XCTAssertEqual(out?.bothOutOfEar, true)
        let worn = WearingReport.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 2, 1, 7, 2, 11]))
        XCTAssertEqual(worn?.inEar[1], true)
        XCTAssertEqual(worn?.inEar[2], true)
        let partial = WearingReport.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 1, 1, 1]))
        XCTAssertEqual(partial?.bothOutOfEar, false)
        XCTAssertNil(partial?.inEar[2])
        XCTAssertNil(WearingReport.parse(Frame(command: 0x8109, sequence: 4, payload: [1, 1, 1, 3])))
        XCTAssertNil(WearingReport.parse(Frame(command: 0x8109, sequence: 4, payload: [0, 2, 1, 3])))
        XCTAssertNil(WearingReport.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 1, 1, 255])))
    }
    func testWearAndFitNotificationsCannotChangeNoiseMode() {
        XCTAssertNil(ANCReading.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [2, 1, 1, 1])))
        XCTAssertNil(ANCReading.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [4, 1, 1, 1])))
        XCTAssertEqual(ANCReading.parse(Frame(command: 0x0204, sequence: 0xFF, payload: [3, 1, 1, 4]))?.bitmap, 4)
    }
    func testUninstallerOnlyTargetsItsOwnBundleAndUserData() {
        let home = URL(fileURLWithPath: "/Users/Example User", isDirectory: true)
        let app = home.appendingPathComponent("Applications/EncoBar.app")
        let helper = "Contents/Helpers/EncoBar Uninstaller.app/Contents/MacOS/EncoBarUninstaller"
        XCTAssertEqual(UninstallLayout.application(containingHelper: app.appendingPathComponent(helper))?.path, app.path)
        XCTAssertNil(UninstallLayout.application(containingHelper: home.appendingPathComponent("EncoBarUninstaller")))
        XCTAssertNil(UninstallLayout.application(containingHelper: home.appendingPathComponent("Applications/Other.app/" + helper)))
        let paths = UninstallLayout.dataLocations(home: home).map(\.path)
        XCTAssertTrue(paths.contains("/Users/Example User/Library/Preferences/local.encobar.air4pro.plist"))
        XCTAssertTrue(paths.contains("/Users/Example User/Library/Caches/local.encobar.air4pro"))
        XCTAssertFalse(paths.contains(home.path))
        XCTAssertFalse(paths.contains("/Users/Example User/Library"))
        XCTAssertFalse(paths.contains { !$0.hasPrefix(home.path + "/Library/") })
        XCTAssertFalse(paths.contains { $0.contains("*") || $0.contains("..") })
    }

    func testPanelOpeningClickIsNotOutsideDismissal() {
        let panel = CGRect(x: -400, y: 600, width: 300, height: 240)
        let anchor = CGRect(x: -150, y: 850, width: 50, height: 25)
        XCTAssertFalse(PanelPlacement.shouldDismissClick(at: CGPoint(x: -125, y: 860), panel: panel, anchor: anchor))
        XCTAssertFalse(PanelPlacement.shouldDismissClick(at: CGPoint(x: -250, y: 700), panel: panel, anchor: anchor))
        XCTAssertTrue(PanelPlacement.shouldDismissClick(at: CGPoint(x: -500, y: 700), panel: panel, anchor: anchor))
        XCTAssertTrue(PanelPlacement.shouldDismissClick(at: CGPoint(x: -125, y: 845), panel: panel, anchor: anchor))
    }

    func testPanelStaysBelowMenuBarAndInsideScreenEdges() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let anchor = CGRect(x: 1380, y: 875, width: 60, height: 25)
        let frame = PanelPlacement.frame(anchor: anchor, visible: visible, size: CGSize(width: 300, height: 224))
        XCTAssertEqual(frame.size, CGSize(width: 300, height: 224))
        XCTAssertTrue(frame.maxY <= visible.maxY - 8)
        XCTAssertTrue(frame.maxY <= anchor.minY - 8)
        XCTAssertTrue(frame.minX >= visible.minX + 8)
        XCTAssertTrue(frame.maxX <= visible.maxX - 8)
    }

    func testPanelPlacementHandlesMonitorWithNegativeOrigin() {
        let visible = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let anchor = CGRect(x: -1915, y: 1255, width: 30, height: 25)
        let frame = PanelPlacement.frame(anchor: anchor, visible: visible, size: CGSize(width: 300, height: 224))
        XCTAssertTrue(frame.minX >= visible.minX + 8)
        XCTAssertTrue(frame.maxX <= visible.maxX - 8)
        XCTAssertTrue(frame.minY >= visible.minY + 8)
        XCTAssertTrue(frame.maxY <= visible.maxY - 8)
    }

    func testBackgroundSyncDoesNotDependOnPopoverVisibility() {
        var sync = BatterySync()
        let start = Date(timeIntervalSince1970: 100)
        sync.queried(sequence: 3, at: start)
        sync.received(sequence: 3)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(5), panelVisible: true, blocked: false), .query)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(29), panelVisible: false, blocked: false), .none)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(30), panelVisible: false, blocked: false), .query)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(30), panelVisible: false, blocked: true), .none)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(2), panelVisible: false, blocked: false, urgent: true), .query)
    }

    func testBatterySyncWaitsForItsReplyAndRecoversFromSilence() {
        var sync = BatterySync()
        let start = Date(timeIntervalSince1970: 100)
        sync.queried(sequence: 7, at: start)
        sync.received(sequence: 6)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(5), panelVisible: true, blocked: false), .none)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(8), panelVisible: false, blocked: false), .reconnect)
        sync.received(sequence: 7)
        XCTAssertEqual(sync.action(at: start.addingTimeInterval(8), panelVisible: true, blocked: false), .query)
    }

    func testCaseLidEventsTriggerOnlyForValidCaseState() {
        XCTAssertEqual(CaseLid.isOpen(in: Frame(command: 0x0204, sequence: 1, payload: [2, 3, 1, 0, 2, 0, 3, 4])), true)
        XCTAssertEqual(CaseLid.isOpen(in: Frame(command: 0x8109, sequence: 1, payload: [0, 1, 3, 0])), false)
        XCTAssertNil(CaseLid.isOpen(in: Frame(command: 0x0204, sequence: 1, payload: [1, 1, 3, 100])))
        XCTAssertNil(CaseLid.isOpen(in: Frame(command: 0x0204, sequence: 1, payload: [2, 3, 3, 4])))
        XCTAssertNil(CaseLid.isOpen(in: Frame(command: 0x8109, sequence: 1, payload: [1, 1, 3, 4])))
    }

    func testCaseUnknownReportsKeepLastRealReadingAndItsDate() throws {
        var history = CaseBatteryHistory()
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        history.receive(BatteryValue(percent: 0, charging: false), at: first)
        XCTAssertNil(history.reading)
        history.receive(BatteryValue(percent: 100, charging: false), at: first)
        XCTAssertEqual(history.reading, CaseBatteryReading(percent: 100, reportedAt: first))
        history.receive(BatteryValue(percent: 0, charging: false), at: later)
        history.receive(nil, at: later)
        history.receive(BatteryValue(percent: nil, charging: false), at: later)
        XCTAssertEqual(history.reading, CaseBatteryReading(percent: 100, reportedAt: first))
        history.receive(BatteryValue(percent: 80, charging: false), at: later)
        XCTAssertEqual(history.reading, CaseBatteryReading(percent: 80, reportedAt: later))
    }

    func testCaseHistoryCanRestoreValidReadingButRejectsUnknownOrCorruptValues() throws {
        let date = Date(timeIntervalSince1970: 100)
        let valid = CaseBatteryReading(percent: 85, reportedAt: date)
        let decoded = try JSONDecoder().decode(CaseBatteryReading.self, from: JSONEncoder().encode(valid))
        XCTAssertEqual(CaseBatteryHistory(restoring: decoded).reading, valid)
        XCTAssertNil(CaseBatteryHistory(restoring: CaseBatteryReading(percent: 0, reportedAt: date)).reading)
        XCTAssertNil(CaseBatteryHistory(restoring: CaseBatteryReading(percent: 101, reportedAt: date)).reading)
    }

    func testBatteryQueryUsesLittleEndianAndExactLengths() throws {
        XCTAssertEqual(try Frame(command: 0x0106, sequence: 0x21, payload: []).encoded(),
                       [0xAA, 7, 0, 0, 6, 1, 0x21, 0, 0])
        XCTAssertThrowsError(try Frame(command: 1, sequence: 1, payload: Array(repeating: 0, count: 249)).encoded())
    }

    func testSplitAndCoalescedFramesPreserveSequenceAndPayload() {
        var decoder = FrameDecoder()
        XCTAssertEqual(decoder.append([0x00, 0xAA, 9, 0, 0, 6]), [])
        let result = decoder.append([0x81, 3, 2, 0, 1, 0xE4, 0xAA, 7, 0, 0, 0, 0x81, 4, 0, 0])
        XCTAssertEqual(result, [Frame(command: 0x8106, sequence: 3, payload: [1, 0xE4]),
                                Frame(command: 0x8100, sequence: 4, payload: [])])
    }

    func testCorruptInnerLengthDoesNotHideFollowingValidFrame() {
        var decoder = FrameDecoder()
        let frames = decoder.append([0xAA, 250, 0, 0, 6, 0x81, 1, 2, 0,
                                     0xAA, 7, 0, 0, 6, 0x81, 2, 0, 0])
        XCTAssertEqual(frames.map(\.sequence), [2])
    }

    func testBatterySeparatesChargingUnknownAndRealZero() throws {
        let frame = Frame(command: 0x8106, sequence: 1, payload: [0, 3, 1, 0xE4, 2, 0, 3, 0xFF])
        let report = try XCTUnwrap(BatteryReport.parse(frame))
        XCTAssertEqual(report.values[1], BatteryValue(percent: 100, charging: true))
        XCTAssertEqual(report.values[2]?.percent, 0)
        XCTAssertNil(report.values[3]?.percent)
        XCTAssertNil(BatteryReport.parse(Frame(command: 0x8106, sequence: 1, payload: [1])))
    }

    func testNotificationCountAndEventTypeAreChecked() {
        XCTAssertNil(BatteryReport.parse(Frame(command: 0x0204, sequence: 0, payload: [1, 2, 1, 80])))
        XCTAssertNil(BatteryReport.parse(Frame(command: 0x0204, sequence: 0, payload: [3, 1, 1, 80])))
        let valid = BatteryReport.parse(Frame(command: 0x0204, sequence: 0, payload: [1, 1, 2, 80]))
        XCTAssertEqual(valid?.values[2]?.percent, 80)
    }

    func testANCReadsBitmapWithoutInventingModeSemantics() {
        XCTAssertEqual(ANCReading.parse(Frame(command: 0x810C, sequence: 8, payload: [0, 1, 1, 0, 1]))?.bitmap, 256)
        XCTAssertEqual(ANCReading.parse(Frame(command: 0x810C, sequence: 8, payload: [0, 1, 1, 0x10]))?.bitmap, 16)
        XCTAssertNil(ANCReading.parse(Frame(command: 0x0204, sequence: 0, payload: [1, 1, 1, 0x10])))
        XCTAssertNil(ANCReading.parse(Frame(command: 0x810C, sequence: 0, payload: [0, 1, 1, 0])))
    }

    func testOnlyFreshMatchingQueryConfirmsMode() {
        var confirmation = CommandConfirmation(target: 256, querySequence: 12)
        XCTAssertFalse(confirmation.accept(Frame(command: 0x8404, sequence: 11, payload: [0])))
        XCTAssertFalse(confirmation.accept(Frame(command: 0x810C, sequence: 9, payload: [0, 1, 1, 0, 1])))
        XCTAssertFalse(confirmation.accept(Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 8])))
        XCTAssertTrue(confirmation.accept(Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 0, 1])))
    }

    func testLiveAir4BatteryHeaderRejectsErrorsAndWrongCounts() {
        XCTAssertEqual(BatteryReport.parse(Frame(command: 0x8106, sequence: 3, payload: [0, 3, 1, 100, 2, 100, 3, 0]))?.values[1]?.percent, 100)
        XCTAssertNil(BatteryReport.parse(Frame(command: 0x8106, sequence: 3, payload: [0, 3, 1, 80])))
        XCTAssertNil(BatteryReport.parse(Frame(command: 0x8106, sequence: 3, payload: [2, 80])))
    }

    func testANCQueryIncludesRequiredSelector() throws {
        XCTAssertEqual(try Commands.queryANC(sequence: 9).encoded(), [0xAA, 9, 0, 0, 0x0C, 1, 9, 2, 0, 1, 1])
    }

    func testAir4ProParentModeUsesItsOwnProtocolIndices() {
        XCTAssertTrue(NoiseMode.off.matches(1))
        XCTAssertTrue(NoiseMode.cancellation.matches(2))
        XCTAssertTrue(NoiseMode.transparency.matches(4))
        XCTAssertTrue(NoiseMode.off.matches(8))
        XCTAssertTrue(NoiseMode.transparency.matches(256))
        XCTAssertTrue(NoiseMode.cancellation.matches(16))
        XCTAssertTrue(NoiseMode.cancellation.matches(128))
        XCTAssertFalse(NoiseMode.cancellation.matches(256))
        XCTAssertEqual(ANCReading.parse(Frame(command: 0x0204, sequence: 0, payload: [3, 1, 1, 4]))?.bitmap, 4)
    }

    func testExpiredCancelledAndAlreadyCompletedOperationsCannotSucceed() {
        let reply = Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 4])
        var expired = CommandConfirmation(target: 4, querySequence: 12, deadline: Date(timeIntervalSince1970: 10))
        XCTAssertFalse(expired.accept(reply, now: Date(timeIntervalSince1970: 11)))
        var cancelled = CommandConfirmation(target: 4, querySequence: 12)
        cancelled.cancel()
        XCTAssertFalse(cancelled.accept(reply))
        var once = CommandConfirmation(target: 4, querySequence: 12)
        XCTAssertTrue(once.accept(reply))
        XCTAssertFalse(once.accept(reply))
    }
    func testANCRejectsFailureStatusAndMalformedEnvelope() {
        XCTAssertNil(ANCReading.parse(Frame(command: 0x810C, sequence: 12, payload: [2, 1, 1, 4])))
        XCTAssertNil(ANCReading.parse(Frame(command: 0x810C, sequence: 12, payload: [0, 2, 1, 4])))
        XCTAssertNil(ANCReading.parse(Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 4, 0, 0])))
        var confirmation = CommandConfirmation(target: 4, querySequence: 12)
        XCTAssertFalse(confirmation.accept(Frame(command: 0x810C, sequence: 12, payload: [2, 1, 1, 4])))
    }

    func testReadBatchRequiresEveryFieldAndRejectsOldResponses() {
        var batch = ReadBatch(required: [.product, .battery, .mode], deadline: Date(timeIntervalSince1970: 10))
        batch.expect(.product, sequence: 1)
        batch.expect(.battery, sequence: 2)
        batch.expect(.mode, sequence: 3)
        batch.receive(.battery, sequence: 2)
        XCTAssertFalse(batch.isComplete)
        XCTAssertTrue(batch.hasExpired(at: Date(timeIntervalSince1970: 11)))
        batch.receive(.product, sequence: 1)
        batch.receive(.mode, sequence: 2)
        XCTAssertFalse(batch.isComplete)
        batch.receive(.mode, sequence: 3)
        XCTAssertTrue(batch.isComplete)
        XCTAssertFalse(batch.hasExpired(at: Date(timeIntervalSince1970: 11)))
    }

    func testRepeatedQueryInvalidatesEarlierFieldCompletion() {
        var batch = ReadBatch(required: [.mode], deadline: Date(timeIntervalSince1970: 10))
        batch.expect(.mode, sequence: 3)
        batch.receive(.mode, sequence: 3)
        XCTAssertTrue(batch.isComplete)
        batch.expect(.mode, sequence: 4)
        batch.receive(.mode, sequence: 3)
        XCTAssertFalse(batch.isComplete)
        batch.receive(.mode, sequence: 4)
        XCTAssertTrue(batch.isComplete)
    }
    func testLateOlderQueryCannotOverwriteLatestState() {
        var gate = ReplyGate()
        gate.issued(command: 0x010C, sequence: 3)
        gate.issued(command: 0x010C, sequence: 5)
        XCTAssertFalse(gate.accepts(Frame(command: 0x810C, sequence: 3, payload: [0, 1, 1, 1])))
        XCTAssertTrue(gate.accepts(Frame(command: 0x810C, sequence: 5, payload: [0, 1, 1, 4])))
        XCTAssertTrue(gate.accepts(Frame(command: 0x0204, sequence: 0, payload: [2, 1, 1, 2])))
        gate = ReplyGate()
        XCTAssertFalse(gate.accepts(Frame(command: 0x810C, sequence: 5, payload: [0, 1, 1, 4])))
    }
    func testConfirmationRecognizesAir4ProChildModeReports() {
        var nc = CommandConfirmation(mode: .cancellation, querySequence: 12)
        XCTAssertFalse(nc.accept(Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 0, 1])))
        XCTAssertTrue(nc.accept(Frame(command: 0x810C, sequence: 12, payload: [0, 1, 1, 16])))
        var trans = CommandConfirmation(mode: .transparency, querySequence: 14)
        XCTAssertFalse(trans.accept(Frame(command: 0x810C, sequence: 14, payload: [0, 1, 1, 16])))
        XCTAssertTrue(trans.accept(Frame(command: 0x810C, sequence: 14, payload: [0, 1, 1, 0, 1])))
    }
    func testWordModeFramesPreserveHighByteAndSelector() throws {
        XCTAssertEqual(try Commands.setMode(.transparency, sequence: 7, format: .childWord).encoded(),
                       [0xAA, 11, 0, 0, 4, 4, 7, 4, 0, 1, 2, 0, 1])
        XCTAssertEqual(try Commands.setMode(.transparency, sequence: 8, format: .parentWord).encoded(),
                       [0xAA, 11, 0, 0, 4, 4, 8, 4, 0, 1, 1, 4, 0])
    }

}

let tests = ProtocolTests()
let checks: [(String, () throws -> Void)] = [
    ("testLegacyMigrationOnlySelectsOwnedBundleAtExactLocation", tests.testLegacyMigrationOnlySelectsOwnedBundleAtExactLocation),
    ("testSystemUninstallRejectsOtherApplicationsAndQuotesUserPath", tests.testSystemUninstallRejectsOtherApplicationsAndQuotesUserPath),
    ("testWearingReportsPreserveUnknownAndDecodeIndependentFlags", tests.testWearingReportsPreserveUnknownAndDecodeIndependentFlags),
    ("testWearAndFitNotificationsCannotChangeNoiseMode", tests.testWearAndFitNotificationsCannotChangeNoiseMode),
    ("testUninstallerOnlyTargetsItsOwnBundleAndUserData", tests.testUninstallerOnlyTargetsItsOwnBundleAndUserData),
    ("testPanelOpeningClickIsNotOutsideDismissal", tests.testPanelOpeningClickIsNotOutsideDismissal),
    ("testPanelStaysBelowMenuBarAndInsideScreenEdges", tests.testPanelStaysBelowMenuBarAndInsideScreenEdges),
    ("testPanelPlacementHandlesMonitorWithNegativeOrigin", tests.testPanelPlacementHandlesMonitorWithNegativeOrigin),
    ("testBackgroundSyncDoesNotDependOnPopoverVisibility", tests.testBackgroundSyncDoesNotDependOnPopoverVisibility),
    ("testBatterySyncWaitsForItsReplyAndRecoversFromSilence", tests.testBatterySyncWaitsForItsReplyAndRecoversFromSilence),
    ("testCaseLidEventsTriggerOnlyForValidCaseState", tests.testCaseLidEventsTriggerOnlyForValidCaseState),
    ("testCaseUnknownReportsKeepLastRealReadingAndItsDate", tests.testCaseUnknownReportsKeepLastRealReadingAndItsDate),
    ("testCaseHistoryCanRestoreValidReadingButRejectsUnknownOrCorruptValues", tests.testCaseHistoryCanRestoreValidReadingButRejectsUnknownOrCorruptValues),
    ("testWordModeFramesPreserveHighByteAndSelector", tests.testWordModeFramesPreserveHighByteAndSelector),
    ("testConfirmationRecognizesAir4ProChildModeReports", tests.testConfirmationRecognizesAir4ProChildModeReports),
    ("testLateOlderQueryCannotOverwriteLatestState", tests.testLateOlderQueryCannotOverwriteLatestState),
    ("testANCRejectsFailureStatusAndMalformedEnvelope", tests.testANCRejectsFailureStatusAndMalformedEnvelope),
    ("testReadBatchRequiresEveryFieldAndRejectsOldResponses", tests.testReadBatchRequiresEveryFieldAndRejectsOldResponses),
    ("testRepeatedQueryInvalidatesEarlierFieldCompletion", tests.testRepeatedQueryInvalidatesEarlierFieldCompletion),
    ("testBatteryQueryUsesLittleEndianAndExactLengths", tests.testBatteryQueryUsesLittleEndianAndExactLengths),
    ("testSplitAndCoalescedFramesPreserveSequenceAndPayload", tests.testSplitAndCoalescedFramesPreserveSequenceAndPayload),
    ("testCorruptInnerLengthDoesNotHideFollowingValidFrame", tests.testCorruptInnerLengthDoesNotHideFollowingValidFrame),
    ("testBatterySeparatesChargingUnknownAndRealZero", tests.testBatterySeparatesChargingUnknownAndRealZero),
    ("testNotificationCountAndEventTypeAreChecked", tests.testNotificationCountAndEventTypeAreChecked),
    ("testANCReadsBitmapWithoutInventingModeSemantics", tests.testANCReadsBitmapWithoutInventingModeSemantics),
    ("testOnlyFreshMatchingQueryConfirmsMode", tests.testOnlyFreshMatchingQueryConfirmsMode),
    ("testLiveAir4BatteryHeaderRejectsErrorsAndWrongCounts", tests.testLiveAir4BatteryHeaderRejectsErrorsAndWrongCounts),
    ("testANCQueryIncludesRequiredSelector", tests.testANCQueryIncludesRequiredSelector),
    ("testAir4ProParentModeUsesItsOwnProtocolIndices", tests.testAir4ProParentModeUsesItsOwnProtocolIndices),
    ("testExpiredCancelledAndAlreadyCompletedOperationsCannotSucceed", tests.testExpiredCancelledAndAlreadyCompletedOperationsCannotSucceed),
]
for (name, check) in checks { let before = failures; do { try check() } catch { failures += 1; print("ERROR \(name): \(error)") }; print("\(failures == before ? "PASS" : "FAIL") \(name)") }
print("\(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
