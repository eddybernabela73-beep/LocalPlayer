import Foundation
import AVFoundation
import MediaPlayer

// Separate NSObject subclass to handle AVAudioPlayerDelegate (avoids @Observable + NSObject conflicts)
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag { onFinish?() }
    }
}

@Observable
final class AudioPlayerService {

    // MARK: - Observable state
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentTrack: Track?

    // MARK: - Callbacks wired by PlayerViewModel
    var onTrackFinished: (() -> Void)?
    var onNextRequested: (() -> Void)?
    var onPreviousRequested: (() -> Void)?

    // MARK: - Private
    private var player: AVAudioPlayer?
    private let delegate = PlayerDelegate()
    private var progressTimer: Timer?

    init() {
        setupAudioSession()
        setupRemoteCommands()
        delegate.onFinish = { [weak self] in
            self?.isPlaying = false
            self?.onTrackFinished?()
        }
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[AudioPlayerService] Session error: \(error)")
        }
    }

    // MARK: - Playback

    func play(track: Track) {
        stopPlayer()

        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.delegate = delegate
            player?.prepareToPlay()
            player?.play()

            currentTrack = track
            duration = player?.duration ?? 0
            currentTime = 0
            isPlaying = true

            startTimer()
            updateNowPlaying()
        } catch {
            print("[AudioPlayerService] Play error for '\(track.title)': \(error)")
        }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }

    func resume() {
        guard !isPlaying, player != nil else { return }
        player?.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
        updateNowPlaying()
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
        stopTimer()
        isPlaying = false
    }

    // MARK: - Progress Timer

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.currentTime = self?.player?.currentTime ?? 0
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Now Playing Info (lock screen / Control Center)

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let artwork = track.artwork {
            let size = CGSize(width: 500, height: 500)
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: size) { _ in artwork }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Command Center (AirPods, lock screen controls)

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextRequested?()
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousRequested?()
            return .success
        }
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: e.positionTime)
            }
            return .success
        }
    }
}
