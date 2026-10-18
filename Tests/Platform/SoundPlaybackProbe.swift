import AVFoundation

@main struct SoundPlaybackProbe {
    @MainActor static func main() throws {
        let feedback = SoundFeedback()
        let names = Set(AlertSound.names)
        feedback.prepare(names)
        for name in AlertSound.names {
            let player = try feedback.play(name)
            guard let player, player.isPlaying, player.currentDevice != nil else {
                print("FAIL: \(name) did not start on an output device"); exit(1)
            }
        }
        let first = try feedback.play("Submarine")!
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard first.isPlaying, first.currentTime > 0.05 else {
            print("FAIL: playback did not advance"); exit(1)
        }
        let repeated = try feedback.play("Submarine")!
        guard repeated.currentTime < 0.05, repeated.isPlaying else {
            print("FAIL: repeated feedback did not restart"); exit(1)
        }
        guard try feedback.play("") == nil else { print("FAIL: silent selection played"); exit(1) }
        do {
            try feedback.play("../invalid")
            print("FAIL: invalid name accepted"); exit(1)
        } catch {}
        print("PASS: all \(names.count) sounds started, playback advanced on current output; repeat, silence and invalid-name checks passed")
    }
}
