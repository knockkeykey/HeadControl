import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case status, gestures, shortcuts, permissions, general
    var id: String { rawValue }
    var title: String { switch self { case .status: "状态"; case .gestures: "头势"; case .shortcuts: "快捷键"; case .permissions: "权限"; case .general: "通用" } }
    var symbol: String { switch self { case .status: "airpodspro"; case .gestures: "person.crop.circle"; case .shortcuts: "keyboard"; case .permissions: "lock.shield"; case .general: "gearshape" } }
    var subtitle: String {
        switch self {
        case .status: "一眼看清：耳机、权限、是否在工作。"
        case .gestures: "小球背对着你，跟你往同一边转。拖动圆弧上的圆点调整动作幅度。"
        case .shortcuts: "每个头势按一个键。点“录制”，直接按键盘。"
        case .permissions: "头势控制需要两项权限，点名称旁的问号看为什么需要。"
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
                        if item == .permissions && !controller.permissionsReady {
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
                    case .shortcuts: ShortcutsPage(controller: controller, store: controller.store)
                    case .permissions: PermissionCards(controller: controller)
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
    private var bound: Int { Gesture.allCases.filter { controller.store.configuration.binding($0).action != .disabled }.count }
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
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "准备清单")
                        step(controller.permissionsReady, "授予两项权限", "运动与健身、辅助功能", action: controller.permissionsReady ? nil : ("去授权", { go(.permissions) }))
                        step(motion.tracking, "戴上耳机", motion.tracking ? "数据来自\(motion.sensor)" : motion.link.detail,
                             action: motion.tracking ? nil : ("重新连接", { motion.reconnect() }))
                        step(motion.calibrated, "校准正前方", "正对屏幕时点一下", action: motion.tracking ? ("校准", { controller.calibrate() }) : nil)
                        step(bound > 0, "设置快捷键", "已绑定 \(bound) / 6 个头势", action: ("编辑", { go(.shortcuts) }))
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "最近一次")
                        HeadOrbView(pose: motion.pose, link: motion.link, enabled: controller.enabled)
                            .frame(height: 170).frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        LastTriggerView(trigger: controller.lastTrigger)
                        Divider()
                        if controller.events.isEmpty { Text("还没有触发记录").font(.caption).foregroundStyle(.tertiary) }
                        ForEach(Array(controller.events.prefix(4).enumerated()), id: \.offset) { _, e in
                            Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .flash(on: controller.lastTrigger?.id, when: true)
                .frame(maxWidth: 340)
            }
        }
    }
    private func step(_ ok: Bool, _ title: String, _ detail: String, action: (String, () -> Void)?) -> some View {
        HStack {
            CheckLine(ok: ok, title: title, detail: detail)
            Spacer()
            if let action { Button(action.0, action: action.1).controlSize(.small) }
        }
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

// MARK: Permissions

struct PermissionCards: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(spacing: 14) {
            card(icon: "figure.walk.motion", color: .pink, title: "运动与健身",
                 subtitle: "读取 AirPods 里的头部动作", ok: controller.motion.authorized,
                 info: [("eye", "只读取耳机报告的头部转动，以及你是否在走动"), ("heart.slash", "不读取健康 App、步数或位置数据"), ("internaldrive", "数据只在这台 Mac 上即时计算，不保存、不上传")],
                 button: controller.motion.authorization == .notDetermined ? "允许" : "打开系统设置",
                 action: { controller.motion.requestPermission() })
            card(icon: "accessibility", color: .blue, title: "辅助功能",
                 subtitle: "替你按下设定好的快捷键", ok: controller.controlTrusted,
                 info: [("keyboard", "识别到头势时，替你点按一次你设定的键"), ("eye.slash", "不读取输入内容，不记录键盘，不看屏幕"), ("hand.raised", "macOS 要求：任何向其他应用发送按键的工具都需要它"), ("arrow.clockwise", "如果打开开关后仍显示未授权，退出并重新打开本应用")],
                 button: "去授权", action: {
                     controller.requestAccessibility()
                     if !controller.controlTrusted { controller.openPrivacy("Privacy_Accessibility") }
                 })
            Text("不需要麦克风、蓝牙、屏幕录制或网络。").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func card(icon: String, color: Color, title: String, subtitle: String, ok: Bool, info: [(String, String)], button: String, action: @escaping () -> Void) -> some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text(title).font(.headline); InfoButton(title: "为什么需要\(title)？", points: info) }
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if ok {
                    Label("已允许", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout.weight(.medium))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(button, action: action).buttonStyle(.borderedProminent)
                }
            }.animation(.spring(duration: 0.3), value: ok)
        }
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
