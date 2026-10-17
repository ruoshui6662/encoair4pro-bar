import Foundation
import IOBluetooth
import EncoCore
import CryptoKit

/// A separate vendor channel; never disconnects the system audio connection.
final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var onOpen: (() -> Void)?
    var onDeviceSelected: ((String) -> Void)?
    var onChannelOpening: (() -> Void)?
    var synchronousDiagnosticOpen = false
    var onFrame: ((Frame) -> Void)?
    var onError: ((String) -> Void)?
    var log: ((String) -> Void)?
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var active = false
    private var attempt = UUID()
    private var reportedOpen = false

    func connect() {
        stop()
        active = true
        reportedOpen = false
        let current = UUID()
        attempt = current
        log?("开始枚举已配对耳机")
        // IOBluetooth's synchronous XPC lookup may wait for system privacy handling.
        // Keep it off AppKit's event loop so the permission prompt and panel remain responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            let candidates = paired.filter {
                ($0.name ?? "").lowercased().filter(\.isLetterOrNumber) == "oppoencoair4pro"
            }
            let target = candidates.first(where: { $0.isConnected() }) ?? candidates.first
            let connected = target?.isConnected() ?? false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.attempt == current else { return }
                self.log?("设备枚举完成")
                self.select(target, connected: connected)
            }
        }
    }

    private func select(_ target: IOBluetoothDevice?, connected: Bool) {
        guard let target else {
            onError?("未找到已配对的 Air4 Pro，请先在系统蓝牙设置中连接耳机。")
            return
        }
        device = target
        // Scope persisted battery history to this paired device without storing
        // or logging its Bluetooth address in plain text.
        if let address = target.addressString {
            let key = SHA256.hash(data: Data(address.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
            onDeviceSelected?(key)
        }
        log?("找到 OPPO Enco Air4 Pro；系统连接：\(connected)")
        guard connected else {
            onError?("耳机尚未连接 Mac，请先在系统蓝牙设置中连接。")
            return
        }
        let result = target.performSDPQuery(self)
        log?("SDP 查询开始：\(result)")
        if result != kIOReturnSuccess { onError?("无法查询耳机服务（\(result)）。") }
    }

    @objc func sdpQueryComplete(_ queried: IOBluetoothDevice, status: IOReturn) {
        guard active, queried === device else { return }
        log?("SDP 完成：\(status)")
        for record in (queried.services as? [IOBluetoothSDPServiceRecord]) ?? [] {
            var number: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&number) == kIOReturnSuccess {
                log?("服务：\(record.getServiceName() ?? "未命名")，RFCOMM \(number)")
            }
        }
        guard status == kIOReturnSuccess else {
            onError?("蓝牙服务查询失败（\(status)），请重新连接耳机后重试。")
            return
        }
        for text in ["00001107-D102-11E1-9B23-00025B00A5A5", "0000079A-D102-11E1-9B23-00025B00A5A5"] {
            var uuid = UUID(uuidString: text)!.uuid
            let bytes = withUnsafeBytes(of: &uuid) { Data($0) }
            let serviceUUID = IOBluetoothSDPUUID(data: bytes)
            guard let record = queried.getServiceRecord(for: serviceUUID) else { continue }
            var number: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&number) == kIOReturnSuccess, number > 0 else { continue }
            log?("匹配厂商服务 \(text)，打开 RFCOMM \(number)")
            onChannelOpening?()
            let result = synchronousDiagnosticOpen
                ? queried.openRFCOMMChannelSync(&channel, withChannelID: number, delegate: self)
                : queried.openRFCOMMChannelAsync(&channel, withChannelID: number, delegate: self)
            channel?.setDelegate(self)
            log?("RFCOMM 请求返回：\(result)，通道对象：\(channel != nil)，已打开：\(channel?.isOpen() ?? false)")
            if result != kIOReturnSuccess { onError?("控制通道打开失败（\(result)）。") }
            else if channel?.isOpen() == true { reportOpen() }
            return
        }
        onError?("未发现欢律控制服务。已保留诊断记录，需要进一步检查 BLE 服务。")
    }

    func rfcommChannelOpenComplete(_ opened: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        log?("RFCOMM 打开结果：\(error)")
        guard active, let opened else { return }
        if channel == nil { channel = opened }
        guard opened === channel else { return }
        if error == kIOReturnSuccess { reportOpen() }
        else { onError?("控制通道连接失败（\(error)）。") }
    }

    private func reportOpen() {
        guard active, !reportedOpen else { return }
        reportedOpen = true
        onOpen?()
    }

    func rfcommChannelData(_ source: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard active, source === channel, let pointer, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
        for frame in decoder.append(bytes) { onFrame?(frame) }
    }

    func rfcommChannelClosed(_ closed: IOBluetoothRFCOMMChannel!) {
        guard active, closed === channel else { return }
        channel = nil
        onError?("耳机控制连接已断开。")
    }

    func send(_ frame: Frame) throws {
        guard let channel, channel.isOpen() else { throw TransportError.closed }
        var bytes = try frame.encoded()
        let result = bytes.withUnsafeMutableBytes {
            channel.writeAsync($0.baseAddress, length: UInt16($0.count), refcon: nil)
        }
        guard result == kIOReturnSuccess else { throw TransportError.write(result) }
    }

    func stop() {
        active = false
        attempt = UUID()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        device = nil
        decoder = FrameDecoder()
    }
}

private enum TransportError: LocalizedError {
    case closed, write(IOReturn)
    var errorDescription: String? {
        switch self {
        case .closed: return "控制通道未连接。"
        case .write(let code): return "发送失败（\(code)）。"
        }
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
