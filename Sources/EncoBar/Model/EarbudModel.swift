import AppKit
import Combine
import CoreBluetooth
import EncoCore

extension NoiseMode {
    var title: String {
        switch self { case .cancellation: return "降噪"; case .transparency: return "通透"; case .off: return "关闭" }
    }
    var symbol: String {
        switch self { case .cancellation: return "waveform.slash"; case .transparency: return "ear.badge.waveform"; case .off: return "waveform" }
    }
}

final class EarbudModel: ObservableObject {
    @Published private(set) var status = "准备连接"
    @Published private(set) var message: String?
    @Published private(set) var controlOpen = false
    @Published private(set) var connecting = false
    @Published private(set) var battery: [UInt8: BatteryValue] = [:]
    @Published private(set) var batteryDates: [UInt8: Date] = [:]
    @Published private(set) var caseBattery = CaseBatteryHistory()
    @Published private(set) var bitmap: UInt16?
    @Published private(set) var pendingMode: NoiseMode?
    @Published private(set) var inEar: [UInt8: Bool] = [:]
    @Published private(set) var productID: String?
    @Published private(set) var logs: [String] = []
    @Published private(set) var updated: Date?
    @Published private(set) var batteryUpdated: Date?
    @Published var showDiagnostics = false
    private var transport: RFCOMMTransport?
    private var sequence: UInt8 = 0
    private var generation = UUID()
    private var timeout: DispatchWorkItem?
    private var readTimeout: DispatchWorkItem?
    private var readBatch: ReadBatch?
    private var replies = ReplyGate()
    private var reconnect: DispatchWorkItem?
    private var retryDelay: Double = 5
    private var pendingQuery: UInt8?
    private var pendingSet: UInt8?
    private var confirmation: CommandConfirmation?
    private var modeDeadline = Date.distantPast
    private var modeStartedAt: Date?
    private var modeOperation: UUID?
    private var modeWearQuery: UInt8?
    private var modeConfirmedOutOfEar = false
    private var lastRefresh = Date.distantPast
    private var batterySync = BatterySync()
    private var caseLidOpen: Bool?
    private var batchSubscriptionSequence: UInt8?
    private var caseStorageKey: String?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let probe: Bool
    private let probeOutput: URL?
    private let commandFormat: ModeCommandFormat
    private let authorization: () -> CBManagerAuthorization

    init(probe: Bool = false, probeOutput: URL? = nil, commandFormat: ModeCommandFormat = .parentByte,
         authorization: @escaping () -> CBManagerAuthorization = { CBManager.authorization }) {
        self.probe = probe
        self.probeOutput = probeOutput
        self.commandFormat = commandFormat
        self.authorization = authorization
        if let probeOutput { try? Data().write(to: probeOutput) }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.disconnect(message: "Mac 已休眠，唤醒后自动连接。", retry: false)
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReconnect(after: 2)
        })
    }

    deinit {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        timeout?.cancel(); readTimeout?.cancel(); reconnect?.cancel(); transport?.stop()
    }

    var currentMode: NoiseMode? { bitmap.flatMap { raw in NoiseMode.allCases.first { $0.matches(raw) } } }
    var canControl: Bool { controlOpen && readBatch == nil && productID == "067C10" && currentMode != nil && pendingMode == nil }
    var controlFeedback: String? {
        if pendingMode != nil { return "正在切换…" }
        if controlOpen && inEar[1] == false && inEar[2] == false { return "请佩戴后切换" }
        if let message, !message.hasPrefix("已切换到") { return message }
        return nil
    }
    var menuBattery: String? {
        let values = [battery[1]?.percent, battery[2]?.percent].compactMap { $0 }
        return values.min().map { "\($0)%" }
    }

    func displayedBattery(for index: UInt8) -> BatteryValue? {
        guard controlOpen else { return nil }
        if index == 3 { return caseBattery.reading.map { BatteryValue(percent: $0.percent, charging: false) } }
        return battery[index]
    }

    func displayedBatteryDate(for index: UInt8) -> Date? {
        guard controlOpen else { return nil }
        return index == 3 ? caseBattery.reading?.reportedAt : batteryDates[index]
    }

    func connect() {
        reconnect?.cancel()
        generation = UUID()
        timeout?.cancel()
        readTimeout?.cancel(); readBatch = nil; replies = ReplyGate()
        transport?.stop()
        transport = nil
        battery = [:]; batteryDates = [:]; bitmap = nil; productID = nil; updated = nil
        caseBattery = CaseBatteryHistory(); caseStorageKey = nil
        batteryUpdated = nil; batterySync = BatterySync(); caseLidOpen = nil; batchSubscriptionSequence = nil
        pendingMode = nil; pendingQuery = nil; pendingSet = nil
        inEar = [:]; modeOperation = nil; modeWearQuery = nil; modeConfirmedOutOfEar = false
        confirmation?.cancel(); confirmation = nil
        controlOpen = false; connecting = true; message = nil; status = "正在连接耳机"
        sequence = 0
        lastRefresh = .distantPast
        let permission = authorization()
        if permission == .denied || permission == .restricted {
            disconnect(message: "蓝牙权限未开启。请在系统设置 → 隐私与安全性 → 蓝牙中允许 EncoBar。", retry: false)
            return
        }
        let current = generation
        let connection = RFCOMMTransport()
        transport = connection
        connection.onDeviceSelected = { [weak self] deviceKey in
            guard let self, self.generation == current else { return }
            let key = "caseBatteryHistory." + deviceKey
            self.caseStorageKey = key
            let saved = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(CaseBatteryReading.self, from: $0) }
            self.caseBattery = CaseBatteryHistory(restoring: saved)
            if let reading = self.caseBattery.reading {
                self.record("已恢复充电盒上次电量：\(reading.percent)%")
            }
        }
        connection.log = { [weak self] text in self?.record(text) }
        connection.onChannelOpening = { [weak self] in
            guard let self, self.generation == current else { return }
            self.setTimeout(seconds: 12) { model in
                model.disconnect(message: "控制通道连接超时，正在重新连接。", retry: !model.probe)
            }
        }
        connection.onError = { [weak self] text in
            guard let self, self.generation == current else { return }
            self.disconnect(message: text, retry: !self.probe)
        }
        connection.onOpen = { [weak self] in
            guard let self, self.generation == current else { return }
            self.timeout?.cancel()
            self.controlOpen = true; self.connecting = false; self.status = "读取耳机状态"
            _ = self.send(0x0100)
            self.refresh()
            self.later(1.3) { model in _ = model.send(0x0200) }
        }
        connection.onFrame = { [weak self] frame in
            guard let self, self.generation == current else { return }
            self.receive(frame)
        }
        record("连接 Air4 Pro")
        connection.connect()
        if connecting {
            setTimeout(seconds: 60) { model in model.disconnect(message: "连接超时。若系统正在请求蓝牙权限，请允许后点击重连。", retry: !model.probe) }
        }
    }

    func refresh() {
        guard controlOpen, pendingMode == nil, readBatch == nil, Date().timeIntervalSince(lastRefresh) > 1 else { return }
        lastRefresh = Date()
        // Reopening an initialized device must not put the controls back behind
        // a three-field startup barrier. Refresh in the background instead.
        if productID == "067C10", currentMode != nil {
            record("刷新已连接耳机：保持模式按钮可用")
            synchronizeBattery(panelVisible: true, urgent: true)
            _ = send(0x010C)
            _ = send(0x0109)
            return
        }
        readBatch = ReadBatch(required: [.product, .battery, .mode], deadline: Date().addingTimeInterval(8))
        status = "正在读取状态"
        let current = generation
        for (index, item) in [(StatusField.product, UInt16(0x0103)), (.battery, 0x0106), (.mode, 0x010C)].enumerated() {
            later(Double(index + 1) * 0.25) { model in
                if let seq = model.send(item.1) { model.readBatch?.expect(item.0, sequence: seq) }
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current, self.readBatch?.hasExpired(at: Date()) == true else { return }
            self.disconnect(message: "耳机状态读取不完整或已超时，正在重新连接。", retry: !self.probe)
        }
        readTimeout?.cancel(); readTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func synchronizeBattery(panelVisible: Bool, urgent: Bool = false) {
        let blocked = !controlOpen || pendingMode != nil || readBatch != nil
        switch batterySync.action(at: Date(), panelVisible: panelVisible, blocked: blocked, urgent: urgent) {
        case .none: break
        case .query:
            record(urgent ? "自动电量同步：开盒补读" : panelVisible ? "自动电量同步：面板" : "自动电量同步：后台")
            _ = send(0x0106)
        case .reconnect:
            disconnect(message: "自动电量查询未响应，正在恢复连接。", retry: !probe)
        }
    }

    func setMode(_ mode: NoiseMode) {
        guard canControl else { return }
        timeout?.cancel()
        message = nil; pendingMode = mode; pendingQuery = nil
        let operation = UUID()
        modeOperation = operation; modeWearQuery = nil; modeConfirmedOutOfEar = false
        modeStartedAt = Date()
        record("请求切换：\(mode.title)")
        modeDeadline = Date().addingTimeInterval(5)
        pendingSet = send(0x0404, payload: Commands.setMode(mode, sequence: 0, format: commandFormat).payload)
        guard controlOpen else { return }
        // Keep the SET immediate; an old out-of-ear report must never block a
        // click made just after reinsertion. Diagnose using a fresh wear query.
        modeWearQuery = send(0x0109)
        guard controlOpen else { return }
        status = "正在切换到\(mode.title)"
        // Usually the ACK arrives first and starts readback immediately. Keep
        // a fallback for firmware that omits a successful ACK.
        later(0.45) { model in
            guard model.modeOperation == operation else { return }
            if model.pendingQuery == nil { model.pollPendingMode() }
        }
        setTimeout(seconds: 5) { model in
            guard model.modeOperation == operation else { return }
            model.finishMode(message: "切换未生效，请重试。")
            model.record("模式切换超时；未报告成功")
        }
    }

    private func pollPendingMode() {
        guard controlOpen, pendingMode != nil else { return }
        pendingQuery = send(0x010C)
        if let query = pendingQuery, let mode = pendingMode {
            confirmation = CommandConfirmation(mode: mode, querySequence: query, deadline: modeDeadline)
        }
    }

    private func finishMode(message text: String) {
        timeout?.cancel()
        pendingMode = nil; pendingQuery = nil; pendingSet = nil
        modeOperation = nil; modeWearQuery = nil; modeConfirmedOutOfEar = false
        confirmation?.cancel(); confirmation = nil
        status = "已连接"; message = text
    }

    private func receive(_ frame: Frame) {
        guard replies.accepts(frame) else { record("忽略迟到或未请求的响应"); return }
        // Only payloads needed for this app are logged; no addresses or serial numbers.
        if [UInt16(0x8100), 0x8103, 0x8106, 0x8109, 0x810C, 0x8404, 0x8200, 0x8201, 0x8205].contains(frame.command) {
            record(String(format: "RX %04X #%02X ", frame.command, frame.sequence) + frame.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        if let wearing = WearingReport.parse(frame) {
            let previous = inEar
            inEar.merge(wearing.inEar) { _, new in new }
            // A later reinsertion push supersedes the earlier wear query;
            // do not abort on its old out-of-ear evidence while ANC settles.
            if wearing.inEar.values.contains(true) { modeConfirmedOutOfEar = false }
            if inEar != previous { record("佩戴状态：左 \(inEar[1].map { $0 ? "入耳" : "未入耳" } ?? "未知")，右 \(inEar[2].map { $0 ? "入耳" : "未入耳" } ?? "未知")") }
            if frame.command == 0x8109, frame.sequence == modeWearQuery {
                modeConfirmedOutOfEar = wearing.bothOutOfEar
                if modeConfirmedOutOfEar { pollPendingMode() }
            } else if pendingMode == nil, readBatch == nil, productID == "067C10", inEar != previous {
                message = nil
                _ = send(0x010C)
            }
        }
        if let report = BatteryReport.parse(frame) {
            if frame.command == 0x0204 { record("收到电量主动上报") }
            for (index, value) in report.values { battery[index] = value; batteryDates[index] = Date() }
            let old = caseBattery.reading
            caseBattery.receive(report.values[3], at: Date())
            if let reading = caseBattery.reading, reading != old {
                if let key = caseStorageKey, let data = try? JSONEncoder().encode(reading) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                record("充电盒有效电量：\(reading.percent)%")
            }
            updated = Date()
            batteryUpdated = Date()
            if frame.command == 0x8106 {
                batterySync.received(sequence: frame.sequence)
                readBatch?.receive(.battery, sequence: frame.sequence)
            }
        }
        if let open = CaseLid.isOpen(in: frame) {
            if open && caseLidOpen != true {
                record("充电盒已开盖，安排自动补读")
                later(1) { $0.synchronizeBattery(panelVisible: false, urgent: true) }
                later(3) { $0.synchronizeBattery(panelVisible: false, urgent: true) }
            }
            caseLidOpen = open
        }
        if let reading = ANCReading.parse(frame) {
            bitmap = reading.bitmap; updated = Date()
            if frame.command == 0x810C { readBatch?.receive(.mode, sequence: frame.sequence) }
            if frame.command == 0x0204 && pendingMode == nil { message = nil }
            if let mode = pendingMode, frame.command == 0x810C, frame.sequence == pendingQuery {
                if confirmation?.accept(frame) == true {
                    finishMode(message: "已切换到\(mode.title)")
                    let elapsed = modeStartedAt.map { Int(Date().timeIntervalSince($0) * 1_000) } ?? 0
                    record("已回读确认：\(mode.title)，耗时 \(elapsed) ms")
                } else if modeConfirmedOutOfEar {
                    finishMode(message: "耳机未检测到佩戴，请戴好后再试。")
                    record("模式未变化，最新佩戴查询确认双耳未入耳")
                } else {
                    let operation = modeOperation
                    later(0.5) { model in
                        guard model.modeOperation == operation else { return }
                        model.pollPendingMode()
                    }
                }
            }
        }
        if frame.command == 0x8404, frame.sequence == pendingSet, let error = frame.payload.first {
            if error != 0 {
                finishMode(message: error == 14 ? "耳机未检测到佩戴，请戴好后再试。" : "耳机拒绝了模式切换（\(error)）。")
                _ = send(0x010C)
            } else if pendingQuery == nil {
                pollPendingMode()
            }
        }
        if frame.command == 0x8103, frame.payload.count == 4, frame.payload[0] == 0 {
            productID = frame.payload.dropFirst().reversed().map { String(format: "%02X", $0) }.joined()
            readBatch?.receive(.product, sequence: frame.sequence)
        }
        if frame.command == 0x8205, frame.sequence == batchSubscriptionSequence, !frame.payload.isEmpty {
            batchSubscriptionSequence = nil
            record("收到批量通知订阅响应")
        }
        if frame.command == 0x8200 {
            // Notification capability: status, count, event codes. Subscribe only when well-formed.
            let p = frame.payload
            if p.count >= 2, p[0] == 0, p.count == 2 + Int(p[1]) {
                let codes = p.dropFirst(2).filter { [UInt8(1), 2, 3, 4].contains($0) }
                if !codes.isEmpty, let seq = send(0x0205, payload: [UInt8(codes.count)] + codes) {
                    batchSubscriptionSequence = seq
                    later(2) { model in
                        guard model.batchSubscriptionSequence == seq else { return }
                        model.batchSubscriptionSequence = nil
                        model.record("批量订阅未确认，改为逐项订阅电量与状态通知")
                        for (index, code) in codes.enumerated() {
                            model.later(Double(index) * 0.25) { _ = $0.send(0x0201, payload: [code]) }
                        }
                    }
                }
            }
        }
        if readBatch?.isComplete == true {
            readTimeout?.cancel(); readBatch = nil; status = "已连接"
            _ = send(0x0109)
            retryDelay = 5
            if productID != "067C10" || currentMode == nil { message = "设备版本尚未适配，已禁用模式切换。" }
        }
    }

    @discardableResult private func send(_ command: UInt16, payload: [UInt8] = []) -> UInt8? {
        guard controlOpen else { return nil }
        // Never wrap within a session: an old response must not confirm a later operation.
        guard sequence < 254 else { disconnect(message: "正在更新控制会话。", retry: true); return nil }
        sequence += 1
        let frame = command == 0x010C ? Commands.queryANC(sequence: sequence) : Frame(command: command, sequence: sequence, payload: payload)
        do {
            try transport?.send(frame)
            replies.issued(command: command, sequence: sequence)
            if command == 0x0106 { batterySync.queried(sequence: sequence, at: Date()) }
            record(String(format: "TX %04X #%02X ", command, sequence) + frame.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
            return sequence
        } catch { disconnect(message: error.localizedDescription, retry: !probe); return nil }
    }

    private func disconnect(message text: String, retry: Bool) {
        generation = UUID(); timeout?.cancel()
        readTimeout?.cancel(); readBatch = nil; replies = ReplyGate(); reconnect?.cancel()
        transport?.stop(); transport = nil
        controlOpen = false; connecting = false; pendingMode = nil; pendingQuery = nil; pendingSet = nil
        inEar = [:]; modeOperation = nil; modeWearQuery = nil; modeConfirmedOutOfEar = false
        bitmap = nil; battery = [:]; batteryDates = [:]; updated = nil; sequence = 0
        batteryUpdated = nil; batterySync = BatterySync(); caseLidOpen = nil; batchSubscriptionSequence = nil
        confirmation?.cancel(); confirmation = nil; productID = nil
        status = "未连接"; message = text; record(text)
        if retry { scheduleReconnect(after: retryDelay); retryDelay = min(retryDelay * 2, 60) }
    }

    private func scheduleReconnect(after seconds: Double) {
        reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func later(_ seconds: Double, action: @escaping (EarbudModel) -> Void) {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == current else { return }
            action(self)
        }
    }

    private func setTimeout(seconds: Double, action: @escaping (EarbudModel) -> Void) {
        timeout?.cancel()
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            action(self)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func record(_ text: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(text)"
        logs.append(line)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        if let probeOutput { try? logs.joined(separator: "\n").write(to: probeOutput, atomically: true, encoding: .utf8) }
        print(line); fflush(stdout)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("EncoBar 0.1 · Air4 Pro\n" + logs.joined(separator: "\n"), forType: .string)
    }

    func shutdown() { disconnect(message: "控制连接已关闭。", retry: false) }
}
