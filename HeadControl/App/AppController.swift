import AppKit
import Combine

enum TriggerOutcome: Equatable {
    case sent, switched, skipped, preview, idlePreview, unbound, paused
    var title: String {
        switch self {
        case .sent: "已识别，已发键"
        case .switched: "已识别，已切换应用"
        case .skipped: "已识别，跳过执行"
        case .preview: "测试识别，未执行动作"
        case .idlePreview: "已达标，未启动控制"
        case .unbound: "已识别，未设置动作"
        case .paused: "已暂停头势控制"
        }
    }
}
struct Trigger: Equatable {
    let id = UUID()
    let gesture: Gesture
    let caps: [String]
    let outcome: TriggerOutcome
    let message: String
    var application: ApplicationTarget? = nil
    var executed: Bool { outcome == .sent || outcome == .switched || outcome == .paused }
}
struct FeedbackEvent: Identifiable, Equatable {
    let id = UUID()
    var time = Date()
    let message: String
    var count = 1
}

@MainActor final class AppController: ObservableObject {
    let store: ConfigurationStore
    let motion = MotionService()
    let keys = KeySender()
    private let applications: any ApplicationSwitching
    @Published private(set) var enabled = false
    @Published private(set) var testing = false
    @Published private(set) var selectingApplication = false
    @Published var showCalibrationReminder = false
    @Published private(set) var notice = "先连接耳机并校准，再开启头势控制"
    @Published private(set) var lastTrigger: Trigger?
    @Published private(set) var events: [FeedbackEvent] = []
    @Published private(set) var hudTrigger: Trigger?
    @Published private(set) var jointTesting = false
    @Published private(set) var jointLastTrigger: Trigger?
    @Published private(set) var observingEveryday = false
    @Published private(set) var jointCounts: [Gesture: Int] = [:]
    @Published private(set) var everydayCount = 0
    @Published private(set) var practiceCounts: [Gesture: Int] = [:]
    @Published private(set) var practiceNotes: [Gesture: String] = [:]
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var postTrusted = CGPreflightPostEventAccess()
    // Calibration test flow: one target at a time, peak travel measured while it is active.
    @Published private(set) var testTarget: Gesture?
    @Published private(set) var testPeaks: [Gesture: Double] = [:]
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
    private var practice: GesturePractice?
    private var practiceResults: [Gesture: GesturePractice] = [:]
    private var practiceRecognitions = 0
    private var attemptRecognized = false
    private var previousConfiguration: Configuration
    private var hintDeadline: Date?
    private var triggerDeadline: Date?
    private var nearAttempts: Set<Gesture> = []
    private var previewSurfaces: Set<String> = []
    private var operation = false
    private var suspended = false
    private var calibrationReminderHandled = false
    private var timer: Timer?
    private let feedback = SoundFeedback()
    private var cancellables: Set<AnyCancellable> = []
    var overlayChanged: (() -> Void)?
    var statusTitle: String { selectingApplication ? "选择应用中 · 暂停执行" : walkingPaused ? "走动中 · 已暂停" : jointTesting ? "联合测试 · 不执行动作" : testing ? "正在练习头势" : enabled ? "头势控制已开启" : "已暂停" }
    /// Gestures are suspended, not disabled: control resumes by itself once walking stops.
    var walkingPaused: Bool { motion.walking && store.configuration.pauseWhileWalking && (enabled || testing) }
    /// Both AX and post-event access are presented as one "辅助功能" permission.
    var controlTrusted: Bool { accessibilityTrusted && postTrusted }
    var permissionsReady: Bool { motion.authorized && controlTrusted }
    var readyToEnable: Bool { motion.tracking && motion.calibrated && controlTrusted }

    init(store: ConfigurationStore, applications: (any ApplicationSwitching)? = nil) {
        self.store = store
        self.applications = applications ?? ApplicationSwitcher()
        previousConfiguration = store.configuration
        store.onChange = { [weak self] in
            guard let self else { return }
            // New settings apply to the next gesture; control stays on.
            self.router.configurationChanged(); self.keys.release()
            self.gestureStatus = [:]; self.blockedHint = nil
            let next = self.store.configuration
            let changed = Gesture.allCases.filter {
                next.isEnabled($0) != self.previousConfiguration.isEnabled($0) || next.tuning[$0.rawValue] != self.previousConfiguration.tuning[$0.rawValue]
            }
            for gesture in changed {
                self.testPassed.remove(gesture); self.practiceResults[gesture] = nil
                self.practiceCounts[gesture] = nil; self.practiceNotes[gesture] = nil
                self.testPeaks[gesture] = nil
            }
            if let target = self.testTarget {
                if !next.isEnabled(target) { self.setTesting(false) }
                else if changed.contains(target) {
                    self.practice = GesturePractice(gesture: target); self.practiceRecognitions = 0; self.attemptRecognized = false
                    self.notice = "参数已修改，请重新完成三次动作"
                }
            }
            if !changed.isEmpty {
                self.nearAttempts.removeAll()
                self.jointCounts.removeAll(); self.everydayCount = 0; self.jointLastTrigger = nil
                if self.jointTesting { self.notice = "识别设置已修改，联合测试记录已重置" }
            }
            if self.jointTesting && next.enabledGestures.isEmpty { self.setTesting(false) }
            self.previousConfiguration = next
            self.syncMotionUsage()
            self.prepareSounds()
            self.overlayChanged?()
        }
        prepareSounds()
        motion.onSample = { [weak self] sample in self?.receive(sample) }
        motion.onInvalidation = { [weak self] reason in
            guard let self else { return }
            self.testPassed.removeAll(); self.practiceResults.removeAll(); self.practiceCounts.removeAll()
            self.practiceNotes.removeAll(); self.testPeaks.removeAll()
            self.jointCounts.removeAll(); self.everydayCount = 0; self.jointLastTrigger = nil
            self.pause(reason)
        }
        motion.onCalibrationResult = { [weak self] message in
            self?.notice = message + "，头势控制保持暂停"
        }
        // Forward nested changes so views observing only the controller stay current.
        motion.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        // Wait for the complete motion update, avoiding transient states while recentering.
        Publishers.CombineLatest3(motion.$tracking, motion.$calibrated, motion.$calibrating)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCalibrationReminder() }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ax = AXIsProcessTrusted(), post = self.keys.canPost
                if ax != self.accessibilityTrusted { self.accessibilityTrusted = ax }
                if post != self.postTrusted { self.postTrusted = post }
                self.refreshFeedback()
                if self.enabled && (!ax || !post) { self.pause("辅助功能权限不可用，头势控制已暂停") }
            }
        }
        // Listen automatically once permission exists; the first request comes from the 状态 page.
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
    func setPreviewVisible(_ visible: Bool, surface: String) {
        let wasPreviewing = previewingGestures
        if visible { previewSurfaces.insert(surface) } else { previewSurfaces.remove(surface) }
        if wasPreviewing != previewingGestures, !enabled, !testing {
            router.setMode(.paused); gestureStatus = [:]; clearTransientFeedback()
        }
        syncMotionUsage()
    }
    private var previewingGestures: Bool {
        previewSurfaces.contains("settings") && !previewSurfaces.isDisjoint(with: ["status", "gestures"])
    }
    private func syncMotionUsage() {
        // Page markers only enable feedback inside the visible settings window.
        let visibleSurfaces = previewSurfaces.subtracting(["status", "gestures"])
        motion.setUsage(active: enabled || testing, preview: !visibleSurfaces.isEmpty, pauseWhileWalking: store.configuration.pauseWhileWalking)
    }
    func setEnabled(_ value: Bool) {
        guard value else { pause("头势控制已暂停"); return }
        guard motion.tracking, motion.calibrated else { notice = "请先连接耳机并校准正前方"; return }
        guard keys.canPost else { notice = "请先在“状态”页的准备清单里授予辅助功能"; return }
        stopTest(); testing = false; enabled = true; suspended = false; router.setMode(.active)
        clearTransientFeedback(); syncMotionUsage()
        notice = "已开启：做头势会执行对应动作"
        overlayChanged?()
    }
    /// Keep enabled/testing state intact; invalidate both partial recognition and queued work.
    func setSelectingApplication(_ value: Bool) {
        guard selectingApplication != value else { return }
        selectingApplication = value
        router.configurationChanged(); keys.release()
        gestureStatus = [:]; clearTransientFeedback(); practice?.interrupt(); attemptRecognized = false
        overlayChanged?()
    }
    func setTesting(_ value: Bool) {
        enabled = false; testing = value; suspended = false; keys.release(); router.setMode(value ? .testing : .paused)
        clearTransientFeedback()
        if !value { stopTest() }
        syncMotionUsage()
        notice = value ? "练习中，请舒适地完成三次动作，不会执行动作" : "测试已结束，头势控制保持暂停"
        overlayChanged?()
    }
    private func updateCalibrationReminder() {
        if !motion.tracking || motion.calibrated {
            calibrationReminderHandled = false
            showCalibrationReminder = false
        } else if motion.calibrating {
            calibrationReminderHandled = true
            showCalibrationReminder = false
        } else if !calibrationReminderHandled {
            calibrationReminderHandled = true
            showCalibrationReminder = true
        }
    }
    func calibrate() {
        showCalibrationReminder = false
        motion.recenter()
    }

    // MARK: Calibration test
    func startTest(_ gesture: Gesture, all: Bool = false) {
        guard store.configuration.isEnabled(gesture), motion.calibrated else { return }
        if !testing { setTesting(true) }
        jointTesting = false; observingEveryday = false
        jointCounts.removeAll(); everydayCount = 0; jointLastTrigger = nil
        testingAll = all; testTarget = gesture
        practice = GesturePractice(gesture: gesture); practiceRecognitions = 0; attemptRecognized = false
        practiceCounts[gesture] = 0; practiceNotes[gesture] = nil; practiceResults[gesture] = nil
        testPassed.remove(gesture); testPeaks[gesture] = 0
        clearTransientFeedback(); router.setMode(.testing)
    }
    func startAllTests() {
        guard let first = store.configuration.enabledGestures.first else { return }
        testPassed.removeAll(); testPeaks.removeAll()
        startTest(first, all: true)
    }
    func startJointTest() {
        guard !store.configuration.enabledGestures.isEmpty, motion.calibrated else { return }
        setTesting(true); stopTest(); jointTesting = true
        jointCounts.removeAll(); everydayCount = 0; jointLastTrigger = nil; testPassed.removeAll()
        notice = "所有已开启头势同时识别。先做指令动作，再观察日常动作；全程不执行动作。"
        router.setMode(.testing); overlayChanged?()
    }
    func setEverydayObservation(_ value: Bool) {
        guard jointTesting else { return }
        observingEveryday = value; everydayCount = 0; jointCounts.removeAll(); jointLastTrigger = nil
        router.setMode(.testing); clearTransientFeedback()
        notice = value ? "自然看屏幕、说话和低头；这里出现的识别可作为误触线索，不会执行动作。" : "做需要使用的头势，检查是否被识别成其他动作；不会执行动作。"
    }
    func stopTest() {
        testTarget = nil; testingAll = false; jointTesting = false; observingEveryday = false; practice = nil
    }
    struct Suggestion: Equatable { var angle: Double; var speed: Double? }
    /// Measured speed of the last test movement, on the same scale as the speed slider.
    func measuredSpeed(for gesture: Gesture) -> Double? {
        practiceResults[gesture]?.medianSpeed ?? (testTarget == gesture ? practice?.medianSpeed : nil)
    }
    /// One suggestion for both angle and speed, offered only when it changes something.
    func suggestion(for gesture: Gesture) -> Suggestion? {
        guard let result = practiceResults[gesture], result.complete, result.consistent, let peak = result.medianPeak else { return nil }
        let tuning = store.configuration.tuning[gesture.rawValue] ?? .defaults(for: gesture)
        guard let angle = ThresholdAdvisor.suggest(peak: peak, tuning: tuning) else { return nil }
        let speed = result.medianSpeed.flatMap { ThresholdAdvisor.suggestSpeed(peak: $0) }
        let changesAngle = abs(angle - tuning.angle) >= 1
        let changesSpeed = speed.map { abs($0 - tuning.speed) >= 5 } ?? false
        return changesAngle || changesSpeed ? Suggestion(angle: angle, speed: speed) : nil
    }
    func applySuggestion(_ gesture: Gesture) {
        guard let value = suggestion(for: gesture) else { return }
        var t = store.configuration.tuning[gesture.rawValue] ?? .defaults(for: gesture)
        t.angle = value.angle; t.neutral = min(t.neutral, value.angle - 1)
        if let speed = value.speed { t.speed = speed }
        store.configuration.tuning[gesture.rawValue] = t
    }

    func shutdown() { pause("应用退出"); motion.stop(); timer?.invalidate() }
    func prepareToQuit() async { pause("正在退出"); keys.release() }

    private func receive(_ sample: MotionSample) {
        guard !selectingApplication else { return }
        if walkingPaused {
            if !suspended {
                suspended = true; router.setMode(.paused); gestureStatus = [:]
                practice?.interrupt(); attemptRecognized = false; clearTransientFeedback(); overlayChanged?()
            }
            return
        }
        if suspended {
            suspended = false; router.setMode(testing ? .testing : enabled ? .active : .paused); overlayChanged?()
        }
        let route = router.update(sample,configuration:store.configuration,testingGesture:testTarget,
                                  feedbackWhenPaused: previewingGestures && motion.tracking && motion.calibrated)
        publishStatus(sample)
        if testing {
            if let route { playSound(for: route.gesture); showPreview(route) }
            updatePractice(sample)
            return
        }
        guard let route else { return }
        // This acknowledges recognition, independent of key delivery. Start before a
        // shortcut can open voice input and reconfigure the Bluetooth audio device.
        playSound(for: route.gesture)
        if !enabled {
            let message = "\(route.gesture.title)已达标，点击“启动头势控制”后才会执行动作"
            notice = message
            publishTrigger(Trigger(gesture:route.gesture,caps:[],outcome:.idlePreview,message:message,
                                   application: route.binding.action == .application ? route.binding.application : nil))
            record(message)
            return
        }
        guard route.executes else {
            if enabled {
                notice = "\(route.gesture.title) 已识别，但未设置动作"
                publishTrigger(Trigger(gesture:route.gesture,caps:[],outcome:.unbound,message:notice))
                record(notice); overlayChanged?()
            }
            return
        }
        // Capture only foreground PID, never text, window identity, input focus or IME state.
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { await self.perform(route,targetPID:targetPID) }
    }
    private func perform(_ route: GestureRouter.Route, targetPID: pid_t?) async {
        guard router.accepts(route), enabled, !selectingApplication, !walkingPaused else { return }
        guard !operation else { skip(route, reason: "上一次动作尚未结束"); return }
        if route.binding.action == .pause {
            publishTrigger(Trigger(gesture:route.gesture,caps:[],outcome:.paused,message:"暂停头势控制"))
            record("已通过\(route.gesture.title)暂停")
            pause("已通过\(route.gesture.title)暂停"); return
        }
        if route.binding.action == .application || route.binding.action == .previousApplication {
            let target = route.binding.action == .application ? route.binding.application : applications.previousApplication(excluding: targetPID)
            guard let target else {
                skip(route, reason: route.binding.action == .application ? "请先选择目标应用" : ApplicationSwitchError.noPrevious.localizedDescription); return
            }
            operation = true; defer { operation = false }
            do {
                try await applications.switchTo(target, isAllowed: { [weak self] in
                    guard let self else { return false }
                    return self.router.accepts(route) && self.enabled && !self.selectingApplication && !self.walkingPaused
                })
                guard router.accepts(route), enabled, !selectingApplication, !walkingPaused else { return }
                notice = "\(route.gesture.title) → 已切换至 \(target.name)"
                publishTrigger(Trigger(gesture: route.gesture, caps: [], outcome: .switched, message: notice, application: target))
                record(notice)
            } catch {
                guard router.accepts(route), enabled, !selectingApplication, !walkingPaused else { return }
                skip(route, reason: error.localizedDescription)
            }
            overlayChanged?(); return
        }
        guard route.binding.action == .shortcut, let shortcut = route.binding.shortcut else { return }
        guard let targetPID else { skip(route, reason: "没有可接收按键的前台应用"); return }
        operation = true; defer { operation = false }
        do {
            try await keys.click(shortcut,targetPID:targetPID)
            guard router.accepts(route), enabled else { return }
            notice = "\(route.gesture.title) → 已点按 \(shortcut.label)"
            publishTrigger(Trigger(gesture:route.gesture,caps:shortcut.caps,outcome:.sent,message:notice))
            record(notice)
        } catch {
            guard router.accepts(route), enabled else { return }
            notice = "\(route.gesture.title)已识别，跳过执行：\(error.localizedDescription)"; record(notice)
            publishTrigger(Trigger(gesture:route.gesture,caps:shortcut.caps,outcome:.skipped,message:error.localizedDescription))
        }
        overlayChanged?()
    }
    private func skip(_ route: GestureRouter.Route, reason: String) {
        notice = reason; record("\(route.gesture.title)：\(reason)")
        publishTrigger(Trigger(gesture: route.gesture, caps: route.binding.action == .shortcut ? route.binding.shortcut?.caps ?? [] : [],
                               outcome: .skipped, message: reason,
                               application: route.binding.action == .application ? route.binding.application : nil))
        overlayChanged?()
    }
    private func publishStatus(_ sample: MotionSample) {
        let next = router.status.mapValues { st in
            GestureStatus(phase: st.phase, progress: (st.progress * 10).rounded() / 10, speed: st.speed.map { ($0 / 5).rounded() * 5 })
        }
        if enabled || testing {
            for g in Gesture.allCases {
                guard let st = next[g] else { continue }
                let old = gestureStatus[g]?.phase
                let tuning = store.configuration.tuning[g.rawValue] ?? .defaults(for: g)
                if st.phase == .below, g.travel(sample) >= max(5, tuning.angle * 0.45) { nearAttempts.insert(g) }
                if st.phase == .fired { nearAttempts.removeAll(); blockedHint = nil; hintDeadline = nil }
                else if old != st.phase {
                    switch st.phase {
                    case .tooSlow: showHint("\(g.shortTitle)：速度不足（\(Int(st.speed ?? 0))/\(Int(tuning.speed))°/s）")
                    case .mixed: showHint("\(g.shortTitle)：其他方向动作太大")
                    case .release where old == .holding: showHint("\(g.shortTitle)：超时，未完成回位")
                    case .below where old == .holding && !g.isSequence: showHint("\(g.shortTitle)：保持时间不足")
                    default: break
                    }
                }
                if st.phase == .below, g.travel(sample) <= min(tuning.neutral, 6), nearAttempts.remove(g) != nil {
                    showHint("\(g.shortTitle)：动作幅度不足")
                }
            }
        }
        if next != gestureStatus { gestureStatus = next }
    }
    private func showHint(_ text: String) {
        blockedHint = text; hintDeadline = Date().addingTimeInterval(4)
        record("未完成头势：\(text)")
    }
    private func publishTrigger(_ trigger: Trigger) {
        lastTrigger = trigger; hudTrigger = trigger; triggerDeadline = Date().addingTimeInterval(4)
        blockedHint = nil; hintDeadline = nil
    }
    func refreshFeedback(now: Date = Date()) {
        if let hintDeadline, now >= hintDeadline { blockedHint = nil; self.hintDeadline = nil }
        if let triggerDeadline, now >= triggerDeadline { hudTrigger = nil; self.triggerDeadline = nil }
    }
    private func clearTransientFeedback() {
        blockedHint = nil; hintDeadline = nil; hudTrigger = nil; triggerDeadline = nil; nearAttempts.removeAll()
    }
    private func showPreview(_ route: GestureRouter.Route) {
        let binding = route.binding
        let caps = binding.action == .shortcut ? (binding.shortcut?.caps ?? []) : []
        let action = binding.action == .application ? (binding.application?.name ?? "尚未选择应用") :
            binding.action == .shortcut ? (binding.shortcut?.label ?? "尚未录入") : binding.action.title
        let message = "\(route.gesture.title) → \(action)（测试，未执行）"
        publishTrigger(Trigger(gesture:route.gesture,caps:caps,outcome:.preview,message:message,
                               application: binding.action == .application ? binding.application : nil))
        record(message)
        if jointTesting {
            jointLastTrigger = lastTrigger
            jointCounts[route.gesture, default: 0] += 1
            if observingEveryday { everydayCount += 1 }
            else { testPassed.insert(route.gesture) }
        } else if testTarget == route.gesture { attemptRecognized = true }
        overlayChanged?()
    }
    private func updatePractice(_ sample: MotionSample) {
        guard let target = testTarget, var current = practice else { return }
        let t = store.configuration.tuning[target.rawValue] ?? .defaults(for: target)
        let attempt = current.update(sample, neutral: t.neutral)
        practice = current
        if current.peak > (testPeaks[target] ?? 0) { testPeaks[target] = current.peak.rounded() }
        guard attempt != nil else {
            if !current.inProgress { attemptRecognized = false }
            return
        }
        if attemptRecognized { practiceRecognitions += 1 }
        attemptRecognized = false
        practiceCounts[target] = current.attempts.count
        guard current.complete else { notice = "\(target.title)：已完成 \(current.attempts.count)/3 次，回正后再做一次"; return }
        practiceResults[target] = current
        testPeaks[target] = current.medianPeak?.rounded()
        if practiceRecognitions >= 3 { testPassed.insert(target) }
        let note = current.consistent ? "已完成三次，幅度相近；可参考建议，采用后重新测试。" : "三次幅度差异较大，请用舒适且相近的幅度重新练习。"
        practiceNotes[target] = note
        notice = "\(target.title)练习完成。\(note)"
        let gestures = store.configuration.enabledGestures
        if testingAll, let i = gestures.firstIndex(of: target), i + 1 < gestures.count {
            startTest(gestures[i + 1], all: true)
        } else { testTarget = nil; testingAll = false; practice = nil; setTesting(false); notice = "三次动作练习已完成，可采用建议或开始联合测试。" }
        overlayChanged?()
    }
    private func pause(_ reason: String) {
        enabled = false; testing = false; suspended = false; stopTest(); router.setMode(.paused); keys.release()
        gestureStatus = [:]; clearTransientFeedback(); syncMotionUsage()
        notice = reason; overlayChanged?()
    }
    private func playSound(for gesture: Gesture) {
        guard store.configuration.sound else { return }
        previewSound(store.configuration.sound(gesture))
    }
    private func prepareSounds() {
        guard store.configuration.sound else { return }
        feedback.prepare(Set(Gesture.allCases.map { store.configuration.sound($0) }))
    }
    /// Preview and recognition share the same player and output-device recovery.
    func previewSound(_ name: String) {
        do { try feedback.play(name) }
        catch { record("提醒音播放失败：\(error.localizedDescription)") }
    }
    private func record(_ message: String) {
        if events.first?.message == message {
            events[0].count += 1; events[0].time = Date(); return
        }
        events.insert(FeedbackEvent(message: message),at:0); if events.count > 24 { events.removeLast(events.count-24) }
    }
}
