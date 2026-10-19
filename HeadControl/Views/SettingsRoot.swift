import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case status, gestures, general
    var id: String { rawValue }
    var title: String { switch self { case .status: "状态"; case .gestures: "头势"; case .general: "通用" } }
    var symbol: String { switch self { case .status: "airpodspro"; case .gestures: "person.crop.circle"; case .general: "gearshape" } }
    var subtitle: String {
        switch self {
        case .status: "按清单完成准备，点击“启动头势控制”就能开始使用。"
        case .gestures: "开启需要的头势，再选择动作。小球背对着你，拖动圆弧上的圆点调整动作幅度。"
        case .general: "外观、悬浮条、提示音、走动暂停和程序坞图标。"
        }
    }
}

struct SettingsRoot: View {
    @ObservedObject var controller: AppController
    @State private var page: SettingsPage? = SettingsRoot.initialPage
    @State private var hoveringContent = false
    @State private var columns: NavigationSplitViewVisibility = .all
    static var initialPage: SettingsPage {
        if let i = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.indices.contains(i + 1),
           let p = SettingsPage(rawValue: CommandLine.arguments[i + 1]) { return p }
        return .status
    }
    var body: some View {
        split.frame(minWidth: 900, minHeight: 660)
            .alert("请先校准正前方", isPresented: $controller.showCalibrationReminder) {
                Button("校准") { controller.calibrate() }
                    .keyboardShortcut(.defaultAction)
                Button("稍后", role: .cancel) {}
            } message: {
                Text("正对屏幕，点击“校准”后保持静止一秒，即可自动完成校准。")
            }
    }
    private var split: some View {
        NavigationSplitView(columnVisibility: $columns) {
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
            }
            .overlay(alignment: .topTrailing) {
                // Shares the title bar row with the traffic lights; the window has no toolbar.
                sidebarButton
                    .frame(height: SettingsWindow.titleBarHeight)
                    .padding(.trailing, 10)
                    .offset(y: -SettingsWindow.titleBarHeight)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 230)
            .toolbar(removing: .sidebarToggle)
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
                    case .gestures: GesturesPage(controller: controller, store: controller.store, showStatus: { page = .status })
                    case .general: GeneralPage(controller: controller, store: controller.store)
                    }
                }
                .padding(28).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
                .background(OverlayScrollbars(hovering: hoveringContent))
            }
            .onHover { hoveringContent = $0 }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topLeading) {
                // With the sidebar collapsed, keep the controls beside the traffic lights.
                if columns == .detailOnly {
                    sidebarButton
                        .frame(height: SettingsWindow.titleBarHeight)
                        .padding(.leading, 78)
                        .offset(y: -SettingsWindow.titleBarHeight)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(.hidden, for: .windowToolbar)
    }

    private var sidebarAction: String { columns == .detailOnly ? "显示侧边栏" : "隐藏侧边栏" }

    private var sidebarButton: some View {
        SidebarIconButton(symbol: "sidebar.left", label: sidebarAction) {
            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
        }
    }
}

/// Window chrome shared by the app and interface probes: no toolbar, content under the title bar.
@MainActor enum SettingsWindow {
    static let titleBarHeight: CGFloat = 28
    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
    }
}

private struct SidebarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Configure the enclosing scroll view without changing system-wide preferences.
private struct OverlayScrollbars: NSViewRepresentable {
    let hovering: Bool

    func makeNSView(context: Context) -> ScrollbarAnchor { ScrollbarAnchor() }
    func updateNSView(_ view: ScrollbarAnchor, context: Context) { view.setHovering(hovering) }

    final class ScrollbarAnchor: NSView {
        private var hovering = false
        private weak var scrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI finishes attaching the document hierarchy after creating the anchor.
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }

        func setHovering(_ value: Bool) {
            let entered = value && !hovering
            hovering = value
            configure()
            if entered { scrollView?.flashScrollers() }
        }

        private func configure() {
            guard let scrollView = enclosingScrollView else { return }
            if self.scrollView !== scrollView {
                self.scrollView = scrollView
                // SwiftUI reapplies the system preference after attaching its scroll view.
                // Keep this one view in overlay mode even when the system uses legacy bars.
                styleObservation = scrollView.observe(\.scrollerStyle, options: [.new]) { view, _ in
                    if view.scrollerStyle != .overlay { view.scrollerStyle = .overlay }
                }
            }
            // Overlay scrollers never reserve a track beside the content. AppKit handles
            // the knob's fading, edge hover, dragging and light/dark appearance.
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            scrollView.autohidesScrollers = true
        }
    }
}

// MARK: Status

struct StatusPage: View {
    @ObservedObject var controller: AppController
    @State private var hoveringEvents = false
    let go: (SettingsPage) -> Void
    private var motion: MotionService { controller.motion }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: 22) {
                HStack(spacing: 22) {
                    HeadphoneBadge(link: motion.link, enabled: controller.enabled, size: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(motion.link.title).font(.title2.weight(.semibold))
                        Text(motion.tracking && !motion.calibrated ? motion.calibrationHint : motion.link.detail)
                            .foregroundStyle(.secondary)
                        if motion.calibrating { ProgressView(value: motion.calibrationProgress).frame(width: 180) }
                        if motion.calibrated { Label("已校准 · 数据来自\(motion.sensor)", systemImage: "scope").font(.caption).foregroundStyle(.green) }
                    }
                    Spacer()
                    Label(controller.enabled ? (controller.walkingPaused ? "走动中 · 自动暂停" : "头势控制已开启") : "尚未启动",
                          systemImage: controller.enabled ? (controller.walkingPaused ? "pause.circle.fill" : "checkmark.circle.fill") : "pause.circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(controller.enabled ? (controller.walkingPaused ? Color.orange : .green) : .secondary)
                        .fixedSize()
                }
                Button { controller.setEnabled(!controller.enabled) } label: {
                    Label(controller.enabled ? "停止头势控制" : "启动头势控制",
                          systemImage: controller.enabled ? "stop.fill" : "power")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ControlLaunchButtonStyle(running: controller.enabled))
                .disabled(!controller.readyToEnable && !controller.enabled)
                .padding(.top, 20)
                .accessibilityHint(controller.enabled ? "停止通过头势执行动作" : "启动后，做头势即可执行设定的动作")
                Text(controller.enabled ? (controller.walkingPaused ? "走动时暂停识别，停下后自动恢复。" : "正在运行，做头势即可执行设定的动作。") :
                        (controller.readyToEnable ? "点击上方按钮，开始用头势执行动作。" : "请先完成下方准备清单，再点击启动。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Divider().padding(.vertical, 8)
                Label(controller.notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                ReadinessChecklist(controller: controller, go: go)
                Card(fillsHeight: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "最近一次")
                        VStack(spacing: 12) {
                            PoseReader(feed: motion.poseFeed) { [link = motion.link, enabled = controller.enabled] pose in
                                HeadOrbView(pose: pose, link: link, enabled: enabled, showsBodyBackdrop: true)
                            }
                                .frame(height: 160)
                                .accessibilityLabel("实时头部姿态，默认正后方视角")
                            Group {
                                if controller.lastTrigger == nil {
                                    Text("做个头势试试").font(.headline).foregroundStyle(.secondary)
                                } else {
                                    LastTriggerView(trigger: controller.lastTrigger)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 228)
                        VStack(alignment: .leading, spacing: 10) {
                            Divider()
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    if controller.events.isEmpty {
                                        Text("还没有触发记录").font(.caption).foregroundStyle(.tertiary)
                                            .frame(maxWidth: .infinity)
                                    }
                                    ForEach(Array(controller.events.prefix(6).enumerated()), id: \.offset) { _, e in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(e.time, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.tertiary)
                                            Text(e.message + (e.count > 1 ? " ×\(e.count)" : "")).textSelection(.enabled)
                                        }.font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OverlayScrollbars(hovering: hoveringEvents))
                            }
                            .onHover { hoveringEvents = $0 }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                }
                .flash(on: controller.lastTrigger?.id, when: true)
                .frame(width: 290, height: 420)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { controller.setPreviewVisible(true, surface: "status") }
        .onDisappear { controller.setPreviewVisible(false, surface: "status") }
    }
}

private struct ControlLaunchButtonStyle: ButtonStyle {
    let running: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .foregroundStyle(running || !isEnabled ? Color.primary : .white)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(running || !isEnabled ? Color.primary.opacity(0.08) : Color.accentColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(running ? 0.12 : 0.04))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

/// One list for everything needed before head control can run: both permissions, headphones,
/// calibration and at least one bound gesture. Each row carries its own fix-it button.
struct ReadinessChecklist: View {
    @ObservedObject var controller: AppController
    let go: (SettingsPage) -> Void
    private var motion: MotionService { controller.motion }
    private var bound: Int { controller.store.configuration.enabledGestures.filter { controller.store.configuration.binding($0).action != .disabled }.count }
    private var done: Int { [motion.authorized, controller.controlTrusted, motion.tracking, motion.calibrated, bound > 0].filter { $0 }.count }

    var body: some View {
        Card(fillsHeight: true) {
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
                    detail: motion.calibrated ? "可随时重新校准" : motion.calibrationHint, ok: motion.calibrated,
                    action: motion.tracking ? (motion.calibrating ? "取消" : "校准", { if motion.calibrating { motion.cancelCalibration() } else { controller.calibrate() } }) : nil, keepActionWhenDone: true)
                Divider().padding(.leading, 46)
                row(icon: "keyboard", color: .indigo, title: "设置头势动作",
                    detail: "已开启并绑定 \(bound) 个头势", ok: bound > 0,
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
        HStack(alignment: .top, spacing: 10) {
            if let trigger {
                GestureGlyph(gesture: trigger.gesture, size: 20)
                    .foregroundStyle(trigger.outcome == .skipped ? Color.orange : trigger.executed ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(trigger.gesture.title).font(.callout.weight(.medium))
                        if !trigger.caps.isEmpty { KeycapRow(caps: trigger.caps, size: 11) }
                    }
                    if let target = trigger.application { ApplicationTargetLabel(target: target).font(.callout) }
                    Text(trigger.outcome.title).font(.caption.weight(.medium))
                        .foregroundStyle(trigger.outcome == .skipped ? .orange : .secondary)
                    if trigger.outcome == .skipped {
                        Text(trigger.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Image(systemName: "hand.wave").font(.title2).foregroundStyle(.tertiary)
                Text("做个头势试试").foregroundStyle(.secondary)
            }
        }
        .id(trigger?.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: trigger?.id)
    }
}

// MARK: General

struct GeneralPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    @AppStorage(AppTheme.preferenceKey) private var theme = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label { VStack(alignment: .leading) { Text("外观"); Text("跟随系统，或固定使用浅色、深色主题").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "circle.lefthalf.filled") }
                        Spacer()
                        Picker("外观", selection: $theme) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    Divider()
                    toggleRow("悬浮状态条", "开启时在屏幕顶部显示最近的头势和动作", "rectangle.topthird.inset.filled", $store.configuration.overlay)
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
            Text("启动、耳机断开、重新校准、屏幕休眠或会话离开后保持暂停。修改设置会清空未完成动作，控制保持当前状态；修改识别参数后需重新测试。").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: theme) { _, value in AppTheme.apply(value, animated: true) }
    }
    private func toggleRow(_ title: String, _ detail: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Label { VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: icon) }
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}
