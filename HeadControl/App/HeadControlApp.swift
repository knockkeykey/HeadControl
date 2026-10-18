import SwiftUI
import AppKit

@main struct HeadControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("头势控制", image: "MenuHead") {
            MenuBarPanel(controller: delegate.controller, openSettings: delegate.showSettings)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController(store: ConfigurationStore())
    private var settingsWindow: NSWindow?
    private var overlay: OverlayController?
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(i + 1) {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[i + 1] == "light" ? .aqua : .darkAqua)
        }
        controller.applyDockPolicy()
        overlay = OverlayController(controller: controller)
        controller.overlayChanged = { [weak self] in self?.overlay?.sync() }
        // Stay in the menu bar unless something needs the user.
        let needsUser = !controller.permissionsReady || controller.store.error != nil
        if needsUser || CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--page") || Snapshot.target != nil { showSettings() }
    }
    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsRoot(controller: controller)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "头势控制"; window.contentMinSize = NSSize(width: 900, height: 660)
            window.contentViewController = NSHostingController(rootView: root)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("HeadControlSettings")
            if CommandLine.arguments.contains("--compact") { window.setContentSize(NSSize(width: 900, height: 660)) }
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let url = Snapshot.target {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                Snapshot.capture(settingsWindow, to: url); exit(0)
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { @MainActor in await controller.prepareToQuit(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
}
