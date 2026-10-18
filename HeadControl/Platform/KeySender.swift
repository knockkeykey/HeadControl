import AppKit
import ApplicationServices

@MainActor final class KeySender {
    private var busy = false
    private var held: (CGKeyCode, CGEventFlags)?
    private var ownedFlags: UInt64 = 0
    var canPost: Bool { CGPreflightPostEventAccess() }
    func requestAccess() { _ = CGRequestPostEventAccess() }
    func click(_ shortcut: Shortcut, targetPID: pid_t) async throws {
        guard canPost else { throw Failure("需要在系统设置中授予辅助功能／事件发送权限") }
        guard !busy else { throw Failure("上一次按键尚未结束") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { throw Failure("发键前应用已切换，本次操作已跳过") }
        let physical = CGEventSource.flagsState(.combinedSessionState)
        let conflict: CGEventFlags = [.maskCommand,.maskControl,.maskAlternate,.maskShift,.maskSecondaryFn]
        guard physical.intersection(conflict).isEmpty else { throw Failure("检测到键盘修饰键仍被按住，本次操作已跳过") }
        guard shortcut.keyCode <= 127 else { throw Failure("快捷键键码无效，请重新录入") }
        busy = true
        defer { release(); busy = false }
        let source = CGEventSource(stateID: .privateState)
        let plan: KeyClickPlan
        do { plan = try .make(shortcut,physical:physical.rawValue) }
        catch { throw Failure("快捷键无效或与实际修饰键冲突，请重新录入") }
        let flags = CGEventFlags(rawValue: plan.strokes[0].flags)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true) else { throw Failure("无法构造按键事件") }
        let modifier = Shortcut.modifierKeyCodes.contains(shortcut.keyCode)
        if modifier { down.type = .flagsChanged }
        // Preserve Caps Lock, but never manufacture unrelated held modifiers.
        down.flags = flags.union(physical.intersection(.maskAlphaShift))
        down.setIntegerValueField(.eventSourceUserData, value: 0x48454144)
        held = (shortcut.keyCode,physical.intersection(.maskAlphaShift))
        ownedFlags = flags.rawValue & ~CGEventFlags.maskAlphaShift.rawValue
        // Input methods such as WeType watch right Option at HID level; a session post bypasses them.
        down.post(tap: .cghidEventTap)
        // A short real click, with guaranteed release even if the task is cancelled.
        try await Task.sleep(for:.milliseconds(45))
    }
    func release() {
        guard let (code,baseline) = held else { return }
        defer { held = nil; ownedFlags = 0 }
        guard let up = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: false) else { return }
        if Shortcut.modifierKeyCodes.contains(code) { up.type = .flagsChanged }
        up.flags = CGEventFlags(rawValue:KeyClickPlan.releaseFlags(owned:ownedFlags,current:CGEventSource.flagsState(.combinedSessionState).rawValue,baseline:baseline.rawValue))
        up.setIntegerValueField(.eventSourceUserData, value: 0x48454144); up.post(tap: .cghidEventTap)
    }
    struct Failure: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
}
