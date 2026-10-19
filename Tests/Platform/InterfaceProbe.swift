import AppKit
import SwiftUI

@MainActor private final class InterfaceApplications: ApplicationSwitching {
    func previousApplication(excluding frontmost: pid_t?) -> ApplicationTarget? { nil }
    func switchTo(_ target: ApplicationTarget, isAllowed: @escaping @MainActor () -> Bool) async throws {
        guard isAllowed() else { throw CancellationError() }
        if CommandLine.arguments.contains("application-hud-failure") { throw ApplicationSwitchError.missing }
        Trace.events.append("application:\(target.name)")
    }
}

/// Exercises production views with synthetic motion and no hardware, audio, key sending or user configuration writes.
@MainActor final class InterfaceProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: AppController?
    private var overlay: OverlayController?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("headcontrol-ui-\(UUID())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let scenario = CommandLine.arguments.dropFirst().first ?? "navigation"
        let output = CommandLine.arguments.dropFirst(2).first ?? "/tmp/headcontrol-interface.png"
        let store = ConfigurationStore(directory: directory)
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("configuration.json"), let data = try? Data(contentsOf: resource) {
            do { store.configuration = try Configuration.decode(data) }
            catch { fatalError("Invalid interface fixture configuration") }
        }
        let controller = AppController(store: store, applications: InterfaceApplications()); self.controller = controller
        if scenario.hasPrefix("application") {
            let target = ApplicationTarget(name: ["application-long", "application-hud-failure"].contains(scenario) ? "用于检查长名称换行的目标应用 Application Name" : "文本编辑", path: "/System/Applications/TextEdit.app", bundleIdentifier: "com.apple.TextEdit")
            store.configuration.set(.init(.application, shortcut: .rightOption, application: target), for: .tiltLeft)
        }
        if scenario.hasPrefix("application-hud") {
            let overlay = OverlayController(controller: controller); self.overlay = overlay
            controller.overlayChanged = { [weak overlay] in overlay?.sync() }
        }
        controller.setPreviewVisible(true, surface: "settings")
        var time = 0.0
        func feed(_ seconds: Double, roll: Double = 0, pitch: Double = 0) {
            for _ in 0..<Int(seconds / 0.02) {
                time += 0.02
                let sample = MotionSample(time: time, pitch: pitch, roll: roll)
                controller.motion.pose = sample; controller.motion.onSample?(sample)
            }
        }
        NSApp.appearance = NSAppearance(named: ["joint", "preview-normal", "application-picker-light"].contains(scenario) ? .aqua : .darkAqua)
        switch scenario {
        case "application-feedback", "application-hud", "application-hud-failure":
            controller.setEnabled(true)
            feed(0.3); feed(0.6, roll: -30)
        case "calibration-reminder", "calibration-reminder-start", "calibration-reminder-later":
            controller.motion.calibrated = false
        case "practice":
            controller.startTest(.tiltLeft)
            for _ in 0..<2 { feed(1.1); feed(0.5, roll: -30); feed(0.2) }
        case "joint":
            controller.startJointTest(); controller.setEverydayObservation(true)
            feed(0.3); feed(0.5, roll: 30); feed(0.2)
        case "feedback":
            Trace.failKey = true; controller.setEnabled(true)
            feed(0.3); feed(0.5, roll: -30)
        case "calibration":
            controller.calibrate(); controller.motion.calibrationProgress = 0.55
        default: break
        }
        let size = ["preview-normal", "application-row-normal"].contains(scenario) ? NSSize(width: 1240, height: 860) : NSSize(width: 900, height: 660)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "头势控制 · 界面检查"
        if scenario.hasPrefix("application-hud") {
            window.contentViewController = NSHostingController(rootView: StatusHUD(controller: controller))
            window.setContentSize(NSSize(width: 360, height: 120))
        } else if scenario.hasPrefix("application-picker") {
            controller.setSelectingApplication(true)
            window.contentViewController = NSHostingController(rootView: ApplicationPicker(gesture: .tiltLeft, initialTarget: store.configuration.binding(.tiltLeft).application,
                select: { target in
                    var binding = store.configuration.binding(.tiltLeft); binding.application = target
                    store.configuration.set(binding, for: .tiltLeft); controller.setSelectingApplication(false)
                }, cancel: { controller.setSelectingApplication(false) }))
            window.setContentSize(NSSize(width: 520, height: 550))
        } else {
            SettingsWindow.configure(window)
            window.contentViewController = NSHostingController(rootView: SettingsRoot(controller: controller))
            window.setContentSize(size)
        }
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        if scenario == "navigation" || scenario == "application-interactive" { return }
        Task { @MainActor in
            if scenario.hasPrefix("preview") {
                try? await Task.sleep(for: .milliseconds(100))
                feed(0.3); feed(0.5, roll: -30)
                if scenario == "preview-status" {
                    guard controller.lastTrigger?.gesture == .tiltLeft,
                          controller.lastTrigger?.outcome == .idlePreview,
                          !controller.events.isEmpty, !controller.enabled, !Trace.events.contains("key") else {
                        fatalError("Status page did not recognize synthetic motion while paused")
                    }
                }
            }
            if ["preview-details", "application-row", "application-row-normal", "application-long"].contains(scenario) {
                if let content = window.contentView {
                    @MainActor func scrollViews(_ view: NSView) -> [NSScrollView] {
                        if let scroll = view as? NSScrollView { return [scroll] }
                        return view.subviews.flatMap(scrollViews)
                    }
                    if let scroll = scrollViews(content).max(by: { $0.bounds.width < $1.bounds.width }) {
                        scroll.documentView?.scroll(NSPoint(x: 0, y: 430))
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(900))
            if scenario.hasPrefix("calibration-reminder") {
                guard controller.showCalibrationReminder, let sheet = window.attachedSheet, let content = sheet.contentView else {
                    fatalError("Missing native calibration reminder")
                }
                if scenario != "calibration-reminder" {
                    @MainActor func buttons(_ view: NSView) -> [NSButton] {
                        if let button = view as? NSButton { return [button] }
                        return view.subviews.flatMap(buttons)
                    }
                    let action = scenario == "calibration-reminder-start" ? "校准" : "稍后"
                    guard let button = buttons(content).first(where: { $0.title == action }) else {
                        fatalError("Missing calibration reminder action: \(action)")
                    }
                    button.performClick(nil)
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !controller.showCalibrationReminder, !controller.enabled,
                          controller.motion.calibrating == (action == "校准") else {
                        fatalError("Calibration reminder action did not reach the expected state")
                    }
                }
            }
            if scenario.hasPrefix("application-hud") {
                self.overlay?.sync()
                guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .floating && $0.isVisible }),
                      !panel.canBecomeKey, let content = panel.contentView,
                      panel.frame.height >= content.fittingSize.height - 1 else { fatalError("HUD clipped its action feedback or can steal focus") }
                Snapshot.capture(panel, to: URL(fileURLWithPath: output))
            } else {
                Snapshot.capture(window.attachedSheet ?? window, to: URL(fileURLWithPath: output))
            }
            controller.showCalibrationReminder = false
            try? await Task.sleep(for: .milliseconds(150))
            controller.shutdown(); try? FileManager.default.removeItem(at: directory)
            NSApp.terminate(nil)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown(); try? FileManager.default.removeItem(at: directory)
    }
}
@main struct InterfaceProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = InterfaceProbeDelegate(); app.delegate = delegate
        app.run(); withExtendedLifetime(delegate) {}
    }
}
