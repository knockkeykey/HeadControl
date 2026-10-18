import AppKit
import Combine

/// One recognized gesture, kept so every view can animate the same moment.
struct Trigger: Equatable {
    let id = UUID()
    let gesture: Gesture
    let caps: [String]
    let executed: Bool
    let message: String
}

@MainActor final class AppController: ObservableObject {
    let store: ConfigurationStore
    let motion = MotionService()
    let keys = KeySender()
    @Published private(set) var enabled = false
    @Published private(set) var testing = false
    @Published private(set) var notice = "先连接耳机并校准，再开启头势控制"
    @Published private(set) var lastTrigger: Trigger?
    @Published private(set) var events: [String] = []
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var postTrusted = CGPreflightPostEventAccess()
    // Calibration test flow: one target at a time, peak travel measured while it is active.
    @Published private(set) var testTarget: Gesture?
    @Published private(set) var testPeaks: [Gesture: Double] = [:]
    @Published private(set) var testPassed: Set<Gesture> = []
    @Published private(set) var testingAll = false
    @Published var showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon"); applyDockPolicy(keepFront: true) }
    }
    private var router = GestureRouter()
    /// A passed gesture keeps measuring its peak until the head returns near neutral.
    private var trailing: Gesture?
    private var operation = false
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    var overlayChanged: (() -> Void)?
    var statusTitle: String { testing ? "正在测试头势" : enabled ? "头势控制已开启" : "已暂停" }
    /// Both AX and post-event access are presented as one "辅助功能" permission.
    var controlTrusted: Bool { accessibilityTrusted && postTrusted }
    var permissionsReady: Bool { motion.authorized && controlTrusted }
    var readyToEnable: Bool { motion.tracking && motion.calibrated && controlTrusted }

    init(store: ConfigurationStore) {
        self.store = store
        store.onChange = { [weak self] in
            guard let self else { return }
            self.router.configurationChanged(); self.enabled = false; self.keys.release()
            self.notice = self.testing ? "设置已更新，可以继续测试" : "设置已更新，头势控制已暂停"
            self.overlayChanged?()
        }
        motion.onSample = { [weak self] sample in self?.receive(sample) }
        motion.onInvalidation = { [weak self] reason in self?.pause(reason) }
        // Forward nested changes so views observing only the controller stay current.
        motion.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ax = AXIsProcessTrusted(), post = self.keys.canPost
                if ax != self.accessibilityTrusted { self.accessibilityTrusted = ax }
                if post != self.postTrusted { self.postTrusted = post }
                if self.enabled && !post { self.pause("辅助功能权限不可用，头势控制已暂停") }
            }
        }
        // Listen automatically once permission exists; the first request comes from the 权限 page.
        if motion.authorized { motion.start() }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        keys.requestAccess(); postTrusted = keys.canPost
    }
    func applyDockPolicy(keepFront: Bool = false) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        // Dropping to accessory deactivates the app; keep the settings window in front.
        if keepFront && !showDockIcon { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) } }
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func setEnabled(_ value: Bool) {
        guard value else { pause("头势控制已暂停"); return }
        guard motion.tracking, motion.calibrated else { notice = "请先连接耳机并校准正前方"; return }
        guard keys.canPost else { notice = "请先在“权限”页授予辅助功能"; return }
        stopTest(); testing = false; enabled = true; router.setMode(.active)
        notice = "已开启：回正后做头势，会点按对应快捷键"
        overlayChanged?()
    }
    func setTesting(_ value: Bool) {
        enabled = false; testing = value; keys.release(); router.setMode(value ? .testing : .paused)
        if !value { stopTest() }
        notice = value ? "测试中，不会发送快捷键" : "测试已结束，头势控制保持暂停"
        overlayChanged?()
    }
    func calibrate() { motion.recenter() }

    // MARK: Calibration test
    func startTest(_ gesture: Gesture, all: Bool = false) {
        if !testing { setTesting(true) }
        testingAll = all; testTarget = gesture; testPeaks[gesture] = 0
        router.setMode(.testing)
    }
    func startAllTests() {
        testPassed.removeAll(); testPeaks.removeAll()
        startTest(Gesture.allCases[0], all: true)
    }
    func stopTest() { testTarget = nil; testingAll = false; trailing = nil }
    func suggestion(for gesture: Gesture) -> Double? {
        guard let peak = testPeaks[gesture], peak >= 8 else { return nil }
        let tuning = store.configuration.tuning[gesture.rawValue] ?? .preset(.standard, for: gesture)
        guard let value = ThresholdAdvisor.suggest(peak: peak, tuning: tuning), abs(value - tuning.angle) >= 1 else { return nil }
        return value
    }
    func applySuggestion(_ gesture: Gesture) {
        guard let value = suggestion(for: gesture) else { return }
        var t = store.configuration.tuning[gesture.rawValue] ?? .preset(.standard, for: gesture)
        t.angle = value; t.neutral = min(t.neutral, value - 1); t.preset = .custom
        store.configuration.tuning[gesture.rawValue] = t
    }

    func shutdown() { pause("应用退出"); motion.stop(); timer?.invalidate() }
    func prepareToQuit() async { pause("正在退出"); keys.release() }

    private func receive(_ sample: MotionSample) {
        for gesture in [testTarget, trailing].compactMap({ $0 }) {
            let travel = gesture.travel(sample)
            if travel > (testPeaks[gesture] ?? 0) + 0.5 { testPeaks[gesture] = travel.rounded() }
        }
        if trailing != nil, max(abs(sample.yaw),abs(sample.pitch),abs(sample.roll)) < 7 { trailing = nil }
        guard let route = router.update(sample,configuration:store.configuration) else { return }
        if testing { showPreview(route); return }
        guard route.executes else { return }
        // Capture only foreground PID, never text, window identity, input focus or IME state.
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { await self.perform(route,targetPID:targetPID) }
    }
    private func perform(_ route: GestureRouter.Route, targetPID: pid_t?) async {
        guard router.accepts(route), enabled, !operation else { return }
        if route.binding.action == .pause {
            lastTrigger = Trigger(gesture:route.gesture,caps:[],executed:true,message:"暂停头势控制")
            pause("已通过\(route.gesture.title)暂停"); return
        }
        guard route.binding.action == .shortcut, let shortcut = route.binding.shortcut, let targetPID else { return }
        operation = true; defer { operation = false }
        do {
            try await keys.click(shortcut,targetPID:targetPID)
            guard router.accepts(route), enabled else { return }
            notice = "\(route.gesture.title) → 已点按 \(shortcut.label)"
            lastTrigger = Trigger(gesture:route.gesture,caps:shortcut.caps,executed:true,message:notice)
            record(notice)
            if store.configuration.sound { NSSound(named:.init("Tink"))?.play() }
        } catch {
            guard router.accepts(route), enabled else { return }
            notice = error.localizedDescription; record(notice)
            lastTrigger = Trigger(gesture:route.gesture,caps:shortcut.caps,executed:false,message:notice)
        }
        overlayChanged?()
    }
    private func showPreview(_ route: GestureRouter.Route) {
        let binding = route.binding
        let caps = binding.action == .shortcut ? (binding.shortcut?.caps ?? []) : []
        let action = binding.action == .shortcut ? (binding.shortcut?.label ?? "尚未录入") : binding.action.title
        let message = "\(route.gesture.title) → \(action)（测试，未发送）"
        lastTrigger = Trigger(gesture:route.gesture,caps:caps,executed:false,message:message)
        record(message)
        if let target = testTarget, target == route.gesture {
            testPassed.insert(target); trailing = target
            if testingAll, let i = Gesture.allCases.firstIndex(of: target), i + 1 < Gesture.allCases.count {
                let next = Gesture.allCases[i + 1]
                testTarget = next; testPeaks[next] = 0
            } else { testTarget = nil; testingAll = false }
        }
        overlayChanged?()
    }
    private func pause(_ reason: String) {
        enabled = false; testing = false; stopTest(); router.setMode(.paused); keys.release()
        notice = reason; overlayChanged?()
    }
    private func record(_ message: String) {
        if events.first == message { return }
        events.insert(message,at:0); if events.count > 24 { events.removeLast(events.count-24) }
    }
}
