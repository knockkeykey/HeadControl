import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case status, gestures, general
    var id: String { rawValue }
    var title: String { switch self { case .status: "状态"; case .gestures: "头势"; case .general: "通用" } }
    var symbol: String { switch self { case .status: "airpodspro"; case .gestures: "person.crop.circle"; case .general: "gearshape" } }
    var subtitle: String {
        switch self {
        case .status: "按清单完成准备，打开开关就能用头控制。"
        case .gestures: "为每个头势选一个按键。小球背对着你，拖动圆弧上的圆点调整动作幅度。"
        case .general: "悬浮条、提示音、走动暂停和程序坞图标。"
        }
    }
}

struct SettingsRoot: View {
    @ObservedObject var controller: AppController
    @State private var page: SettingsPage? = SettingsRoot.initialPage
    static var initialPage: SettingsPage {
        if let i = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.indices.contains(i + 1),
           let p = SettingsPage(rawValue: CommandLine.arguments[i + 1]) { return p }
        return .status
    }
    var body: some View {
        split.frame(minWidth: 900, minHeight: 660)
    }
    private var split: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SettingsPage.allCases, selection: $page) { item in
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        Spacer()
                        if item == .status && !controller.permissionsReady {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("有权限未授予")
                        }
                    }.tag(item).padding(.vertical, 5)
                }.listStyle(.sidebar)
                Divider()
                HStack(spacing: 10) {
                    HeadphoneBadge(link: controller.motion.link, enabled: controller.enabled, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(controller.statusTitle).font(.caption.weight(.medium))
                        Text(controller.motion.link.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(14)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 230)
        } detail: {
            let current = page ?? .status
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(current.title).font(.system(size: 26, weight: .semibold))
                        Text(current.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    switch current {
                    case .status: StatusPage(controller: controller) { page = $0 }
                    case .gestures: GesturesPage(controller: controller, store: controller.store)
                    case .general: GeneralPage(controller: controller, store: controller.store)
                    }
                }
                .padding(28).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: Status

struct StatusPage: View {
    @ObservedObject var controller: AppController
    let go: (SettingsPage) -> Void
    private var motion: MotionService { controller.motion }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: 22) {
                HStack(spacing: 22) {
                    HeadphoneBadge(link: motion.link, enabled: controller.enabled, size: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(motion.link.title).font(.title2.weight(.semibold))
                        Text(motion.tracking && !motion.calibrated ? "正对屏幕坐好，点“校准正前方”" : motion.link.detail)
                            .foregroundStyle(.secondary)
                        if motion.calibrated { Label("已校准 · 数据来自\(motion.sensor)", systemImage: "scope").font(.caption).foregroundStyle(.green) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle("头势控制", isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) }))
                            .toggleStyle(.switch).controlSize(.large).labelsHidden()
                            .disabled(!controller.readyToEnable && !controller.enabled)
                        Text(controller.enabled ? "已开启" : "已暂停").font(.caption.weight(.medium)).foregroundStyle(controller.enabled ? .green : .secondary)
                    }
                }
                Divider().padding(.vertical, 8)
                Label(controller.notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                ReadinessChecklist(controller: controller, go: go)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "最近一次")
                        LastTriggerView(trigger: controller.lastTrigger)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Divider()
                        if controller.events.isEmpty { Text("还没有触发记录").font(.caption).foregroundStyle(.tertiary) }
                        ForEach(Array(controller.events.prefix(6).enumerated()), id: \.offset) { _, e in
                            Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .flash(on: controller.lastTrigger?.id, when: true)
                .frame(width: 290)
            }
        }
    }
}

/// One list for everything needed before head control can run: both permissions, headphones,
/// calibration and at least one bound gesture. Each row carries its own fix-it button.
struct ReadinessChecklist: View {
    @ObservedObject var controller: AppController
    let go: (SettingsPage) -> Void
    private var motion: MotionService { controller.motion }
    private var bound: Int { Gesture.allCases.filter { controller.store.configuration.binding($0).action != .disabled }.count }
    private var done: Int { [motion.authorized, controller.controlTrusted, motion.tracking, motion.calibrated, bound > 0].filter { $0 }.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(title: "准备清单")
                    Spacer()
                    Text(done == 5 ? "全部就绪" : "\(done) / 5 完成")
                        .font(.caption.weight(.medium)).foregroundStyle(done == 5 ? .green : .secondary)
                        .contentTransition(.numericText())
                }
                .padding(.bottom, 10)
                row(icon: "figure.walk.motion", color: .pink, title: "运动与健身",
                    detail: "读取 AirPods 里的头部动作", ok: motion.authorized,
                    info: [("eye", "只读取耳机报告的头部转动，以及你是否在走动"), ("heart.slash", "不读取健康 App、步数或位置数据"), ("internaldrive", "数据只在这台 Mac 上即时计算，不保存、不上传")],
                    action: (motion.authorization == .notDetermined ? "允许" : "打开系统设置", { motion.requestPermission() }), prominent: true)
                Divider().padding(.leading, 46)
                row(icon: "accessibility", color: .blue, title: "辅助功能",
                    detail: "替你按下设定好的快捷键", ok: controller.controlTrusted,
                    info: [("keyboard", "识别到头势时，替你点按一次你设定的键"), ("eye.slash", "不读取输入内容，不记录键盘，不看屏幕"), ("hand.raised", "macOS 要求：任何向其他应用发送按键的工具都需要它"), ("arrow.clockwise", "如果打开开关后仍显示未授权，退出并重新打开本应用")],
                    action: ("去授权", {
                        controller.requestAccessibility()
                        if !controller.controlTrusted { controller.openPrivacy("Privacy_Accessibility") }
                    }), prominent: true)
                Divider().padding(.leading, 46)
                row(icon: "airpodspro", color: .gray, title: "戴上耳机",
                    detail: motion.tracking ? "数据来自\(motion.sensor)" : motion.link.detail, ok: motion.tracking,
                    action: ("重新连接", { motion.reconnect() }))
                Divider().padding(.leading, 46)
                row(icon: "scope", color: .teal, title: "校准正前方",
                    detail: motion.calibrated ? "可随时重新校准" : "正对屏幕坐好，头放正", ok: motion.calibrated,
                    action: motion.tracking ? ("校准", { controller.calibrate() }) : nil, keepActionWhenDone: true)
                Divider().padding(.leading, 46)
                row(icon: "keyboard", color: .indigo, title: "设置头势按键",
                    detail: "已绑定 \(bound) / 6 个头势", ok: bound > 0,
                    action: ("编辑", { go(.gestures) }), keepActionWhenDone: true)
                Text("不需要麦克风、蓝牙、屏幕录制或网络。").font(.caption).foregroundStyle(.tertiary).padding(.top, 10)
            }
            .animation(.spring(duration: 0.3), value: done)
        }
    }

    private func row(icon: String, color: Color, title: String, detail: String, ok: Bool,
                     info: [(String, String)]? = nil, action: (String, () -> Void)?,
                     prominent: Bool = false, keepActionWhenDone: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.body.weight(.medium))
                    if let info { InfoButton(title: "为什么需要\(title)？", points: info) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let action, !ok || keepActionWhenDone {
                if prominent { Button(action.0, action: action.1).buttonStyle(.borderedProminent).controlSize(.small) }
                else { Button(action.0, action: action.1).controlSize(.small) }
            }
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(ok ? Color.green : Color.secondary.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(ok ? "已完成" : "未完成")
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
    }
}

struct LastTriggerView: View {
    let trigger: Trigger?
    var body: some View {
        HStack(spacing: 12) {
            if let trigger {
                GestureGlyph(gesture: trigger.gesture, size: 24).foregroundStyle(trigger.executed ? Color.green : Color.accentColor).frame(width: 34)
                Text(trigger.gesture.title).font(.body.weight(.medium))
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                if trigger.caps.isEmpty { Text(trigger.message).font(.caption).foregroundStyle(.secondary) }
                else { KeycapRow(caps: trigger.caps, size: 13) }
            } else {
                Image(systemName: "hand.wave").font(.title2).foregroundStyle(.tertiary)
                Text("做个头势试试").foregroundStyle(.secondary)
            }
        }
        .id(trigger?.id)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: trigger?.id)
    }
}

// MARK: General

struct GeneralPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    toggleRow("悬浮状态条", "开启时在屏幕顶部显示最近的头势和按键", "rectangle.topthird.inset.filled", $store.configuration.overlay)
                    Divider()
                    toggleRow("提示音", "每完成一个头势都会响一声，可在“头势”页为每个头势选择不同声音", "speaker.wave.2", $store.configuration.sound)
                    Divider()
                    toggleRow("走动时自动暂停", "走路或跑步时不识别头势，停下后自动恢复", "figure.walk", $store.configuration.pauseWhileWalking)
                    Divider()
                    toggleRow("在程序坞显示图标", "关闭后只留在菜单栏，点菜单栏图标打开设置", "dock.rectangle", $controller.showDockIcon)
                }
            }
            if let error = store.error {
                Card {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Spacer()
                        Button("备份原文件并重置") { store.recover() }
                    }
                }
            }
            Text("启动时总是暂停。修改设置、耳机断开或重新校准，也会自动暂停。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func toggleRow(_ title: String, _ detail: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Label { VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: icon) }
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}
