import AVFoundation
import CoreAudio

/// Feedback uses ordinary playback on the current output, without opening a microphone.
@MainActor final class SoundFeedback {
    private struct Output: Equatable {
        let id: AudioDeviceID
        let uid: String
        let sampleRate: Float64
    }
    private var output: Output?
    private var players: [String: AVAudioPlayer] = [:]
    private var current: AVAudioPlayer?

    /// Prepare the selected sounds ahead of the gesture, including after settings change.
    func prepare(_ names: Set<String>) {
        for name in names where !name.isEmpty { _ = try? player(for: name) }
    }

    @discardableResult func play(_ name: String) throws -> AVAudioPlayer? {
        guard !name.isEmpty else { return nil }
        guard AlertSound.names.contains(name) else { throw Failure("提醒音名称无效") }
        current?.pause()
        do { return try start(name) }
        catch {
            // A Bluetooth route can disappear during preparation or playback start.
            // Never retry the same cached queue after either failure.
            players.removeAll(); output = nil; current = nil
            return try start(name)
        }
    }

    private func start(_ name: String) throws -> AVAudioPlayer {
        let next = try player(for: name)
        next.currentTime = 0
        guard next.play() else { throw Failure("音频输出启动失败，请检查当前输出设备") }
        current = next
        return next
    }

    private func player(for name: String) throws -> AVAudioPlayer {
        guard AlertSound.names.contains(name) else { throw Failure("提醒音名称无效") }
        let route = try Self.defaultOutput()
        // The same AirPods UID can reappear with a new object ID or sample rate when
        // voice input changes its Bluetooth mode. A cached NSSound queue misses this.
        if route != output {
            current?.pause(); current = nil; players.removeAll(); output = route
        }
        if let player = players[name] { return player }
        let url = URL(fileURLWithPath: "/System/Library/Sounds").appendingPathComponent(name).appendingPathExtension("aiff")
        let player = try AVAudioPlayer(contentsOf: url)
        player.currentDevice = route.uid
        player.volume = 1
        guard player.prepareToPlay() else { throw Failure("无法准备提醒音播放器") }
        players[name] = player
        return player
    }

    private static func defaultOutput() throws -> Output {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw Failure("没有可用的音频输出设备") }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let uid else { throw Failure("无法读取音频输出设备") }
        let identifier = uid.takeRetainedValue() as String
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        var rate: Float64 = 0
        size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else {
            throw Failure("音频输出正在切换，请重试")
        }
        return Output(id: device, uid: identifier, sampleRate: rate)
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
