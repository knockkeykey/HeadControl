import SwiftUI

struct GesturesPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    @State private var selected: Gesture = .tiltLeft
    @State private var recording: Gesture?
    private var motion: MotionService { controller.motion }
    private func tuning(_ g: Gesture) -> GestureTuning { store.configuration.tuning[g.rawValue] ?? .preset(.standard, for: g) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let gesture = recording {
                Card {
                    ShortcutRecorderPanel(gesture: gesture, save: { shortcut in
                        store.configuration.set(GestureBinding(.shortcut, shortcut: shortcut), for: gesture)
                        withAnimation(.spring(duration: 0.35)) { recording = nil }
                    }, cancel: { withAnimation(.spring(duration: 0.35)) { recording = nil } })
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 0) {
                    HeadOrbView(pose: motion.pose, ghost: ghost, link: motion.link, enabled: controller.enabled)
                        .frame(height: 300).frame(maxWidth: .infinity)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                Circle().fill(controller.walkingPaused ? Color.orange : motion.link.tone.color).frame(width: 8, height: 8)
                                Text(controller.walkingPaused ? "走动中 · 已暂停" : motion.link.title).font(.caption.weight(.medium))
                            }.padding(.horizontal, 10).padding(.vertical, 5).background(.thinMaterial, in: Capsule()).padding(14)
                        }
                }
                testCard.frame(width: 300)
            }
            // Top-aligned so only the selected tile grows; its neighbours keep their compact height.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 12) {
                ForEach(Gesture.allCases) { tile($0) }
            }
            HStack {
                Text("默认：左歪头 → 右 ⌥，完整点头 → ↩，其余不操作。点按键可重新录制。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认按键") { store.configuration.bindings = Configuration.defaultBindings }
            }
        }
    }

    private var ghost: MotionSample? {
        guard let target = controller.testTarget else { return nil }
        return target.ghostPose(angle: tuning(target).angle)
    }

    // MARK: Test flow

    private var testCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "校准与测试")
                if !motion.tracking {
                    CheckLine(ok: false, title: "先戴上耳机", detail: motion.link.detail)
                    Button("重新连接") { motion.reconnect() }
                } else if !motion.calibrated {
                    Text("正对屏幕坐好、头放正，然后点下面的按钮。").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { controller.calibrate() } label: { Label("校准正前方", systemImage: "scope").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else if let target = controller.testTarget {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                            Circle().trim(from: 0, to: Double(controller.testPassed.count) / 6).stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90)).animation(.spring, value: controller.testPassed.count)
                            GestureGlyph(gesture: target, size: 20).foregroundStyle(Color.accentColor)
                        }.frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.title).font(.headline)
                            Text(target.prompt).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("跟着蓝色虚线转，让实线和它重合。动作干脆一点更容易识别。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("结束测试") { controller.setTesting(false) }
                } else {
                    Label("已校准 · \(motion.sensor)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                    Text("逐个做一遍 6 个头势，测完会按你的实际动作给出建议。测试时不会发送按键。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { controller.startAllTests() } label: { Label("依次测试全部", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    HStack {
                        Button("重新校准") { controller.calibrate() }
                        if controller.testing { Button("结束测试") { controller.setTesting(false) } }
                    }
                    if !controller.testPassed.isEmpty {
                        Text("已通过 \(controller.testPassed.count) / 6").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Tiles

    private func tile(_ g: Gesture) -> some View {
        let t = tuning(g)
        let isSelected = selected == g
        let firing = controller.lastTrigger?.gesture == g
        let suggestion = controller.suggestion(for: g)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                GestureGlyph(gesture: g, size: 14).foregroundStyle(Color.accentColor)
                Text(g.title).font(.callout.weight(.medium))
                if isSelected { InfoButton(title: g.title, points: helpPoints(g), help: "说明") }
                Spacer()
                if controller.testPassed.contains(g) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).transition(.scale)
                }
            }
            ArcGauge(value: motion.calibrated ? g.travel(motion.pose) : 0,
                     threshold: angleBinding(g), neutral: t.neutral,
                     peak: controller.testPeaks[g], suggestion: suggestion?.angle,
                     lit: controller.testTarget == g, ready: ready(g))
                .frame(height: 112)
            statusLine(g, t)
            actionRow(g)
            HStack {
                if suggestion != nil {
                    Button("采用建议") { controller.applySuggestion(g) }.controlSize(.small).tint(.orange)
                } else {
                    Text(t.preset.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(controller.testTarget == g ? "测试中…" : "测试") { controller.startTest(g) }
                    .controlSize(.small).disabled(!motion.calibrated || controller.testTarget == g)
            }
            if isSelected {
                Divider().padding(.vertical, 4)
                controls(g)
                    .transition(.opacity)
            }
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
        recording == g ? Color.red.opacity(0.6) : selected ? Color.accentColor : Color.primary.opacity(0.06)
    }

    // MARK: Key binding (formerly the Shortcuts page)

    /// What this gesture does: a compact action menu plus the bound key, which is also the record button.
    private func actionRow(_ g: Gesture) -> some View {
        let binding = store.configuration.binding(g)
        let firing = controller.lastTrigger?.gesture == g
        return HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.tertiary)
            Picker("动作", selection: actionBinding(g)) { ForEach(ActionKind.allCases) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize().controlSize(.small)
            Spacer(minLength: 4)
            switch binding.action {
            case .shortcut:
                Button { beginRecording(g) } label: {
                    if let s = binding.shortcut { KeycapRow(caps: s.caps, size: 12, pressed: firing && controller.lastTrigger?.executed == true) }
                    else { Label("录制", systemImage: "record.circle").font(.caption).foregroundStyle(.red) }
                }
                .buttonStyle(.plain).help("点一下重新录制").accessibilityLabel("为\(g.title)录制快捷键")
            case .pause:
                Image(systemName: "pause.circle").foregroundStyle(.secondary).help("触发时暂停头势控制")
            case .disabled:
                EmptyView()
            }
        }
        .frame(height: 26)
        .opacity(binding.action == .disabled ? 0.7 : 1)
    }

    private func beginRecording(_ g: Gesture) {
        controller.setEnabled(false)
        withAnimation(.spring(duration: 0.35)) { recording = g; selected = g }
    }
    private func actionBinding(_ g: Gesture) -> Binding<ActionKind> {
        Binding(get: { store.configuration.binding(g).action }, set: { action in
            var b = store.configuration.binding(g); b.action = action
            if action == .shortcut, b.shortcut == nil { beginRecording(g) } else { store.configuration.set(b, for: g) }
        })
    }

    /// Green only when the recognizer would actually accept this gesture right now, not merely when the angle is past the knob.
    private func ready(_ g: Gesture) -> Bool {
        guard let phase = controller.gestureStatus[g]?.phase else { return false }
        return phase == .holding || phase == .fired
    }

    /// The recognizer's actual decision for this gesture, so "reached the gauge" and "fires" never disagree silently.
    @ViewBuilder private func statusLine(_ g: Gesture, _ t: GestureTuning) -> some View {
        if motion.calibrated, let st = controller.gestureStatus[g] {
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
            t.angle = value; t.neutral = min(t.neutral, value - 1); t.preset = .custom
            store.configuration.tuning[g.rawValue] = t
        })
    }

    // MARK: Inline controls (selected tile only)

    private func controls(_ g: Gesture) -> some View {
        let t = tuning(g)
        let sound = store.configuration.sound(g)
        return VStack(alignment: .leading, spacing: 10) {
            row("灵敏度") {
                Picker("灵敏度", selection: Binding(get: { t.preset }, set: { value in
                    if value != .custom { store.configuration.tuning[g.rawValue] = .preset(value, for: g) }
                })) { ForEach(Sensitivity.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
            }
            row("速度") { SpeedSlider(value: speedBinding(g), measured: controller.measuredSpeed(for: g)) }
            row("提醒音") {
                HStack(spacing: 6) {
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
        }
        .controlSize(.small)
    }
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            content()
        }
    }
    private func helpPoints(_ g: Gesture) -> [(String, String)] {
        [("hand.draw", g.isSequence
            ? "做一个完整的\(g == .nod ? "低头再抬起" : "左右摇头再回正")，太慢不会触发。"
            : "歪到圆点的位置并停一下就触发，稍微收回一点就能再次触发。"),
         ("circle.circle", "拖动白色圆点调整动作幅度。蓝色是当前幅度，灰色是回正区，橙色是测试后的建议位置。"),
         ("gauge.with.needle", "速度越靠右，只有越干脆的动作才会触发；橙点是你上次测试的速度。"),
         ("speaker.wave.2", "每完成一次这个头势都会播放所选提醒音。"),
         ("pause.circle", "修改参数后头势控制会自动暂停。")]
    }
    private func speedBinding(_ g: Gesture) -> Binding<Double> {
        Binding(get: { tuning(g).speed }, set: { value in
            var t = tuning(g)
            let rounded = (value / 5).rounded() * 5
            guard t.speed != rounded else { return }
            t.speed = rounded; t.preset = .custom
            store.configuration.tuning[g.rawValue] = t
        })
    }
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
