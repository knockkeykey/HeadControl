import Foundation

// Exercise the production recovery path without disconnecting the user's headphones.
@MainActor final class AVAudioPlayer {
    static var created = 0, attempts = 0, failures = 0, prepareFailures = 0
    var currentDevice: String?, volume: Float = 1, currentTime: Double = 0
    init(contentsOf url: URL) throws { Self.created += 1 }
    func prepareToPlay() -> Bool {
        if Self.prepareFailures > 0 { Self.prepareFailures -= 1; return false }
        return true
    }
    func pause() {}
    func play() -> Bool {
        Self.attempts += 1
        if Self.failures > 0 { Self.failures -= 1; return false }
        return true
    }
    static func reset() { created = 0; attempts = 0; failures = 0; prepareFailures = 0 }
}
@main struct SoundRecoveryProbe {
    @MainActor static func main() throws {
        AVAudioPlayer.reset(); AVAudioPlayer.failures = 1
        let feedback = SoundFeedback()
        feedback.prepare(["Submarine"])
        _ = try feedback.play("Submarine")
        guard AVAudioPlayer.created == 2, AVAudioPlayer.attempts == 2 else {
            print("FAIL: cached failed player was not rebuilt"); exit(1)
        }
        AVAudioPlayer.reset(); AVAudioPlayer.failures = 10
        do {
            _ = try SoundFeedback().play("Glass")
            print("FAIL: permanent output failure was ignored"); exit(1)
        } catch {}
        guard AVAudioPlayer.attempts == 2 else { print("FAIL: recovery was not bounded"); exit(1) }
        AVAudioPlayer.reset(); AVAudioPlayer.prepareFailures = 1
        _ = try SoundFeedback().play("Pop")
        guard AVAudioPlayer.created == 2, AVAudioPlayer.attempts == 1 else {
            print("FAIL: failed preparation was not recovered"); exit(1)
        }
        print("PASS: failed cached playback rebuilt, preparation failure recovered, permanent failure reported after one retry")
    }
}
