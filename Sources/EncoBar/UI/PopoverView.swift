import SwiftUI
import EncoCore

struct PopoverView: View {
    @ObservedObject var model: EarbudModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Enco Air4 Pro").font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    Button(model.controlOpen ? "刷新电量" : "重新连接") {
                        model.controlOpen ? model.refresh() : model.connect()
                    }
                    Button("蓝牙设置…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                    Divider()
                    Button("卸载 EncoBar…") { UninstallLauncher.open() }
                    Button("退出 EncoBar") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多")
            }
            .frame(height: 20)

            HStack(spacing: 8) {
                batteryItem(1, title: "左耳", symbol: "earbud.left")
                batteryItem(2, title: "右耳", symbol: "earbud.right")
                batteryItem(3, title: "耳机仓", symbol: "earbuds.case")
            }
            .frame(height: 68)
            .accessibilityElement(children: .contain)

            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)

            HStack(spacing: 8) {
                ForEach(NoiseMode.allCases) { mode in modeButton(mode) }
            }
            .frame(height: 58)

            HStack(spacing: 6) {
                Circle().fill(model.controlOpen ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.4)).frame(width: 4, height: 4)
                Text(model.controlOpen ? "已连接" : "未连接").font(.system(size: 10))
                Spacer(minLength: 2)
                if let feedback = model.controlFeedback {
                    Text(feedback).font(.system(size: 10)).lineLimit(1)
                        .help(model.message ?? feedback)
                }
            }
            .foregroundStyle(.secondary)
            .frame(height: 20, alignment: .center)
        }
        .padding(16)
        .frame(width: 300, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .circular))
    }

    private func batteryItem(_ index: UInt8, title: String, symbol: String) -> some View {
        let value = model.displayedBattery(for: index)
        let date = model.displayedBatteryDate(for: index)
        let hint = date.map { "\(index == 3 ? "耳机仓上次有效电量" : title)：\($0.formatted(date: .abbreviated, time: .standard))" }
            ?? (!model.controlOpen ? "未连接耳机。" : index == 3 ? "将耳机放回盒内并开盖，即可自动读取盒电量。" : "尚未收到电量。")
        return VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .scaleEffect(x: index == 3 ? 1 : -1, y: 1)
                .frame(width: 30, height: 26)
                .foregroundStyle(value?.percent == nil ? .tertiary : .secondary)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 12)
            Text(value?.percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                .frame(width: 48, height: 17)
                .overlay(alignment: .trailing) {
                    if value?.charging == true {
                        Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.secondary).offset(x: 9)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .help(hint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value?.percent.map { "\($0)%\(index == 3 ? "，上次读取" : "")" } ?? "未知")
    }

    private func modeButton(_ mode: NoiseMode) -> some View {
        let selected = model.currentMode == mode
        return Button { model.setMode(mode) } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                    .opacity(model.pendingMode == mode ? 0.3 : 1)
                    .overlay {
                        if model.pendingMode == mode { ProgressView().controlSize(.small) }
                    }
                Text(mode.title).font(.system(size: 10, weight: selected ? .medium : .regular))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!model.canControl)
        .opacity(model.canControl || model.pendingMode != nil ? 1 : 0.5)
        .accessibilityLabel("切换到\(mode.title)")
        .accessibilityValue(selected ? "当前模式" : "")
    }
}
