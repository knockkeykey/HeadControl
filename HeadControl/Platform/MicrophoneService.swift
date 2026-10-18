import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Combine

/// An opt-in, in-memory input meter. Never creates an audio file or a speech recognizer.
@MainActor final class MicrophoneService: ObservableObject {
    enum State: Equatable {
        case off, requesting, waiting, active, denied, failed(String)
        var title: String {
            switch self {
            case .off: "未开启"
            case .requesting: "等待麦克风授权"
            case .waiting: "等待音频输入"
            case .active: "正在读取电平"
            case .denied: "麦克风权限未授予"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var state: State = .off
    @Published private(set) var level: AudioSignalLevel?
    @Published private(set) var inputName = "系统默认输入"
    @Published private(set) var sampleRate: Double?
    @Published private(set) var channelCount: Int?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var session = UUID()
    private var configurationObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private var lastBufferAt: Date?
    var isStarted: Bool { state == .requesting || state == .waiting || state == .active }

    func refreshInputStatus() {
        refreshInputName()
        if state == .denied && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { state = .off }
    }

    func refreshInputName() {
        guard engine == nil else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr {
            inputName = Self.deviceName(device)
        }
    }

    func start() {
        guard !isStarted else { return }
        stop(); state = .requesting
        let token = session
        Task { @MainActor [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
            default: allowed = false
            }
            guard let self, self.session == token else { return }
            guard allowed else { self.state = .denied; return }
            self.startEngine(token: token)
        }
    }

    func stop() {
        session = UUID(); watchdog?.invalidate(); watchdog = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        engine = nil; tapInstalled = false; lastBufferAt = nil
        level = nil; sampleRate = nil; channelCount = nil; state = .off
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
    }

    private func fail(_ message: String) { stop(); state = .failed(message) }

    private func startEngine(token: UUID) {
        let nextEngine = AVAudioEngine()
        let input = nextEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            fail("没有可用的输入设备，请检查系统声音设置"); return
        }
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if let unit = input.audioUnit,
           AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size) == noErr {
            inputName = Self.deviceName(device)
        } else { refreshInputName() }
        engine = nextEngine; state = .waiting
        var framesSinceUpdate = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            let frames = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
            guard frames > 0, channels > 0, let samples = buffer.floatChannelData else { return }
            framesSinceUpdate += frames
            guard Double(framesSinceUpdate) >= buffer.format.sampleRate / 10 else { return }
            framesSinceUpdate = 0
            var squares = 0.0, peak = 0.0
            let interleaved = buffer.format.isInterleaved
            for channel in 0..<channels {
                let data = samples[interleaved ? 0 : channel]
                for frame in 0..<frames {
                    let value = Double(data[frame * buffer.stride + (interleaved ? channel : 0)])
                    squares += value * value; peak = max(peak, abs(value))
                }
            }
            guard let reading = AudioSignalLevel(sumOfSquares: squares, sampleCount: frames * channels, peak: peak) else { return }
            let rate = buffer.format.sampleRate
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.level = reading; self.sampleRate = rate; self.channelCount = channels
                self.lastBufferAt = Date(); self.state = .active
            }
        }
        tapInstalled = true
        do { try nextEngine.start() }
        catch { fail("无法启动音频输入：\(error.localizedDescription)"); return }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nextEngine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.fail("音频输入已改变，请重新开启电平"); self.refreshInputName()
            }
        }
        let startedAt = Date()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                    self.stop(); self.state = .denied
                } else if Date().timeIntervalSince(self.lastBufferAt ?? startedAt) > 3 {
                    self.fail("音频输入已中断，请检查输入设备后重试")
                }
            }
        }
    }

    private static func deviceName(_ device: AudioDeviceID) -> String {
        guard device != kAudioObjectUnknown else { return "没有可用输入设备" }
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "系统默认输入" }
        return value as String
    }
}
