import SwiftUI
import AppKit

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    private let panel: PassivePanel
    private let controller: AppController
    private let size = NSSize(width: 360, height: 84)
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
            if controller.walkingPaused {
                Label("走动中 · 暂停识别", systemImage: "figure.walk").font(.callout).foregroundStyle(.orange)
            } else if let hint = controller.blockedHint {
                VStack(alignment: .leading, spacing: 3) {
                    Text("未完成头势").font(.caption.weight(.medium)).foregroundStyle(.orange)
                    Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } else if let trigger = controller.hudTrigger {
                LastTriggerView(trigger: trigger)
            } else {
                Text(controller.testing ? "测试中，不发送按键" : "做个头势试试").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if controller.testing { controller.setTesting(false) } else { controller.setEnabled(false) }
            } label: { Image(systemName: "pause.fill") }.buttonStyle(.borderless).help("暂停头势控制")
        }
        .padding(.horizontal, 14).frame(width: 360, height: 84)
        .background(.regularMaterial, in: Capsule())
        .scaleEffect(bounce && !reduceMotion ? 1.06 : 1)
        .onChange(of: controller.lastTrigger?.id) { _, _ in
            withAnimation(.spring(duration: 0.18)) { bounce = true }
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(220)); withAnimation(.spring(duration: 0.3)) { bounce = false } }
        }
    }
}
