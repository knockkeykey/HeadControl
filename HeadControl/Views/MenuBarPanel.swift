import SwiftUI
import AppKit

/// MenuBarExtra window: status at a glance plus the few actions needed day to day.
struct MenuBarPanel: View {
    @ObservedObject var controller: AppController
    let openSettings: () -> Void
    private var motion: MotionService { controller.motion }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HeadphoneBadge(link: motion.link, enabled: controller.enabled, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(motion.link.title).font(.headline)
                    Text(controller.statusTitle).font(.caption).foregroundStyle(controller.enabled ? .green : .secondary)
                }
                Spacer()
                Toggle("头势控制", isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!controller.readyToEnable && !controller.enabled)
            }
            HeadOrbView(pose: motion.pose, link: motion.link, enabled: controller.enabled)
                .frame(height: 150).frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            LastTriggerView(trigger: controller.lastTrigger).frame(maxWidth: .infinity, alignment: .leading)
            Text(controller.notice).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !controller.permissionsReady {
                Button { openSettings() } label: { Label("还有权限未授予", systemImage: "exclamationmark.circle.fill") }
                    .buttonStyle(.link).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button { controller.calibrate() } label: { Label("校准", systemImage: "scope") }.disabled(!motion.tracking)
                if controller.testing { Button("结束测试") { controller.setTesting(false) } }
                Spacer()
                Button("设置…", action: openSettings).keyboardShortcut(",")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("退出头势控制").keyboardShortcut("q")
            }.buttonStyle(.borderless)
        }
        .padding(16).frame(width: 320)
    }
}
