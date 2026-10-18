import AppKit
import SwiftUI

/// Exercises production views with synthetic motion and no hardware, audio, key sending or user configuration writes.
@MainActor final class InterfaceProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: AppController?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("headcontrol-ui-\(UUID())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let scenario = CommandLine.arguments.dropFirst().first ?? "navigation"
        let output = CommandLine.arguments.dropFirst(2).first ?? "/tmp/headcontrol-interface.png"
        let store = ConfigurationStore(directory: directory)
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("configuration.json"), let data = try? Data(contentsOf: resource) {
            do { store.configuration = try Configuration.decode(data) }
            catch { fatalError("Invalid interface fixture configuration") }
        }
        let controller = AppController(store: store); self.controller = controller
        controller.setPreviewVisible(true, surface: "settings")
        var time = 0.0
        func feed(_ seconds: Double, roll: Double = 0, pitch: Double = 0) {
            for _ in 0..<Int(seconds / 0.02) {
                time += 0.02
                let sample = MotionSample(time: time, pitch: pitch, roll: roll)
                controller.motion.pose = sample; controller.motion.onSample?(sample)
            }
        }
        NSApp.appearance = NSAppearance(named: scenario == "joint" ? .aqua : .darkAqua)
        switch scenario {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "头势控制 · 界面检查"
        window.contentViewController = NSHostingController(rootView: SettingsRoot(controller: controller))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        if scenario == "navigation" { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            Snapshot.capture(window, to: URL(fileURLWithPath: output))
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
