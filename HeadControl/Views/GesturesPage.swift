import SwiftUI

struct GesturesPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    @State private var selected: Gesture = .tiltLeft
    @State private var advanced = false
    private var motion: MotionService { controller.motion }
    private func tuning(_ g: Gesture) -> GestureTuning { store.configuration.tuning[g.rawValue] ?? .preset(.standard, for: g) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 0) {
                    HeadOrbView(pose: motion.pose, ghost: ghost, link: motion.link, enabled: controller.enabled)
                        .frame(height: 300).frame(maxWidth: .infinity)
                        .overlay(alignment: .bottomLeading) { poseReadout.padding(14) }
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                Circle().fill(motion.link.tone.color).frame(width: 8, height: 8)
                                Text(motion.link.title).font(.caption.weight(.medium))
                            }.padding(.horizontal, 10).padding(.vertical, 5).background(.thinMaterial, in: Capsule()).padding(14)
                        }
                }
                testCard.frame(width: 300)
            }
            MotionDataPanel(motion: motion, microphone: controller.microphone)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Gesture.allCases) { tile($0) }
            }
            detail
        }
        .onDisappear { controller.microphone.stop() }
    }

    private var ghost: MotionSample? {
        guard let target = controller.testTarget else { return nil }
        return target.ghostPose(angle: tuning(target).angle)
    }

    private var poseReadout: some View {
        HStack(spacing: 14) {
            ForEach([("转头", motion.pose.yaw), ("点头", motion.pose.pitch), ("歪头", motion.pose.roll)], id: \.0) { name, value in
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                    Text(motion.tracking ? "\(Int(value.rounded()))°" : "暂无").font(.system(.callout, design: .rounded).weight(.medium)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(motion.tracking ? 1 : 0.4)
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
                    Text("跟着蓝色虚线转，让实线和它重合，最大 \(Int(controller.testPeaks[target] ?? 0))°").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("结束测试") { controller.setTesting(false) }
                } else {
                    Label("已校准 · \(motion.sensor)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                    Text("逐个做一遍 6 个头势，测完会按你的实际幅度给出建议角度。测试时不会发送按键。")
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
                Spacer()
                if controller.testPassed.contains(g) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).transition(.scale)
                }
            }
            ArcGauge(value: motion.calibrated ? g.travel(motion.pose) : 0,
                     threshold: angleBinding(g), neutral: t.neutral,
                     peak: controller.testPeaks[g], suggestion: suggestion,
                     lit: controller.testTarget == g)
                .frame(height: 112)
            HStack {
                if let suggestion {
                    Button("采用建议 \(Int(suggestion))°") { controller.applySuggestion(g) }.controlSize(.small).tint(.orange)
                } else {
                    Text(t.preset.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(controller.testTarget == g ? "测试中…" : "测试") { controller.startTest(g) }
                    .controlSize(.small).disabled(!motion.calibrated || controller.testTarget == g)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { selected = g }
        .flash(on: firing ? controller.lastTrigger?.id : nil, when: firing)
        .animation(.spring(duration: 0.3), value: controller.testPassed)
        .accessibilityElement(children: .contain).accessibilityLabel(g.title)
    }

    private func angleBinding(_ g: Gesture) -> Binding<Double> {
        Binding(get: { tuning(g).angle }, set: { value in
            var t = tuning(g)
            guard t.angle != value else { return }
            t.angle = value; t.neutral = min(t.neutral, value - 1); t.preset = .custom
            store.configuration.tuning[g.rawValue] = t
        })
    }

    // MARK: Detail

    private var detail: some View {
        let t = tuning(selected)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: selected.title, detail: selected.isSequence
                                 ? "识别完整动作：\(selected == .nod ? "低头再回正" : "左右经过再回正")，超过完成时限不触发。"
                                 : "越过触发角度并停留一下就触发，回正后才能再次触发。")
                    Spacer()
                }
                Picker("灵敏度", selection: Binding(get: { t.preset }, set: { value in
                    if value != .custom { store.configuration.tuning[selected.rawValue] = .preset(value, for: selected) }
                })) { ForEach(Sensitivity.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                DisclosureGroup("高级", isExpanded: $advanced) {
                    VStack(spacing: 4) {
                        if !selected.isSequence { TuningSlider(title: "停留时间", value: valueBinding(\.dwell), range: 0.1...1.5, unit: "秒", precision: 2) }
                        if selected.isSequence { TuningSlider(title: "动作完成时限", value: valueBinding(\.completion), range: 0.35...2, unit: "秒", precision: 2) }
                        TuningSlider(title: "回正范围（灰色区域）", value: valueBinding(\.neutral), range: 2...min(15, t.angle - 1), unit: "°", precision: 0)
                        TuningSlider(title: "冷却时间", value: valueBinding(\.cooldown), range: 0.3...3, unit: "秒", precision: 2)
                        HStack { Spacer(); Button("恢复标准参数") { store.configuration.tuning[selected.rawValue] = .preset(.standard, for: selected) } }
                    }.padding(.top, 8)
                }
                HStack(spacing: 16) {
                    legend(Color.accentColor, "当前幅度")
                    legend(Color.secondary.opacity(0.4), "回正区")
                    legend(Color.orange, "建议角度")
                    Text("拖动白色圆点调整触发角度。修改后控制会自动暂停。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) { Capsule().fill(color).frame(width: 14, height: 5); Text(text).font(.caption).foregroundStyle(.secondary) }
    }
    private func valueBinding(_ key: WritableKeyPath<GestureTuning, Double>) -> Binding<Double> {
        Binding(get: { tuning(selected)[keyPath: key] }, set: { value in
            var t = tuning(selected); t[keyPath: key] = value; t.neutral = min(t.neutral, t.angle - 1); t.preset = .custom
            store.configuration.tuning[selected.rawValue] = t
        })
    }
}

struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let precision: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(value, specifier: precision == 0 ? "%.0f" : "%.2f") \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $value, in: range).accessibilityLabel(title).accessibilityValue("\(value) \(unit)")
        }.padding(.vertical, 3)
    }
}
