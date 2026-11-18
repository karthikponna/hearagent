import AVFoundation

/// Plays the voiced lines returned by the Hear Agent backend, one at a time.
@MainActor
final class AudioPlayer: NSObject {
    private var player: AVAudioPlayer?
    /// Called when a line finishes, is skipped, or cannot be played.
    var onFinished: (() -> Void)?
    var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(_ audio: Data) {
        do {
            let next = try AVAudioPlayer(data: audio)
            next.delegate = self
            next.volume = volume
            next.prepareToPlay()
            player = next
            if !next.play() { finish() }
        } catch {
            AppModel.log.error("could not play audio: \(error.localizedDescription, privacy: .public)")
            finish()
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        finish()
    }

    private func finish() {
        player = nil
        onFinished?()
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish() }
    }
}
