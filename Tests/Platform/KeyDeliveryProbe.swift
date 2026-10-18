import AppKit

// Uses the real KeySender in a separate process from a harmless key receiver.
// No keystrokes are sent unless that exact receiver is the foreground application.
@MainActor final class KeyDeliveryProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var monitor: Any?
    private var receiver: NSRunningApplication?
    private var timer: Timer?
    private let keys = KeySender()
    private let arguments = CommandLine.arguments
    private var resultURL: URL { URL(fileURLWithPath: arguments[2]) }
    private var receivedURL: URL { URL(fileURLWithPath: arguments[3]) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if arguments[1] == "receiver" { receive(); return }
        Task { await send() }
    }

    private func receive() {
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 460, height: 160),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window?.title = "HeadControl 后台按键回归测试"
        let label = NSTextField(labelWithString: "仅接收测试按键，不输入文字或执行快捷操作")
        label.frame = NSRect(x: 20, y: 60, width: 420, height: 30)
        window?.contentView?.addSubview(label)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [receivedURL] event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) == 0x48454144 else { return event }
            let line = "\(event.type.rawValue),\(event.keyCode),\(event.modifierFlags.rawValue)\n"
            if let h = try? FileHandle(forWritingTo: receivedURL) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            }
            return nil // Consume every test key; it cannot perform a menu action.
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Do not leave a receiver behind if the sender crashes.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in NSApp.terminate(nil) }
    }

    private func send() async {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "HeadControl background key delivery test")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        guard keys.canPost else { finish("FAIL: Debug 应用没有事件发送权限，未发送任何按键"); return }
        let receiverURL = URL(fileURLWithPath: arguments[4])
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        config.arguments = ["receiver", resultURL.path, receivedURL.path]
        do {
            receiver = try await NSWorkspace.shared.openApplication(at: receiverURL, configuration: config)
            try await Task.sleep(for: .seconds(1))
            guard let receiver else { finish("FAIL: 接收进程未启动"); return }
            receiver.activate(options: [])
            try await Task.sleep(for: .milliseconds(500))
            let shortcuts: [Shortcut] = [
                .returnKey, .rightOption,
                .init(keyCode: 58, label: "左 Option"),
                .init(keyCode: 60, label: "右 Shift"),
                .init(keyCode: 59, label: "左 Control"),
                .init(keyCode: 54, label: "右 Command")
            ]
            for _ in 0..<3 {
                for shortcut in shortcuts {
                    guard !NSApp.isActive else { finish("FAIL: 发送进程意外位于前台"); return }
                    try await keys.click(shortcut, targetPID: receiver.processIdentifier)
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            let lines = try String(contentsOf: receivedURL, encoding: .utf8).split(separator: "\n")
            let events = lines.compactMap { line -> [UInt64]? in
                let values = line.split(separator: ",").compactMap { UInt64($0) }
                return values.count == 3 ? values : nil
            }
            let expected = try (0..<3).flatMap { _ in try shortcuts.flatMap { try KeyClickPlan.make($0, physical: 0).strokes } }
            guard events.count == expected.count else {
                finish("FAIL: expected \(expected.count) events, received \(events.count): \(lines.joined(separator: ";"))"); return
            }
            let relevantFlags: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | 0x207F
            for (event, stroke) in zip(events, expected) {
                let type = stroke.flagsChanged ? NSEvent.EventType.flagsChanged : stroke.down ? .keyDown : .keyUp
                guard event[0] == type.rawValue, event[1] == stroke.code,
                      event[2] & relevantFlags == stroke.flags & relevantFlags else {
                    finish("FAIL: wrong event \(event), expected code=\(stroke.code) flags=\(stroke.flags)"); return
                }
            }
            finish("PASS: 18 background shortcuts, 36 ordered press/release events; Return, right/left Option, right Shift, left Control and right Command")
        } catch { finish("FAIL: \(error.localizedDescription)") }
    }

    private func finish(_ result: String) {
        keys.release()
        receiver?.terminate()
        try? (result + "\n").write(to: resultURL, atomically: false, encoding: .utf8)
        NSApp.terminate(nil)
    }
}

@main enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = KeyDeliveryProbe()
        app.delegate = delegate
        app.setActivationPolicy(CommandLine.arguments[1] == "receiver" ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
