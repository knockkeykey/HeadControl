import SwiftUI
import AppKit

extension HeadphoneLink.Tone {
    var color: Color {
        switch self { case .off: .secondary; case .warning: .orange; case .connected: .green }
    }
}

/// Rounded surface used for every content block; quieter than a grouped Form, still native.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        // Wrap so multi-child content becomes one card, not one card per child.
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// ❓ button with a plain-language explanation popover.
struct InfoButton: View {
    let title: String
    let points: [(String, String)]
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain).help("为什么需要？").accessibilityLabel("为什么需要\(title)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                ForEach(points, id: \.0) { symbol, text in
                    Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
                }
            }.padding(18).frame(width: 300)
        }
    }
}

/// Headphone icon: grey / orange / green, with a pulse while live or a pause badge while paused.
struct HeadphoneBadge: View {
    let link: HeadphoneLink
    var enabled = false
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var live: Bool { link.tone == .connected && enabled }
    var body: some View {
        ZStack {
            if live && !reduceMotion {
                Circle().fill(Color.green.opacity(0.22))
                    .scaleEffect(pulse ? 1.25 : 0.85).opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle().fill(link.tone.color.opacity(link.tone == .off ? 0.10 : 0.16))
            Image(systemName: "airpodspro")
                .font(.system(size: size * 0.44, weight: .regular))
                .foregroundStyle(link.tone.color)
                .contentTransition(.symbolEffect(.replace))
            if link.tone == .connected && !enabled {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: size * 0.28)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.secondary)
                    .offset(x: size * 0.33, y: size * 0.33)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: link)
        .onAppear { pulse = true }
        .accessibilityElement().accessibilityLabel(link.title + (link.tone == .connected ? (enabled ? "，控制已开启" : "，已暂停") : ""))
    }
}

/// Keycaps rendered like physical keys: ⇧ ⌘ K.
struct KeycapRow: View {
    let caps: [String]
    var size: CGFloat = 13
    var pressed = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in Keycap(text: cap, size: size, pressed: pressed) }
        }.accessibilityElement().accessibilityLabel(caps.joined(separator: " "))
    }
}

struct Keycap: View {
    let text: String
    var size: CGFloat = 13
    var pressed = false
    var tint: Color? = nil
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .padding(.horizontal, size * 0.6).frame(minWidth: size * 2.2, minHeight: size * 2.1)
            .background(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .fill(tint ?? Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(pressed ? 0 : 0.18), radius: 0, y: pressed ? 0 : 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .offset(y: pressed ? 1.5 : 0)
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
    }
}

/// Green-check / dashed-circle status line used by checklists and permission cards.
struct CheckLine: View {
    let ok: Bool
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18)).foregroundStyle(ok ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).strikethrough(false)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }.animation(.default, value: ok)
    }
}

/// Short visual "press" when a trigger id changes; collapses to a fade with Reduce Motion.
struct FlashModifier: ViewModifier {
    let trigger: UUID?
    let active: Bool
    var color: Color = .green
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color, lineWidth: 2).opacity(lit ? 1 : 0))
            .scaleEffect(lit && !reduceMotion ? 1.02 : 1)
            .onChange(of: trigger) { _, _ in
                guard active else { return }
                withAnimation(.spring(duration: 0.18)) { lit = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(380))
                    withAnimation(.easeOut(duration: 0.6)) { lit = false }
                }
            }
    }
}
extension View {
    func flash(on trigger: UUID?, when active: Bool, color: Color = .green) -> some View { modifier(FlashModifier(trigger: trigger, active: active, color: color)) }
}
