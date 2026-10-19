import SwiftUI

struct GesturesPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    var showStatus: () -> Void = {}
    @State private var selected: Gesture = .tiltLeft
    @State private var recording: Gesture?
    @State private var choosingApplication: Gesture?
    private var motion: MotionService { controller.motion }
    private var enabledGestures: [Gesture] { store.configuration.enabledGestures }
    private var passedCount: Int { controller.testPassed.intersection(enabledGestures).count }
    private func tuning(_ g: Gesture) -> GestureTuning { store.configuration.tuning[g.rawValue] ?? .defaults(for: g) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !controller.enabled { startControlPrompt }
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 0, fillsHeight: true) {
                    PoseReader(feed: motion.poseFeed) { [ghost, link = motion.link, enabled = controller.enabled] pose in
                        HeadOrbView(pose: pose, ghost: ghost, link: link, enabled: enabled, showsBodyBackdrop: true)
                    }
                        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                Circle().fill(controller.walkingPaused ? Color.orange : motion.link.tone.color).frame(width: 8, height: 8)
                                Text(controller.walkingPaused ? "走动中 · 已暂停" : motion.link.title).font(.caption.weight(.medium))
                            }.padding(.horizontal, 10).padding(.vertical, 5).background(.thinMaterial, in: Capsule()).padding(14)
                        }
                }
                testCard.frame(width: 300)
            }
            .fixedSize(horizontal: false, vertical: true)
            jointTestCard
            // Directly above the tiles so the keyboard appears next to the gesture being bound.
            if let gesture = recording {
                Card {
                    ShortcutRecorderPanel(gesture: gesture, save: { shortcut in
                        var binding = store.configuration.binding(gesture)
                        binding.action = .shortcut; binding.shortcut = shortcut
                        store.configuration.set(binding, for: gesture)
                        withAnimation(.spring(duration: 0.35)) { recording = nil }
                    }, cancel: { withAnimation(.spring(duration: 0.35)) { recording = nil } })
                }
                .transition(.scale(scale: 0.97, anchor: .bottom).combined(with: .opacity))
            }
            // Top-aligned so only the selected tile grows; its neighbours keep their compact height.
            // Six native-control cards do not need lazy sizing. Eager rows keep tall
            // parameter panels stable when entering this page or scrolling them offscreen.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(Gesture.allCases.prefix(3))) { tile($0).frame(minWidth: 0, maxWidth: .infinity, alignment: .top) }
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(Gesture.allCases.suffix(3))) { tile($0).frame(minWidth: 0, maxWidth: .infinity, alignment: .top) }
                }
            }
            HStack {
                Text("默认开启左右歪头和完整点头；左歪头 → 右 ⌥，完整点头 → ↩。关闭的头势不参与识别。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认动作") { store.configuration.bindings = Configuration.defaultBindings }
            }
        }
        .onAppear { controller.setPreviewVisible(true, surface: "gestures") }
        .onDisappear {
            controller.setPreviewVisible(false, surface: "gestures")
            choosingApplication = nil; controller.setSelectingApplication(false)
        }
        .sheet(item: $choosingApplication, onDismiss: { controller.setSelectingApplication(false) }) { gesture in
            ApplicationPicker(gesture: gesture, initialTarget: store.configuration.binding(gesture).application, select: { target in
                var binding = store.configuration.binding(gesture)
                binding.action = .application; binding.application = target
                store.configuration.set(binding, for: gesture)
                choosingApplication = nil
            }, cancel: { choosingApplication = nil })
        }
    }

    private var startControlPrompt: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("头势控制未启动").font(.headline)
                    Text("这里仍可查看达标效果、听提醒音。点击启动后，头势才会执行动作。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !controller.readyToEnable {
                        Text(!motion.calibrated ? "请先连接耳机并校准正前方。" : "请先到“状态”页授予辅助功能权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    Button("启动头势控制") { controller.setEnabled(true) }
                        .buttonStyle(.borderedProminent).disabled(!controller.readyToEnable)
                    if !controller.readyToEnable { Button("前往状态页", action: showStatus) }
                }.fixedSize()
            }
        }
    }

    private var ghost: MotionSample? {
        guard let target = controller.testTarget else { return nil }
        return target.ghostPose(angle: tuning(target).angle)
    }

    // MARK: Test flow

    private var testCard: some View {
        Card(fillsHeight: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "校准与测试")
                testStatus
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity)
                Divider()
                testActions
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder private var testStatus: some View {
        VStack(spacing: 12) {
            if !motion.tracking {
                Image(systemName: "airpodspro").font(.system(size: 36)).foregroundStyle(.tertiary)
                VStack(spacing: 5) {
                    Text("先戴上耳机").font(.headline)
                    Text(motion.link.detail).font(.callout).foregroundStyle(.secondary)
                }
            } else if motion.calibrating {
                Image(systemName: "scope").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text(motion.calibrationHint).font(.callout).foregroundStyle(.secondary)
                ProgressView(value: motion.calibrationProgress)
            } else if !motion.calibrated {
                Image(systemName: "scope").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text(motion.calibrationHint + "。点击校准后保持静止一秒。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let target = controller.testTarget {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: Double(controller.practiceCounts[target] ?? 0) / 3).stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.spring, value: controller.practiceCounts[target] ?? 0)
                    GestureGlyph(gesture: target, size: 22).foregroundStyle(Color.accentColor)
                }.frame(width: 58, height: 58)
                VStack(spacing: 5) {
                    Text("\(target.title) · \(controller.practiceCounts[target] ?? 0)/3 次").font(.headline)
                    Text(target.prompt).font(.callout).foregroundStyle(.secondary)
                }
                Text("舒适地做三次，每次都回正。练习会记录实际幅度，未达到当前门槛也能收集；全程不执行动作。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.green)
                Text("已校准 · \(motion.sensor)").font(.headline)
                Text(enabledGestures.isEmpty ? "先打开至少一个头势，再开始测试。" : "逐个练习已开启的 \(enabledGestures.count) 个头势，每个做三次。幅度相近时给出建议，手动采用后再测试。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var testActions: some View {
        VStack(spacing: 10) {
            if !motion.tracking {
                Button { motion.reconnect() } label: { Text("重新连接").frame(maxWidth: .infinity) }
            } else if motion.calibrating {
                Button { motion.cancelCalibration() } label: { Text("取消校准").frame(maxWidth: .infinity) }
            } else if !motion.calibrated {
                Button { controller.calibrate() } label: { Label("校准正前方", systemImage: "scope").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else if controller.testTarget != nil {
                Button { controller.setTesting(false) } label: { Text("结束测试").frame(maxWidth: .infinity) }
            } else {
                Button { controller.startAllTests() } label: { Label("依次练习 · 每个三次", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(enabledGestures.isEmpty)
                HStack {
                    Button("重新校准正前方") { controller.calibrate() }
                    if controller.testing { Button("结束测试") { controller.setTesting(false) } }
                }.controlSize(.regular)
                Text("换坐姿、调整耳机，或回正后角度仍有偏移时使用。正对屏幕，点击后保持静止一秒，将当前朝向设为正前方。校准完成后需手动启动头势控制。")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if !controller.testPassed.isEmpty {
                    Text("当前参数已通过 \(passedCount) / \(enabledGestures.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.bordered).controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    private var jointTestCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "联合测试", detail: "所有已开启头势同时识别，用于检查串扰与日常误触。全程不执行动作。")
                    Spacer()
                    if controller.jointTesting {
                        Button("结束联合测试") { controller.setTesting(false) }
                    } else {
                        Button("开始联合测试") { controller.startJointTest() }
                            .disabled(!motion.calibrated || enabledGestures.isEmpty)
                    }
                }
                if controller.jointTesting {
                    Picker("测试方式", selection: Binding(get: { controller.observingEveryday }, set: { controller.setEverydayObservation($0) })) {
                        Text("做指令动作").tag(false)
                        Text("观察日常动作").tag(true)
                    }.pickerStyle(.segmented)
                    Text(controller.observingEveryday ? "自然看屏幕、说话或低头。此阶段已识别 \(controller.everydayCount) 次，请判断是否为误触；切换阶段后重新计数。" : "依次做需要使用的头势，核对下面的计数和最近记录，检查是否识别成其他动作。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if controller.jointTesting || !controller.jointCounts.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), alignment: .leading) {
                        ForEach(enabledGestures) { gesture in
                            Label("\(gesture.shortTitle) · \(controller.jointCounts[gesture] ?? 0) 次", systemImage: gesture.symbol).font(.caption)
                        }
                    }
                    if let trigger = controller.jointLastTrigger {
                        Text(trigger.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Tiles

    private func tile(_ g: Gesture) -> some View {
        let t = tuning(g)
        let enabled = store.configuration.isEnabled(g)
        let isSelected = selected == g
        let firing = controller.lastTrigger?.gesture == g
        let suggestion = controller.suggestion(for: g)
        let testing = controller.testTarget == g
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                GestureGlyph(gesture: g, size: 15).foregroundStyle(Color.accentColor).frame(width: 20)
                Text(g.title).font(.headline)
                if controller.testPassed.contains(g) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).transition(.scale).help("当前识别参数测试已通过")
                }
                Spacer()
                Toggle("启用\(g.title)", isOn: Binding(get: { store.configuration.isEnabled(g) }, set: { value in
                    store.configuration.recognitionEnabled[g.rawValue] = value
                }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(enabled ? "关闭后不参与识别，也不占用冷却时间" : "开启这个头势")
            }
            HStack(spacing: 6) {
                Text(enabled ? "已开启" : "已关闭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isSelected { InfoButton(title: g.title, points: helpPoints(g), help: "说明") }
                Button { controller.startTest(g) } label: {
                    Label(testing ? "练习中" : "练习", systemImage: testing ? "waveform" : "play.fill")
                        .symbolEffect(.variableColor.iterative, isActive: testing)
                        .fixedSize()
                }
                .controlSize(.small).buttonStyle(.bordered).buttonBorderShape(.capsule)
                .disabled(!enabled || !motion.calibrated || testing)
                .help(!enabled ? "先开启这个头势再测试" : motion.calibrated ? "舒适地做三次这个头势，不执行动作" : "先在右上方完成校准")
            }
            let live = enabled && motion.calibrated
            let threshold = angleBinding(g), peak = controller.testPeaks[g]
            let lit = enabled && controller.hudTrigger?.gesture == g, isReady = enabled && ready(g)
            PoseReader(feed: motion.poseFeed) { pose in
                ArcGauge(value: live ? g.travel(pose) : 0,
                         threshold: threshold, neutral: t.neutral,
                         peak: peak, suggestion: suggestion?.angle,
                         lit: lit, ready: isReady)
            }
                .frame(height: 96)
                .opacity(enabled ? 1 : 0.4)
            statusLine(g, t)
            if suggestion != nil {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    Text("三次练习后建议调整参数").font(.caption)
                    Spacer()
                    Button("采用") { controller.applySuggestion(g) }.controlSize(.small)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let note = controller.practiceNotes[g] {
                Text(note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            // Grouped rows like System Settings: the binding is always visible, tuning only on the selected tile.
            VStack(spacing: 0) {
                actionRow(g)
                if isSelected {
                    controls(g).transition(.opacity)
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border(g, selected: isSelected), lineWidth: isSelected || recording == g ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { withAnimation(.spring(duration: 0.3)) { selected = g } }
        .opacity(controller.walkingPaused ? 0.6 : 1)
        .flash(on: firing ? controller.lastTrigger?.id : nil, when: firing)
        .animation(.spring(duration: 0.3), value: controller.testPassed)
        .accessibilityElement(children: .contain).accessibilityLabel(g.title)
    }

    private func border(_ g: Gesture, selected: Bool) -> Color {
        recording == g || selected ? Color.accentColor : Color.primary.opacity(0.06)
    }

    // MARK: Key binding (formerly the Shortcuts page)

    /// "执行" row: the result reads as a value (keycap / text) with one menu to change it.
    private func actionRow(_ g: Gesture) -> some View {
        let binding = store.configuration.binding(g)
        let firing = controller.lastTrigger?.gesture == g
        return Group {
            if binding.action == .application {
                ViewThatFits(in: .horizontal) {
                    settingRow("执行", labelWidth: 32) {
                        Spacer(minLength: 0)
                        applicationButton(g).fixedSize()
                        actionMenu(g)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("执行").font(.callout); Spacer(); actionMenu(g) }
                        applicationButton(g).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                }
            } else {
                settingRow("执行") {
                    Spacer(minLength: 4)
                    switch binding.action {
                    case .application:
                        EmptyView()
                    case .shortcut:
                        if let s = binding.shortcut {
                            Button { beginRecording(g) } label: {
                                KeycapRow(caps: s.caps, size: 11, pressed: firing && controller.lastTrigger?.executed == true)
                            }
                            .buttonStyle(.plain).help("点按键帽重新录制").accessibilityLabel("为\(g.title)重新录制快捷键")
                        } else {
                            Button("录制快捷键…") { beginRecording(g) }.controlSize(.small)
                        }
                    case .previousApplication:
                        Text("切换到上一个应用").font(.callout)
                    case .pause:
                        Text("暂停头势控制").font(.callout)
                    case .disabled:
                        Text("不操作").font(.callout).foregroundStyle(.secondary)
                    }
                    actionMenu(g)
                }
            }
        }
        .frame(minHeight: 34)
    }

    private func applicationButton(_ g: Gesture) -> some View {
        let target = store.configuration.binding(g).application
        return Button { beginChoosingApplication(g) } label: {
            if let target { ApplicationTargetLabel(target: target).font(.callout) }
            else { Text("选择应用…") }
        }
        .buttonStyle(.plain).help("选择要切换到的应用").accessibilityLabel("为\(g.title)选择应用")
        .accessibilityValue(target?.name ?? "尚未选择")
    }

    private func actionMenu(_ g: Gesture) -> some View {
        let binding = store.configuration.binding(g)
        return Menu {
            Picker("执行", selection: actionBinding(g)) { ForEach(ActionKind.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.inline).labelsHidden()
            if binding.action == .shortcut {
                Divider()
                Button("重新录制快捷键…") { beginRecording(g) }
            } else if binding.action == .application {
                Divider()
                Button("更换应用…") { beginChoosingApplication(g) }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("更改这个头势的动作").accessibilityLabel("更改\(g.title)的动作")
    }

    private func beginRecording(_ g: Gesture) {
        controller.setEnabled(false)
        withAnimation(.spring(duration: 0.35)) { recording = g; selected = g }
    }
    private func beginChoosingApplication(_ g: Gesture) {
        recording = nil; selected = g
        controller.setSelectingApplication(true)
        choosingApplication = g
    }
    private func actionBinding(_ g: Gesture) -> Binding<ActionKind> {
        Binding(get: { store.configuration.binding(g).action }, set: { action in
            var b = store.configuration.binding(g); b.action = action
            if action == .application { beginChoosingApplication(g) }
            else if action == .shortcut, b.shortcut == nil { beginRecording(g) }
            else { store.configuration.set(b, for: g) }
        })
    }

    /// Green only when the recognizer would actually accept this gesture right now, not merely when the angle is past the knob.
    private func ready(_ g: Gesture) -> Bool {
        if controller.hudTrigger?.gesture == g { return true }
        guard let phase = controller.gestureStatus[g]?.phase else { return false }
        return phase == .holding || phase == .fired
    }

    /// The recognizer's actual decision for this gesture, so "reached the gauge" and "fires" never disagree silently.
    @ViewBuilder private func statusLine(_ g: Gesture, _ t: GestureTuning) -> some View {
        if !store.configuration.isEnabled(g) {
            Text("不参与识别，也不占用冷却时间").font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
        } else if motion.calibrated, controller.hudTrigger?.gesture == g {
            Text(controller.hudTrigger?.outcome == .idlePreview ? "已达标 · 未启动控制" : "已达标")
                .font(.caption2).foregroundStyle(.green).frame(height: 14)
        } else if motion.calibrated, let st = controller.gestureStatus[g] {
            let (text, color): (String, Color) = {
                switch st.phase {
                case .release: return ("稍微收回一点，才能再次触发", .secondary)
                case .cooldown: return ("冷却中", .secondary)
                case .below: return ("", .secondary)
                case .mixed: return ("其他方向动作太大，不算\(g.shortTitle)", .orange)
                case .holding: return (g.isSequence ? "已到位，回正完成动作" : "保持住…", .accentColor)
                case .tooSlow: return ("动作太慢（\(Int(st.speed ?? 0)) < \(Int(t.speed)) °/s）", .orange)
                case .fired: return ("已触发", .green)
                }
            }()
            HStack(spacing: 6) {
                if st.phase == .holding && !g.isSequence {
                    ProgressView(value: st.progress).progressViewStyle(.linear).frame(width: 50)
                }
                Text(text).font(.caption2).foregroundStyle(color).lineLimit(1)
            }
            .frame(height: 14)
        } else {
            Color.clear.frame(height: 14)
        }
    }

    private func angleBinding(_ g: Gesture) -> Binding<Double> {
        Binding(get: { tuning(g).angle }, set: { value in
            var t = tuning(g)
            guard t.angle != value else { return }
            t.angle = value; t.neutral = min(t.neutral, value - 1)
            store.configuration.tuning[g.rawValue] = t
        })
    }

    // MARK: Inline controls (selected tile only)

    private func controls(_ g: Gesture) -> some View {
        let t = tuning(g)
        let sound = store.configuration.sound(g)
        return VStack(spacing: 0) {
            if !g.isSequence {
                Divider().padding(.leading, 10)
                DurationSlider(value: dwellBinding(g), info: dwellHelp)
            } else {
                Divider().padding(.leading, 10)
                DurationSlider(value: parameterBinding(g, \.completion, step: 0.05), range: 0.35...2, title: "完成时限", info: completionHelp)
                Divider().padding(.leading, 10)
                DurationSlider(value: parameterBinding(g, \.neutral, step: 1), range: 2...min(15, t.angle - 1), title: "回位范围", info: neutralHelp, step: 1, unit: "°")
            }
            Divider().padding(.leading, 10)
            settingRow("速度", labelWidth: 76, info: speedHelp(g)) {
                Spacer(minLength: 0)
                Toggle("启用\(g.title)的速度条件", isOn: Binding(get: { tuning(g).speedEnabled }, set: { value in
                    var next = tuning(g); next.speedEnabled = value
                    store.configuration.tuning[g.rawValue] = next
                }))
                .toggleStyle(.switch).labelsHidden()
            }
            if t.speedEnabled {
                SpeedSlider(value: speedBinding(g), measured: controller.measuredSpeed(for: g))
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
            Divider().padding(.leading, 10)
            DurationSlider(value: parameterBinding(g, \.cooldown, step: 0.05), range: 0.3...3, title: "冷却时间", info: cooldownHelp)
            Divider().padding(.leading, 10)
            settingRow("提醒音") {
                Picker("提醒音", selection: Binding(get: { sound }, set: { value in
                    store.configuration.sounds[g.rawValue] = value
                    controller.previewSound(value)
                })) {
                    Text("无").tag("")
                    Divider()
                    ForEach(AlertSound.names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button { controller.previewSound(sound) } label: {
                    Image(systemName: store.configuration.sound ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .buttonStyle(.borderless).disabled(sound.isEmpty)
                .help(store.configuration.sound ? "试听" : "提示音已在“通用”中关闭")
                .accessibilityLabel("试听提醒音")
            }
        }
        .controlSize(.small)
    }
    private func settingRow<C: View>(_ label: String, labelWidth: CGFloat = 46, info: [(String, String)]? = nil, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(label).font(.callout).fixedSize()
                if let info { InfoButton(title: label, points: info, help: "了解\(label)") }
            }.frame(width: labelWidth, alignment: .leading)
            content()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
    private func helpPoints(_ g: Gesture) -> [(String, String)] {
        [("hand.draw", g.isSequence
            ? "在完成时限内做一个完整的\(g == .nod ? "低头再抬起" : "左右摇头再回正")。"
            : "越过角度门槛后保持到设定时长即可触发，稍微收回一点就能再次触发。"),
         ("circle.circle", "拖动白色圆点调整动作幅度。蓝色是当前幅度，灰色是回正区，橙色是测试后的建议位置。"),
         ("gauge.with.needle", "速度条件可单独关闭。开启后，滑块越靠右，动作需要越快；橙点是你上次测试的速度。"),
         ("speaker.wave.2", "每完成一次这个头势都会播放所选提醒音。"),
         ("switch.2", "头势开关与执行动作独立。关闭后不参与识别，不播放提醒音，也不会占用其他头势的冷却时间；原有按键和参数会保留。"),
         ("pause.circle", "修改参数会清空未完成的动作，新设置从下一个动作开始生效。")]
    }
    private var dwellHelp: [(String, String)] {
        [("timer", "越过角度门槛后，保持到这个时长才触发。"),
         ("minus.circle", "调短会更快响应，但短暂歪头或转头也更容易触发。"),
         ("plus.circle", "调长需要保持更久，可以过滤短暂动作。")]
    }
    private func speedHelp(_ g: Gesture) -> [(String, String)] {
        [("switch.2", "关闭后不检查动作速度，慢动作也能触发；仍需满足幅度和时间条件。"),
         ("gauge.with.needle", "开启后，滑块越靠右，动作需要越快；越靠左，较慢的动作也能通过。"),
         ("hand.draw", g.isSequence ? "往返两个方向都要达到速度要求，完成整个动作仍需在完成时限内。" : "检查到达角度门槛前后的峰值速度，保持姿势时不必一直移动。"),
         ("circle.fill", "橙点标记上次测试的实际速度，方便你手动比较和调整。")]
    }
    private var completionHelp: [(String, String)] {
        [("timer", "从达到动作幅度开始，到完成点头或摇头并回位，最多允许的时间。"),
         ("plus.circle", "调长给慢动作更多时间；调短要求更快完成。它和速度开关独立生效。")]
    }
    private var neutralHelp: [(String, String)] {
        [("scope", "点头或摇头后，回到距校准正前方这个角度以内，才算完成。"),
         ("plus.circle", "调大更容易完成回位；调小要求回得更正。")]
    }
    private var cooldownHelp: [(String, String)] {
        [("hourglass", "一次触发后，等待这段时间才允许任何头势再次触发。"),
         ("plus.circle", "调长可以减少连续误触；调短适合连续操作。")]
    }
    private func parameterBinding(_ g: Gesture, _ key: WritableKeyPath<GestureTuning, Double>, step: Double) -> Binding<Double> {
        Binding(get: { tuning(g)[keyPath: key] }, set: { value in
            var next = tuning(g)
            let rounded = (value / step).rounded() * step
            guard next[keyPath: key] != rounded else { return }
            next[keyPath: key] = rounded
            store.configuration.tuning[g.rawValue] = next
        })
    }
    private func speedBinding(_ g: Gesture) -> Binding<Double> {
        Binding(get: { tuning(g).speed }, set: { value in
            var t = tuning(g)
            let rounded = (value / 5).rounded() * 5
            guard t.speed != rounded else { return }
            t.speed = rounded
            store.configuration.tuning[g.rawValue] = t
        })
    }
    private func dwellBinding(_ g: Gesture) -> Binding<Double> {
        Binding(get: { tuning(g).dwell }, set: { value in
            var t = tuning(g)
            let rounded = (value / GestureTuning.dwellStep).rounded() * GestureTuning.dwellStep
            guard t.dwell != rounded else { return }
            t.dwell = rounded
            store.configuration.tuning[g.rawValue] = t
        })
    }
}

struct DurationSlider: View {
    @Binding var value: Double
    var range = GestureTuning.dwellRange
    var title = "持续时长"
    var info: [(String, String)]
    var step = GestureTuning.dwellStep
    var unit = "秒"

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(title).font(.callout).fixedSize()
                InfoButton(title: title, points: info, help: "了解\(title)")
                Spacer(minLength: 0)
                Text(displayValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            Slider(value: $value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(Text(displayValue))
                .help("\(title)：\(displayValue)")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var displayValue: String { unit == "°" ? "\(Int(value))°" : String(format: "%.2f %@", value, unit) }
}

/// Unitless speed requirement: slow movements also count ↔ only brisk movements count.
/// An orange tick shows how fast the user's last test movement was, so they can drag relative to it.
struct SpeedSlider: View {
    @Binding var value: Double
    let measured: Double?
    private let range = GestureTuning.speedRange
    var body: some View {
        HStack(spacing: 6) {
            Text("慢").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $value, in: range) { Text("动作速度") }
                .labelsHidden()
                .overlay { GeometryReader { geo in marker(in: geo.size.width) } }
                .accessibilityValue(description)
                .help(description)
            Text("快").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }
    private var description: String {
        fraction < 0.2 ? "慢慢转头也会触发" : fraction < 0.5 ? "正常速度的动作会触发" : "只有干脆的动作才会触发"
    }
    @ViewBuilder private func marker(in width: CGFloat) -> some View {
        if let measured {
            // Approximate inset of the small slider's thumb radius.
            let inset: CGFloat = 8, track = max(0, width - inset * 2)
            let f = min(1, max(0, (measured - range.lowerBound) / (range.upperBound - range.lowerBound)))
            Circle().fill(Color.orange).frame(width: 6, height: 6)
                .position(x: inset + track * f, y: -1).allowsHitTesting(false)
        }
    }
}
