import SwiftUI
import AppKit
import Combine

@main struct HeadControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("头势控制", image: "MenuHead") {
            MenuBarPanel(controller: delegate.controller, openSettings: delegate.showSettings)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controller = AppController(store: ConfigurationStore())
    private var settingsWindow: NSWindow?
    private var overlay: OverlayController?
    private var terminating = false
    private var calibrationReminderObserver: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(i + 1) {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[i + 1] == "light" ? .aqua : .darkAqua)
        } else {
            AppTheme.apply(UserDefaults.standard.string(forKey: AppTheme.preferenceKey) ?? "system")
        }
        controller.applyDockPolicy()
        overlay = OverlayController(controller: controller)
        controller.overlayChanged = { [weak self] in self?.overlay?.sync() }
        // Stay in the menu bar unless something needs the user.
        let needsUser = !controller.permissionsReady || controller.store.error != nil
        if needsUser || CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--page") || Snapshot.target != nil { showSettings() }
        calibrationReminderObserver = controller.$showCalibrationReminder
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                guard show, let self, self.controller.showCalibrationReminder, !self.terminating else { return }
                self.showSettings()
            }
    }
    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsRoot(controller: controller)
            let defaultSize = NSSize(width: 1240, height: 860)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: defaultSize), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.delegate = self
            window.title = "头势控制"; window.contentMinSize = NSSize(width: 900, height: 660)
            SettingsWindow.configure(window)
            window.contentViewController = NSHostingController(rootView: root)
            // Hosting can reset the initial content rect to the SwiftUI minimum size.
            window.setContentSize(defaultSize)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("HeadControlSettings")
            // Enlarge an older saved window once; subsequent launches retain the user's size.
            if !UserDefaults.standard.bool(forKey: "settingsWindowSpaciousDefault") {
                let current = window.contentRect(forFrameRect: window.frame).size
                var size = NSSize(width: max(current.width, defaultSize.width), height: max(current.height, defaultSize.height))
                if let screen = window.screen ?? NSScreen.main {
                    let chrome = window.frame.height - current.height
                    size.width = min(size.width, screen.visibleFrame.width)
                    size.height = min(size.height, screen.visibleFrame.height - chrome)
                }
                window.setContentSize(size)
                UserDefaults.standard.set(true, forKey: "settingsWindowSpaciousDefault")
            }
            if CommandLine.arguments.contains("--compact") { window.setContentSize(NSSize(width: 900, height: 660)) }
            window.center(); settingsWindow = window
        }
        controller.setPreviewVisible(true, surface: "settings")
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let url = Snapshot.target {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                Snapshot.capture(settingsWindow, to: url); exit(0)
            }
        }
    }
    func windowWillClose(_ notification: Notification) { controller.setPreviewVisible(false, surface: "settings") }
    func windowDidMiniaturize(_ notification: Notification) { controller.setPreviewVisible(false, surface: "settings") }
    func windowDidDeminiaturize(_ notification: Notification) { controller.setPreviewVisible(true, surface: "settings") }
    func applicationDidHide(_ notification: Notification) { controller.setPreviewVisible(false, surface: "settings") }
    func applicationDidUnhide(_ notification: Notification) {
        controller.setPreviewVisible(settingsWindow?.isVisible == true && settingsWindow?.isMiniaturized == false, surface: "settings")
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
