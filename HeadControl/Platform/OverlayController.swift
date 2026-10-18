import SwiftUI
import AppKit

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    private let panel: PassivePanel
    private let controller: AppController
    private let size = NSSize(width: 300, height: 64)
    init(controller: AppController) {
        self.controller = controller
        panel = PassivePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: StatusHUD(controller: controller))
    }
    func sync() {
        let visible = controller.store.configuration.overlay && (controller.enabled || controller.testing)
        guard visible else { panel.orderOut(nil); return }
        if !panel.isVisible, let screen = NSScreen.main {
            panel.setFrame(NSRect(origin: NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24), size: size), display: true)
        }
        panel.orderFrontRegardless()
    }
}

/// Headphone state, then "last gesture → keycaps"; the row bounces on each trigger.
private struct StatusHUD: View {
    @ObservedObject var controller: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    var body: some View {
        HStack(spacing: 12) {
            HeadphoneBadge(link: controller.motion.link, enabled: controller.enabled, size: 36)
            if let hint = controller.blockedHint {
                Image(systemName: "tortoise.fill").font(.system(size: 13)).foregroundStyle(.orange)
                Text(hint).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            } else if let t = controller.lastTrigger {
                GestureGlyph(gesture: t.gesture, size: 16).foregroundStyle(t.executed ? Color.green : Color.accentColor)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                if t.caps.isEmpty { Text(t.gesture.shortTitle).font(.system(size: 12)) }
                else { KeycapRow(caps: t.caps, size: 12, pressed: bounce) }
            } else {
                Text(controller.testing ? "测试中，不发送按键" : "做个头势试试").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if controller.testing { controller.setTesting(false) } else { controller.setEnabled(false) }
            } label: { Image(systemName: "pause.fill") }.buttonStyle(.borderless).help("暂停头势控制")
        }
        .padding(.horizontal, 14).frame(width: 300, height: 64)
        .background(.regularMaterial, in: Capsule())
        .scaleEffect(bounce && !reduceMotion ? 1.06 : 1)
        .onChange(of: controller.lastTrigger?.id) { _, _ in
            withAnimation(.spring(duration: 0.18)) { bounce = true }
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(220)); withAnimation(.spring(duration: 0.3)) { bounce = false } }
        }
    }
}
