import AppKit
import Combine
import CoreMotion

/// Only leaf views that draw the live pose observe this.
@MainActor final class PoseFeed: ObservableObject {
    @Published var pose = MotionSample(time: 0)
}

@MainActor final class MotionService: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published private(set) var link: HeadphoneLink = .idle
    @Published private(set) var tracking = false
    @Published private(set) var calibrated = false
    @Published private(set) var calibrating = false
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var calibrationHint = "正对屏幕，保持自然坐姿"
    /// Live pose at UI rate, kept out of objectWillChange so whole pages are not re-rendered 20×/s.
    let poseFeed = PoseFeed()
    var pose: MotionSample { poseFeed.pose }
    @Published private(set) var sensor = "未知"
    @Published private(set) var authorization = CMHeadphoneMotionManager.authorizationStatus()
    /// The headphones report walking or running; used to suspend gestures, never shown as data.
    @Published private(set) var walking = false
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
    var onCalibrationResult: ((String) -> Void)?
    private var manager = CMHeadphoneMotionManager()
    private let activityManager = CMHeadphoneActivityManager()
    private var session = UUID()
    private var activitySession = UUID()
    private var activityListening = false
    private var reference: CMAttitude?
    private var current: CMAttitude?
    private var lastReceived: Date?
    private var lastUI: Double?
    private var started = false
    private var timer: Timer?
    /// Keeps App Nap from throttling sample delivery while the app sits in the background,
    /// which is exactly when gestures are used for real.
    private var activity: NSObjectProtocol?
    private var usage = MotionUsage()
    private var pauseWhileWalking = true
    private var stablePose = StablePoseWindow()
    private var calibrationStarted: Double?
    private var suspensionReasons: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    override init() {
        super.init(); manager.delegate = self
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "sleep"), (NSWorkspace.screensDidSleepNotification, "display"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend(reason: reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "sleep"), (NSWorkspace.screensDidWakeNotification, "display"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume(reason: reason) }
            })
        }
        // Distributed lock notifications supplement workspace sleep/session notifications.
        let distributed = DistributedNotificationCenter.default()
        lockObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(reason: "lock") }
        })
        lockObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume(reason: "lock") }
        })
        // Always-on watch: permission changes and data gaps must surface even before the first start().
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    var authorized: Bool { authorization == .authorized }
    var status: String { link.title }

    func start() {
        guard suspensionReasons.isEmpty else { return }
        guard manager.isDeviceMotionAvailable else { stop(); link = .unavailable; return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        authorization = auth
        guard auth != .denied && auth != .restricted else { stop(); link = .permissionDenied; return }
        if tracking || calibrated { onInvalidation?("耳机采集已重新启动，请重新校准") }
        stop()
        started = true; link = .waiting; manager.startConnectionStatusUpdates()
        let token = session
        startActivityServices()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, self.started, self.session == token else { return }
            if let error { self.invalidate("耳机数据错误：\(error.localizedDescription)"); return }
            guard let motion else { return }
            self.receive(motion)
        }
    }
    /// Requests Motion & Fitness: the system prompt only appears when updates start.
    func requestPermission() {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") { NSWorkspace.shared.open(url) }
        default: start()
        }
    }
    func reconnect() {
        onInvalidation?("耳机正在重新连接，本轮已退出")
        stop(); manager.delegate = nil; manager = CMHeadphoneMotionManager(); manager.delegate = self; start()
    }
    func stop() {
        session = UUID()
        manager.stopDeviceMotionUpdates(); manager.stopConnectionStatusUpdates(); started = false
        stopActivityServices()
        releaseRealtimeActivity()
        calibrating = false; calibrationProgress = 0; stablePose.reset(); calibrationStarted = nil
        lastReceived = nil; current = nil; reference = nil; tracking = false; calibrated = false; link = .idle
        lastUI = nil; sensor = "未知"
    }
    func setUsage(active: Bool, preview: Bool, pauseWhileWalking: Bool) {
        usage.active = active; usage.preview = preview
        self.pauseWhileWalking = pauseWhileWalking
        if active { startActivityServices() } else { stopActivityServices() }
        refreshResources()
    }
    private func refreshResources() {
        usage.tracking = tracking; usage.calibrating = calibrating
        usage.walking = walking && pauseWhileWalking; usage.suspended = !suspensionReasons.isEmpty
        if usage.needsRealtime {
            if activity == nil {
                // Protect delivery from App Nap while allowing the Mac to sleep normally.
                activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "实时识别耳机头势")
            }
        } else { releaseRealtimeActivity() }
    }
    private func releaseRealtimeActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func recenter() {
        guard tracking, current != nil else { return }
        onInvalidation?("正在校准，请正对屏幕静止一秒")
        reference = nil; calibrated = false; calibrating = true; calibrationProgress = 0
        calibrationStarted = nil; stablePose.reset()
        calibrationHint = "正对屏幕，保持静止一秒"
        refreshResources()
    }
    func cancelCalibration(hint: String = "校准已取消，请准备好后重试") {
        guard calibrating else { return }
        calibrating = false; calibrationProgress = 0; stablePose.reset(); calibrationStarted = nil
        calibrationHint = hint; refreshResources(); onCalibrationResult?(hint)
    }
    func suspend(reason: String) {
        let first = suspensionReasons.isEmpty
        suspensionReasons.insert(reason)
        guard first else { return }
        onInvalidation?("屏幕休眠、锁屏或会话离开，头势控制已暂停")
        stop(); link = .interrupted("恢复使用后请重新校准并手动开启控制")
    }
    func resume(reason: String) {
        guard suspensionReasons.remove(reason) != nil, suspensionReasons.isEmpty else { return }
        if authorized { start() }
    }
    private func poll() {
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        if auth != authorization {
            authorization = auth
            if auth == .authorized && started { start(); return }
            if auth == .denied || auth == .restricted {
                stopActivityServices()
                invalidate("运动与健身权限不可用"); link = .permissionDenied; return
            }
        }
        if let last = lastReceived, Date().timeIntervalSince(last) > 1.5, tracking { invalidate("耳机数据中断，请重新戴好耳机并校准") }
    }
    private func receive(_ motion: CMDeviceMotion) {
        guard motion.timestamp.isFinite, motion.attitude.yaw.isFinite,
              motion.attitude.pitch.isFinite, motion.attitude.roll.isFinite else {
            invalidate("耳机返回的运动数据无效，请重新连接"); return
        }
        lastReceived = Date(); current = motion.attitude.copy() as? CMAttitude
        let nextSensor: String
        switch motion.sensorLocation { case .headphoneLeft: nextSensor = "左耳"; case .headphoneRight: nextSensor = "右耳"; default: nextSensor = "未知" }
        if nextSensor != sensor {
            if sensor != "未知" {
                calibrated = false; calibrating = false; calibrationProgress = 0
                stablePose.reset(); calibrationStarted = nil; reference = nil; lastUI = nil; releaseRealtimeActivity()
                onInvalidation?("数据来源耳机改变，请重新校准")
            }
            sensor = nextSensor
        }
        if !tracking { tracking = true; if usage.active { startActivityServices(restart: true) }; refreshResources() }
        if link != .tracking { link = .tracking }
        guard usage.needsPose else { return }
        guard let relative = motion.attitude.copy() as? CMAttitude else { return }
        if let reference { relative.multiply(byInverseOf: reference) }
        let degrees = 180.0 / Double.pi
        // Same headphone coordinate convention as HeadOrbit: right yaw positive, down pitch negative.
        // Body-frame gyro: x ≈ pitch, y ≈ roll, z ≈ yaw near the calibrated pose. The speed gate
        // compares magnitudes per axis, so only the axis pairing matters, not the sign.
        let r = motion.rotationRate
        let rate = AxisRates(yaw: -r.z * degrees, pitch: r.x * degrees, roll: r.y * degrees)
        let sample = MotionSample(time: motion.timestamp, yaw: -relative.yaw * degrees, pitch: relative.pitch * degrees,
                                  roll: relative.roll * degrees, rate: rate.finite ? rate : nil)
        if calibrating {
            if calibrationStarted == nil { calibrationStarted = motion.timestamp }
            let raw = MotionSample(time: motion.timestamp, yaw: -motion.attitude.yaw * degrees, pitch: motion.attitude.pitch * degrees, roll: motion.attitude.roll * degrees, rate: rate.finite ? rate : nil)
            if stablePose.update(raw) {
                reference = motion.attitude.copy() as? CMAttitude
                calibrated = reference != nil; calibrating = false; calibrationProgress = calibrated ? 1 : 0
                calibrationHint = calibrated ? "校准完成，可开始三次动作练习" : "校准失败，请重试"
                poseFeed.pose = MotionSample(time: motion.timestamp); refreshResources()
                onCalibrationResult?(calibrationHint); return
            }
            let progress = (stablePose.progress * 20).rounded() / 20
            if progress != calibrationProgress { calibrationProgress = progress }
            if motion.timestamp - (calibrationStarted ?? motion.timestamp) > 10 {
                cancelCalibration(hint: "姿态尚未稳定，请坐稳后重新校准")
            }
        }
        if lastUI == nil || sample.time < lastUI! || sample.time - lastUI! >= 0.05 {
            poseFeed.pose = sample; lastUI = sample.time
        }
        if calibrated && (usage.active || usage.preview) { onSample?(sample) }
    }

    private func startActivityServices(restart: Bool = false) {
        guard started, usage.active, authorized, activityManager.isActivityAvailable else { return }
        if restart { stopActivityServices() }
        guard !activityListening else { return }
        activityListening = true
        let token = activitySession
        activityManager.startActivityUpdates(to: .main) { [weak self] reading, error in
            guard let self, self.started, self.activitySession == token else { return }
            // An error or missing reading must never leave gestures suspended.
            let moving = error == nil && (reading?.walking == true || reading?.running == true)
            if moving != self.walking { self.walking = moving; self.refreshResources() }
        }
    }

    private func stopActivityServices() {
        activitySession = UUID()
        activityManager.stopActivityUpdates()
        activityListening = false; walking = false
    }
    private func invalidate(_ reason: String) {
        tracking = false; calibrated = false; calibrating = false; calibrationProgress = 0
        stablePose.reset(); calibrationStarted = nil; reference = nil; current = nil; lastUI = nil
        releaseRealtimeActivity(); stopActivityServices(); link = .interrupted(reason); onInvalidation?(reason)
    }
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.started, manager === self.manager, !self.tracking else { return }
            self.link = .waiting
        }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.started, manager === self.manager else { return }
            self.walking = false
            self.invalidate("耳机已断开，戴回后需重新校准")
        }
    }
}
