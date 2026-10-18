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
    @Published private(set) var testSpeeds: [Gesture: SpeedPeak] = [:]
    @Published private(set) var testPassed: Set<Gesture> = []
    @Published private(set) var testingAll = false
    /// The recognizer's own verdict per gesture, refreshed from every calibrated sample.
    @Published private(set) var gestureStatus: [Gesture: GestureStatus] = [:]
    /// Why the last attempt did not fire, shown in the HUD so real use explains itself like the test page.
    @Published private(set) var blockedHint: String?
    @Published var showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon"); applyDockPolicy(keepFront: true) }
    }
    private var router = GestureRouter()
    /// A passed gesture keeps measuring its peak until the head returns near neutral.
    private var trailing: Gesture?
    private var operation = false
    private var suspended = false
    private var timer: Timer?
    private var currentSound: NSSound?
    private var cancellables: Set<AnyCancellable> = []
    var overlayChanged: (() -> Void)?
    var statusTitle: String { testing ? "正在测试头势" : walkingPaused ? "走动中 · 已暂停" : enabled ? "头势控制已开启" : "已暂停" }
    /// Gestures are suspended, not disabled: control resumes by itself once walking stops.
    var walkingPaused: Bool { motion.walking && store.configuration.pauseWhileWalking && (enabled || testing) }
    /// Both AX and post-event access are presented as one "辅助功能" permission.
    var controlTrusted: Bool { accessibilityTrusted && postTrusted }
    var permissionsReady: Bool { motion.authorized && controlTrusted }
    var readyToEnable: Bool { motion.tracking && motion.calibrated && controlTrusted }

    init(store: ConfigurationStore) {
        self.store = store
        store.onChange = { [weak self] in
            guard let self else { return }
            // New settings apply to the next gesture; control stays on.
            self.router.configurationChanged(); self.keys.release()
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
        guard keys.canPost else { notice = "请先在“状态”页的准备清单里授予辅助功能"; return }
        stopTest(); testing = false; enabled = true; router.setMode(.active)
        notice = "已开启：做头势会点按对应快捷键"
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
        testingAll = all; testTarget = gesture; testPeaks[gesture] = 0; testSpeeds[gesture] = SpeedPeak()
        router.setMode(.testing)
    }
    func startAllTests() {
        testPassed.removeAll(); testPeaks.removeAll(); testSpeeds.removeAll()
        startTest(Gesture.allCases[0], all: true)
    }
    func stopTest() { testTarget = nil; testingAll = false; trailing = nil }
    struct Suggestion: Equatable { var angle: Double; var speed: Double? }
    /// Measured speed of the last test movement, on the same scale as the speed slider.
    func measuredSpeed(for gesture: Gesture) -> Double? {
        guard let peak = testSpeeds[gesture], peak.measured else { return nil }
        let value = peak.effective(sequence: gesture.isSequence)
        return value > 0 ? value : nil
    }
    /// One suggestion for both angle and speed, offered only when it changes something.
    func suggestion(for gesture: Gesture) -> Suggestion? {
        guard let peak = testPeaks[gesture], peak >= 8 else { return nil }
        let tuning = store.configuration.tuning[gesture.rawValue] ?? .preset(.standard, for: gesture)
        guard let angle = ThresholdAdvisor.suggest(peak: peak, tuning: tuning) else { return nil }
        let speed = measuredSpeed(for: gesture).flatMap { ThresholdAdvisor.suggestSpeed(peak: $0) }
        let changesAngle = abs(angle - tuning.angle) >= 1
        let changesSpeed = speed.map { abs($0 - tuning.speed) >= 5 } ?? false
        return changesAngle || changesSpeed ? Suggestion(angle: angle, speed: speed) : nil
    }
    func applySuggestion(_ gesture: Gesture) {
        guard let value = suggestion(for: gesture) else { return }
        var t = store.configuration.tuning[gesture.rawValue] ?? .preset(.standard, for: gesture)
        t.angle = value.angle; t.neutral = min(t.neutral, value.angle - 1); t.preset = .custom
        if let speed = value.speed { t.speed = speed }
        store.configuration.tuning[gesture.rawValue] = t
    }

    func shutdown() { pause("应用退出"); motion.stop(); timer?.invalidate() }
    func prepareToQuit() async { pause("正在退出"); keys.release() }

    private func receive(_ sample: MotionSample) {
        for gesture in [testTarget, trailing].compactMap({ $0 }) {
            let travel = gesture.travel(sample)
            if travel > (testPeaks[gesture] ?? 0) + 0.5 { testPeaks[gesture] = travel.rounded() }
            if let rate = sample.rate {
                var speed = testSpeeds[gesture] ?? SpeedPeak(); speed.record(gesture.rate(rate))
                if speed != testSpeeds[gesture] { testSpeeds[gesture] = speed }
            }
        }
        if walkingPaused {
            // Drop any half-finished gesture so stopping mid-step cannot complete it.
            if !suspended { suspended = true; router.setMode(.paused); gestureStatus = [:]; overlayChanged?() }
            return
        }
        if suspended { suspended = false; router.setMode(testing ? .testing : .active); overlayChanged?() }
        if trailing != nil, max(abs(sample.yaw),abs(sample.pitch),abs(sample.roll)) < 7 { trailing = nil }
        let route = router.update(sample,configuration:store.configuration)
        publishStatus()
        guard let route else { return }
        if testing { showPreview(route); return }
        guard route.executes else {
            if enabled {
                notice = "\(route.gesture.title) 已识别，但未设置动作"
                lastTrigger = Trigger(gesture:route.gesture,caps:[],executed:false,message:notice)
                record(notice); overlayChanged?()
            }
            return
        }
        // Capture only foreground PID, never text, window identity, input focus or IME state.
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { await self.perform(route,targetPID:targetPID) }
    }
    private func perform(_ route: GestureRouter.Route, targetPID: pid_t?) async {
        guard router.accepts(route), enabled, !operation else { return }
        if route.binding.action == .pause {
            lastTrigger = Trigger(gesture:route.gesture,caps:[],executed:true,message:"暂停头势控制")
            playSound(for: route.gesture)
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
            playSound(for: route.gesture)
        } catch {
            guard router.accepts(route), enabled else { return }
            notice = error.localizedDescription; record(notice)
            lastTrigger = Trigger(gesture:route.gesture,caps:shortcut.caps,executed:false,message:notice)
        }
        overlayChanged?()
    }
    /// Published only on visible change: progress is quantized so 100 Hz samples don't redraw every frame.
    private func publishStatus() {
        let next = router.status.mapValues { st in
            GestureStatus(phase: st.phase, progress: (st.progress * 10).rounded() / 10, speed: st.speed.map { ($0 / 5).rounded() * 5 })
        }
        for (g, st) in next where gestureStatus[g]?.phase != st.phase {
            switch st.phase {
            case .tooSlow:
                let need = Int((store.configuration.tuning[g.rawValue] ?? .preset(.standard, for: g)).speed)
                blockedHint = "\(g.shortTitle)太慢 \(Int(st.speed ?? 0))/\(need)°/s"
            case .fired: blockedHint = nil
            default: break
            }
        }
        if next != gestureStatus { gestureStatus = next }
    }
    private func showPreview(_ route: GestureRouter.Route) {
        let binding = route.binding
        let caps = binding.action == .shortcut ? (binding.shortcut?.caps ?? []) : []
        let action = binding.action == .shortcut ? (binding.shortcut?.label ?? "尚未录入") : binding.action.title
        let message = "\(route.gesture.title) → \(action)（测试，未发送）"
        lastTrigger = Trigger(gesture:route.gesture,caps:caps,executed:false,message:message)
        record(message)
        playSound(for: route.gesture)
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
        enabled = false; testing = false; suspended = false; stopTest(); router.setMode(.paused); keys.release()
        gestureStatus = [:]; blockedHint = nil
        notice = reason; overlayChanged?()
    }
    private func playSound(for gesture: Gesture) {
        guard store.configuration.sound else { return }
        previewSound(store.configuration.sound(gesture))
    }
    /// Plays a system alert sound by name; stops the previous one so rapid gestures don't pile up.
    func previewSound(_ name: String) {
        guard !name.isEmpty, let sound = NSSound(named: .init(name)) else { return }
        currentSound?.stop(); currentSound = sound; sound.play()
    }
    private func record(_ message: String) {
        if events.first == message { return }
        events.insert(message,at:0); if events.count > 24 { events.removeLast(events.count-24) }
    }
}
