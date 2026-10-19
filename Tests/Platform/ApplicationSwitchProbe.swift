import AppKit

/// Disposable apps exercise the production switcher without real keys or user applications.
@MainActor final class ApplicationSwitchProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var receiver: NSRunningApplication?
    private var anchor: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var timeout: Timer?
    private var reopens = 0
    private var phase = "initial focus"
    private let original = NSWorkspace.shared.frontmostApplication
    private var isReceiver: Bool { CommandLine.arguments.dropFirst().first != "sender" }
    private var stateURL: URL { URL(fileURLWithPath: Bundle.main.infoDictionary!["ProbeStatePath"] as! String) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 260, y: 260, width: 460, height: 150), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = isReceiver ? "HeadControl 应用切换测试目标" : "HeadControl 应用切换测试"
        window.contentView?.addSubview(NSTextField(labelWithString: "独立测试窗口，不发送按键、不修改用户配置"))
        window.makeKeyAndOrderFront(nil); self.window = window
        timeout = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in NSApp.terminate(nil) }
        if isReceiver {
            let name = Notification.Name(Bundle.main.bundleIdentifier! + ".minimize")
            observers.append(DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.window?.miniaturize(nil) }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeState() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeState() }
            })
            writeState()
        } else { Task { await run() } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopens += 1
        if let window { window.deminiaturize(nil); window.makeKeyAndOrderFront(nil) }
        if isReceiver { writeState() }
        return true
    }
    private func writeState() {
        try? Data("\(window?.isMiniaturized == true),\(reopens)".utf8).write(to: stateURL, options: .atomic)
    }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() {
                // Workspace completion precedes delivery of the target's reopen event.
                // Observe a stable state rather than racing its pending window changes.
                try await Task.sleep(for: .milliseconds(200))
                if condition() { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: message, code: 1)
    }
    private func foreground(_ app: NSRunningApplication) async throws {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        } else { app.activate(options: [.activateAllWindows]) }
        try await waitFor("failed to focus \(app.processIdentifier), frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")") { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
    }
    private func run() async {
        do {
            let targetURL = URL(fileURLWithPath: CommandLine.arguments[3])
            guard let target = ApplicationCatalog.target(at: targetURL), let id = target.bundleIdentifier else { throw NSError(domain: "invalid receiver", code: 1) }
            let catalog = ApplicationCatalog.installed(in: [targetURL.deletingLastPathComponent(), targetURL.deletingLastPathComponent()])
            guard catalog.filter({ $0.path == target.path }).count == 1 else { throw NSError(domain: "catalog failed to deduplicate", code: 1) }
            let service = ApplicationSwitcher()
            try await foreground(.current)
            phase = "cold launch"
            try await service.switchTo(target, isAllowed: { true })
            try await waitFor("cold launch did not foreground target") { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id }
            receiver = NSWorkspace.shared.frontmostApplication
            guard let receiver else { throw NSError(domain: "no receiver", code: 1) }
            let pid = receiver.processIdentifier
            phase = "already frontmost"
            try await service.switchTo(target, isAllowed: { true })
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw NSError(domain: "frontmost no-op changed target", code: 1) }
            phase = "background running activation"
            let anchorConfiguration = NSWorkspace.OpenConfiguration()
            anchor = try await NSWorkspace.shared.openApplication(at: targetURL.deletingLastPathComponent().appendingPathComponent("Anchor.app"), configuration: anchorConfiguration)
            guard let anchor else { throw NSError(domain: "missing anchor", code: 1) }
            try await waitFor("anchor did not foreground") { NSWorkspace.shared.frontmostApplication?.processIdentifier == anchor.processIdentifier }
            guard !NSApp.isActive else { throw NSError(domain: "sender unexpectedly foreground", code: 1) }
            try await service.switchTo(target, isAllowed: { true })
            try await waitFor("running target did not activate") { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: id).count == 1 else { throw NSError(domain: "duplicated target", code: 1) }

            phase = "hidden restoration"; receiver.hide()
            try await waitFor("could not hide target") { receiver.isHidden }
            try await foreground(.current)
            try await service.switchTo(target, isAllowed: { true })
            try await waitFor("hidden target did not restore") { !receiver.isHidden && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

            phase = "minimized restoration"
            DistributedNotificationCenter.default().postNotificationName(.init(id + ".minimize"), object: nil, userInfo: nil, deliverImmediately: true)
            let receiverState = targetURL.deletingLastPathComponent().appendingPathComponent("receiver-state.txt")
            try await waitFor("target did not minimize") { (try? String(contentsOf: receiverState, encoding: .utf8))?.hasPrefix("true,") == true }
            try await foreground(.current)
            try await service.switchTo(target, isAllowed: { true })
            try await waitFor("minimized target did not reopen") {
                (try? String(contentsOf: receiverState, encoding: .utf8))?.hasPrefix("false,") == true && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            }

            // A moved installation is resolved from its stable bundle identity.
            var relocated = target; relocated.path = targetURL.deletingLastPathComponent().appendingPathComponent("OldLocation.app").path
            phase = "relocation"
            guard ApplicationCatalog.resolvedURL(for: relocated)?.resolvingSymlinksInPath().standardizedFileURL == targetURL.resolvingSymlinksInPath().standardizedFileURL else {
                throw NSError(domain: "bundle identity fallback failed: \(ApplicationCatalog.resolvedURL(for: relocated)?.path ?? "nil"), expected \(target.path)", code: 1)
            }
            phase = "cancellation"; try await foreground(.current)
            try await service.switchTo(relocated, isAllowed: { true })
            try await waitFor("relocated target did not activate") { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

            try await foreground(.current)
            do { try await service.switchTo(target, isAllowed: { false }); throw NSError(domain: "cancelled request executed", code: 1) }
            catch is CancellationError {}
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { throw NSError(domain: "cancelled request took focus", code: 1) }
            do {
                try await service.switchTo(.init(name: "Missing", path: "/nonexistent/HeadControlMissing.app"), isAllowed: { true })
                throw NSError(domain: "missing target did not fail", code: 1)
            } catch ApplicationSwitchError.missing {}
            finish("PASS: native cold launch, background running activation, frontmost no-op, hide/unhide, minimize/reopen, bundle-ID relocation, cancellation, missing target and catalog deduplication; no keys")
        } catch { finish("FAIL at \(phase): \(error.localizedDescription)") }
    }
    private func finish(_ result: String) {
        receiver?.terminate(); anchor?.terminate()
        original?.activate(options: [])
        try? Data(result.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        NSApp.terminate(nil)
    }
}

@main struct ApplicationSwitchProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ApplicationSwitchProbeDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        app.run(); withExtendedLifetime(delegate) {}
    }
}
