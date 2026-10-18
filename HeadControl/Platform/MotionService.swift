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
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
    private var manager = CMHeadphoneMotionManager()
    private var reference: CMAttitude?
    private var current: CMAttitude?
    private var lastReceived: Date?
    private var lastUI: Double = 0
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

    func start() {
        guard manager.isDeviceMotionAvailable else { link = .unavailable; return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        authorization = auth
        guard auth != .denied && auth != .restricted else { link = .permissionDenied; return }
        if tracking || calibrated { onInvalidation?("耳机采集已重新启动，请重新校准") }
        stop()
        started = true; link = .waiting; manager.startConnectionStatusUpdates()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
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
        manager.stopDeviceMotionUpdates(); manager.stopConnectionStatusUpdates(); started = false
        lastReceived = nil; current = nil; reference = nil; tracking = false; calibrated = false; link = .idle
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
            if auth == .denied || auth == .restricted { invalidate("运动与健身权限不可用"); link = .permissionDenied; return }
        }
        if let last = lastReceived, Date().timeIntervalSince(last) > 1.5, tracking { invalidate("耳机数据中断，请重新戴好耳机并校准") }
    }
    private func receive(_ motion: CMDeviceMotion) {
        lastReceived = Date(); current = motion.attitude.copy() as? CMAttitude
        guard let relative = motion.attitude.copy() as? CMAttitude else { return }
        if let reference { relative.multiply(byInverseOf: reference) }
        let degrees = 180.0 / Double.pi
        // Same headphone coordinate convention as HeadOrbit: right yaw positive, down pitch negative.
        let sample = MotionSample(time: motion.timestamp, yaw: -relative.yaw * degrees, pitch: relative.pitch * degrees, roll: relative.roll * degrees)
        if !tracking { tracking = true }
        if link != .tracking { link = .tracking }
        let nextSensor: String
        switch motion.sensorLocation { case .headphoneLeft: nextSensor = "左耳"; case .headphoneRight: nextSensor = "右耳"; default: nextSensor = "未知" }
        if nextSensor != sensor {
            if sensor != "未知" { calibrated = false; reference = nil; onInvalidation?("数据来源耳机改变，请重新校准") }
            sensor = nextSensor
        }
        if sample.time - lastUI >= 0.05 { pose = sample; lastUI = sample.time }
        if calibrated { onSample?(sample) }
    }
    private func invalidate(_ reason: String) {
        tracking = false; calibrated = false; reference = nil; current = nil; link = .interrupted(reason); onInvalidation?(reason)
    }
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, !self.tracking else { return }
            self.link = .waiting
        }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.invalidate("耳机已断开，戴回后需重新校准") }
    }
}
