import AppKit
import Combine
import CoreMotion

@MainActor final class MotionService: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published private(set) var link: HeadphoneLink = .idle
    @Published private(set) var tracking = false
    @Published private(set) var calibrated = false
    @Published private(set) var pose = MotionSample(time: 0)
    @Published private(set) var sensor = "未知"
    @Published private(set) var authorization = CMHeadphoneMotionManager.authorizationStatus()
    /// The headphones report walking or running; used to suspend gestures, never shown as data.
    @Published private(set) var walking = false
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
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
    override init() {
        super.init(); manager.delegate = self
        // Always-on watch: permission changes and data gaps must surface even before the first start().
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    var authorized: Bool { authorization == .authorized }
    var status: String { link.title }

    func start() {
        guard manager.isDeviceMotionAvailable else { stop(); link = .unavailable; return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        authorization = auth
        guard auth != .denied && auth != .restricted else { stop(); link = .permissionDenied; return }
        if tracking || calibrated { onInvalidation?("耳机采集已重新启动，请重新校准") }
        stop()
        started = true; link = .waiting; manager.startConnectionStatusUpdates()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                                                         reason: "实时识别耳机头势")
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
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        lastReceived = nil; current = nil; reference = nil; tracking = false; calibrated = false; link = .idle
        lastUI = nil; sensor = "未知"
    }
    func recenter() {
        guard tracking, let copy = current?.copy() as? CMAttitude else { return }
        onInvalidation?("已重新校准，本轮已退出")
        reference = copy; calibrated = true; pose = MotionSample(time: ProcessInfo.processInfo.systemUptime)
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
                calibrated = false; reference = nil; lastUI = nil
                onInvalidation?("数据来源耳机改变，请重新校准")
            }
            sensor = nextSensor
        }
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
        if !tracking { tracking = true; startActivityServices(restart: true) }
        if link != .tracking { link = .tracking }
        if lastUI == nil || sample.time < lastUI! || sample.time - lastUI! >= 0.05 {
            pose = sample; lastUI = sample.time
        }
        if calibrated { onSample?(sample) }
    }

    private func startActivityServices(restart: Bool = false) {
        guard started, authorized, activityManager.isActivityAvailable else { return }
        if restart { stopActivityServices() }
        guard !activityListening else { return }
        activityListening = true
        let token = activitySession
        activityManager.startActivityUpdates(to: .main) { [weak self] reading, error in
            guard let self, self.started, self.activitySession == token else { return }
            // An error or missing reading must never leave gestures suspended.
            let moving = error == nil && (reading?.walking == true || reading?.running == true)
            if moving != self.walking { self.walking = moving }
        }
    }

    private func stopActivityServices() {
        activitySession = UUID()
        activityManager.stopActivityUpdates()
        activityListening = false; walking = false
    }
    private func invalidate(_ reason: String) {
        tracking = false; calibrated = false; reference = nil; current = nil; lastUI = nil; link = .interrupted(reason); onInvalidation?(reason)
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
