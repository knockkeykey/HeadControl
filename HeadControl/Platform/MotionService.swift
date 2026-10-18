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
    @Published private(set) var telemetry: HeadphoneTelemetry?
    @Published private(set) var activityState: PublicDataState = .stopped
    @Published private(set) var activity: HeadphoneActivityReading?
    @Published private(set) var activityConnection = "未监听"
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
    private var manager = CMHeadphoneMotionManager()
    private let activityManager = CMHeadphoneActivityManager()
    private var cadence = MotionCadence()
    private var session = UUID()
    private var activitySession = UUID()
    private var activityListening = false
    private var activityStatusListening = false
    private var reference: CMAttitude?
    private var current: CMAttitude?
    private var lastReceived: Date?
    private var lastUI: Double?
    private var lastTelemetryUI: Double?
    private var started = false
    private var timer: Timer?
    override init() {
        super.init(); manager.delegate = self
        // Always-on watch: permission changes and data gaps must surface even before the first start().
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    var authorized: Bool { authorization == .authorized }
    var status: String { link.title }
    var deviceMotionActive: Bool { manager.isDeviceMotionActive }
    var connectionUpdatesActive: Bool { manager.isConnectionStatusActive }

    func start() {
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
        lastReceived = nil; current = nil; reference = nil; tracking = false; calibrated = false; link = .idle
        clearTelemetry(); sensor = "未知"
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
                stopActivityServices(); activityState = .denied
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
                calibrated = false; reference = nil; clearTelemetry()
                onInvalidation?("数据来源耳机改变，请重新校准")
            }
            sensor = nextSensor
        }
        guard let relative = motion.attitude.copy() as? CMAttitude else { return }
        if let reference { relative.multiply(byInverseOf: reference) }
        let degrees = 180.0 / Double.pi
        // Same headphone coordinate convention as HeadOrbit: right yaw positive, down pitch negative.
        let sample = MotionSample(time: motion.timestamp, yaw: -relative.yaw * degrees, pitch: relative.pitch * degrees, roll: relative.roll * degrees)
        if !tracking { tracking = true; startActivityServices(restart: true) }
        if link != .tracking { link = .tracking }
        cadence.record(sample.time)
        if lastUI == nil || sample.time < lastUI! || sample.time - lastUI! >= 0.05 {
            pose = sample; lastUI = sample.time
        }
        // Numeric diagnostics update at 10 Hz. Gesture recognition still receives every sample.
        if lastTelemetryUI == nil || sample.time < lastTelemetryUI! || sample.time - lastTelemetryUI! >= 0.1 {
            telemetry = HeadphoneTelemetry(motion: motion, cadence: cadence)
            lastTelemetryUI = sample.time
        }
        if calibrated { onSample?(sample) }
    }
    private func clearTelemetry() {
        telemetry = nil; cadence.reset(); lastUI = nil; lastTelemetryUI = nil
    }

    private func startActivityServices(restart: Bool = false) {
        guard started, authorized else { return }
        if restart { stopActivityServices() }
        let token = activitySession
        if activityManager.isActivityAvailable {
            if !activityListening {
                activityListening = true
                activityState = .waiting
                activityManager.startActivityUpdates(to: .main) { [weak self] reading, error in
                    guard let self, self.started, self.activitySession == token else { return }
                    if let error { self.activity = nil; self.activityState = .failed(error.localizedDescription); return }
                    guard let reading else { return }
                    self.activity = HeadphoneActivityReading(reading); self.activityState = .receiving
                }
            }
        } else { activity = nil; activityState = .unsupported }
        if activityManager.isStatusAvailable {
            if !activityStatusListening {
                activityStatusListening = true
                activityConnection = "等待连接事件"
                activityManager.startStatusUpdates(to: .main) { [weak self] status, error in
                    guard let self, self.started, self.activitySession == token else { return }
                    if let error { self.activityConnection = error.localizedDescription; return }
                    switch status {
                    case .connected: self.activityConnection = "已连接"
                    case .disconnected:
                        self.activityConnection = "已断开"; self.activity = nil
                        if self.activityState == .receiving { self.activityState = .waiting }
                    @unknown default: self.activityConnection = "未知状态"
                    }
                }
            }
        } else { activityConnection = "当前设备不支持" }
    }

    private func stopActivityServices() {
        activitySession = UUID()
        activityManager.stopActivityUpdates(); activityManager.stopStatusUpdates()
        activityListening = false; activityStatusListening = false
        activity = nil; activityState = .stopped; activityConnection = "未监听"
    }
    private func invalidate(_ reason: String) {
        tracking = false; calibrated = false; reference = nil; current = nil; link = .interrupted(reason); onInvalidation?(reason)
        clearTelemetry()
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
            self.activity = nil
            if self.activityState == .receiving { self.activityState = .waiting }
            self.invalidate("耳机已断开，戴回后需重新校准")
        }
    }
}
