import SwiftUI

struct ShortcutsPage: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ConfigurationStore
    @State private var recording: Gesture?

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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Gesture.allCases) { row($0) }
            }
            HStack {
                Text("默认：左歪头 → 右 ⌥，完整点头 → ↩。其余不操作。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { store.configuration.bindings = Configuration.defaultBindings }
            }
        }
    }

    private func row(_ g: Gesture) -> some View {
        let binding = store.configuration.binding(g)
        let firing = controller.lastTrigger?.gesture == g
        return HStack(spacing: 14) {
            GestureGlyph(gesture: g, size: 20).foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(g.title).font(.headline)
                Picker("动作", selection: actionBinding(g)) { ForEach(ActionKind.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize().controlSize(.small)
            }
            Spacer()
            switch binding.action {
            case .shortcut:
                Button { begin(g) } label: {
                    if let s = binding.shortcut { KeycapRow(caps: s.caps, size: 14, pressed: firing && controller.lastTrigger?.executed == true) }
                    else { Text("录制").foregroundStyle(.secondary) }
                }
                .buttonStyle(.plain).help("点一下重新录制")
                .overlay(alignment: .topTrailing) { if recording == g { Circle().fill(.red).frame(width: 8, height: 8).offset(x: 4, y: -4) } }
            case .pause:
                Label("暂停", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .disabled:
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(recording == g ? Color.red.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: recording == g ? 2 : 1))
        .flash(on: firing ? controller.lastTrigger?.id : nil, when: firing)
        .animation(.spring(duration: 0.15), value: controller.lastTrigger?.id)
    }

    private func begin(_ g: Gesture) {
        controller.setEnabled(false)
        withAnimation(.spring(duration: 0.35)) { recording = g }
    }
    private func actionBinding(_ g: Gesture) -> Binding<ActionKind> {
        Binding(get: { store.configuration.binding(g).action }, set: { action in
            var b = store.configuration.binding(g); b.action = action
            if action == .shortcut, b.shortcut == nil { begin(g) } else { store.configuration.set(b, for: g) }
        })
    }
}
