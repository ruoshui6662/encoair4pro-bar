import AppKit
import SwiftUI
import Combine
import EncoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ControlPanel!
    private var model: EarbudModel!
    private var subscription: AnyCancellable?
    private var exerciseEnabled = false
    private var exerciseStarted = false
    private var exerciseFinished = false
    private var exerciseModes: [NoiseMode] = []
    private var exerciseExpected: NoiseMode?
    private var terminateSignal: DispatchSourceSignal?
    private var protocolProbe: ProtocolProbe?
    private var batteryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--ui-preview") ? .regular : .accessory)
        signal(SIGTERM, SIG_IGN)
        terminateSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminateSignal?.setEventHandler { NSApp.terminate(nil) }
        terminateSignal?.resume()
        let arguments = CommandLine.arguments
        if arguments.contains("--protocol-probe") {
            guard let diagnostic = ProtocolProbe(arguments: arguments) else { NSApp.terminate(nil); return }
            protocolProbe = diagnostic
            diagnostic.start()
            return
        }
        exerciseEnabled = arguments.contains("--exercise")
        let probeIndex = arguments.firstIndex(of: "--probe")
        let logIndex = probeIndex ?? arguments.firstIndex(of: "--log-file")
        let output = logIndex.flatMap { index in arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil }
        let format: ModeCommandFormat = arguments.contains("--child-commands") ? .childWord
            : arguments.contains("--wide-commands") ? .parentWord : .parentByte
        model = EarbudModel(probe: probeIndex != nil, probeOutput: output, commandFormat: format)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "EncoBar 耳机控制")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "OPPO Enco Air4 Pro"
        panel = ControlPanel(model: model)
        batteryTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.synchronizeBattery(panelVisible: self.panel.isShown)
        }
        if let batteryTimer { RunLoop.main.add(batteryTimer, forMode: .common) }
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusItem.button?.title = self.model.menuBattery.map { " \($0)" } ?? ""
                self.advanceExercise()
            }
        }
        DispatchQueue.main.async { [weak self] in self?.model.connect() }
        if probeIndex != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 70) { NSApp.terminate(nil) }
        } else if !arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showPopover() }
        }
    }

    @objc private func togglePopover() {
        model.record("菜单栏点击；面板可见：\(panel.isShown)")
        if panel.isShown { panel.hide() } else { showPopover() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }
    private func advanceExercise() {
        guard exerciseEnabled, !exerciseFinished, model.canControl else { return }
        if !exerciseStarted {
            guard let original = model.currentMode else { return }
            exerciseStarted = true
            exerciseModes = [.transparency, .cancellation, .off, original]
            model.record("实机验证开始；结束时恢复\(original.title)")
        }
        if let expected = exerciseExpected {
            guard model.currentMode == expected, model.message == "已切换到\(expected.title)" else { return }
            model.record("CHECK PASS：\(expected.title)")
            exerciseExpected = nil
        }
        guard !exerciseModes.isEmpty else {
            exerciseFinished = true
            model.record("CHECK PASS：全部模式已确认，已恢复原模式")
            return
        }
        let next = exerciseModes.removeFirst()
        exerciseExpected = next
        model.setMode(next)
    }
    private func showPopover() {
        guard let button = statusItem.button else { return }
        panel.show(relativeTo: button)
        model.refresh()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { batteryTimer?.invalidate(); protocolProbe?.stop(); model?.shutdown() }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
