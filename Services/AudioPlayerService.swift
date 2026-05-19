import Foundation
import AVFoundation
import MediaPlayer

@Observable
final class AudioPlayerService {

    // MARK: - Observable state
    var isPlaying    = false
    var currentTime: TimeInterval = 0
    var duration:    TimeInterval = 0
    var currentTrack: Track?

    var playbackRate: Float = 1.0 {
        didSet { timePitchNode.rate = playbackRate }
    }

    var isCrossfadeEnabled  = false
    var crossfadeDuration: TimeInterval = 3.0

    // 5-band EQ
    var eqGains: [Float] = [0, 0, 0, 0, 0] {
        didSet {
            for (i, g) in eqGains.enumerated() where i < eqNode.bands.count {
                eqNode.bands[i].gain = g
            }
        }
    }
    static let eqFrequencies: [Float]   = [60, 250, 1000, 4000, 16000]
    static let eqBandLabels             = ["Sub", "Bass", "Mid", "Hi-Mid", "Treble"]

    // MARK: - Callbacks
    var onTrackFinished:     (() -> Void)?
    var onNextRequested:     (() -> Void)?
    var onPreviousRequested: (() -> Void)?
    var onCrossfadeNeeded:   (() -> Void)?

    // MARK: - Engine — simple linear graph
    //   playerNode → eqNode → timePitchNode → mainMixerNode → outputNode
    private let engine        = AVAudioEngine()
    private let playerNode    = AVAudioPlayerNode()
    private let eqNode        = AVAudioUnitEQ(numberOfBands: 5)
    private let timePitchNode = AVAudioUnitTimePitch()

    private var currentAudioFile: AVAudioFile?
    private var seekTime: TimeInterval = 0

    // Generation counter — incremented on every play/seek so stale completion
    // handlers (fired by playerNode.stop()) are silently ignored.
    private var playbackGeneration = 0

    private var progressTimer:     Timer?
    private var crossfadeTriggered = false
    private var notificationTokens: [Any] = []

    // MARK: - Init / Deinit

    init() {
        setupEngine()
        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        engine.stop()
    }

    // MARK: - Engine

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(timePitchNode)

        // Linear chain — simplest possible graph for reliable background audio
        engine.connect(playerNode,    to: eqNode,              format: nil)
        engine.connect(eqNode,        to: timePitchNode,       format: nil)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: nil)

        // Configure EQ bands
        let freqs: [Float] = [60, 250, 1000, 4000, 16000]
        for (i, f) in freqs.enumerated() {
            eqNode.bands[i].filterType = .parametric
            eqNode.bands[i].frequency  = f
            eqNode.bands[i].bandwidth  = 1.0
            eqNode.bands[i].gain       = 0
            eqNode.bands[i].bypass     = false
        }

        timePitchNode.rate    = 1.0
        timePitchNode.pitch   = 0
        timePitchNode.overlap = 4.0   // lower CPU than 8

        startEngine()
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do { try engine.start() } catch {
            print("[AudioPlayerService] Engine start error: \(error)")
        }
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioPlayerService] Session error: \(error)")
        }
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioPlayerService] Activate session error: \(error)")
        }
        startEngine()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let session = AVAudioSession.sharedInstance()

        let t1 = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] n in self?.handleInterruption(n) }

        let t2 = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] n in self?.handleRouteChange(n) }

        // Restart engine if hardware config changes (Bluetooth connect/disconnect etc.)
        let t3 = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.startEngine()
            if self.isPlaying { self.playerNode.play() }
        }

        notificationTokens = [t1, t2, t3]
    }

    private func handleInterruption(_ note: Notification) {
        guard let val  = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: val) else { return }
        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            activateSession()
            let opts = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if opts.contains(.shouldResume) { resume() }
        @unknown default: break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let val    = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: val) else { return }
        if reason == .oldDeviceUnavailable { pause() }   // headphones unplugged
    }

    // MARK: - Playback

    func play(track: Track) {
        playerNode.stop()
        playbackGeneration += 1
        let gen            = playbackGeneration
        currentTime        = 0
        seekTime           = 0
        crossfadeTriggered = false

        do {
            let file = try AVAudioFile(forReading: track.url)
            currentAudioFile = file
            let sr = file.processingFormat.sampleRate
            duration     = sr > 0 ? Double(file.length) / sr : 0
            currentTrack = track

            activateSession()
            timePitchNode.rate = playbackRate

            playerNode.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    // Ignore if a newer play/seek has already started
                    guard let self, self.playbackGeneration == gen else { return }
                    self.isPlaying = false
                    self.stopTimer()
                    self.onTrackFinished?()
                }
            }

            playerNode.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        } catch {
            print("[AudioPlayerService] Play error: \(error)")
        }
    }

    /// Crossfade: fade out current track volume, then start next track
    func startCrossfadeTo(track: Track) {
        let fadeSteps    = 20
        let stepInterval = crossfadeDuration / Double(fadeSteps)
        var step         = 0

        // Fade out volume
        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            step += 1
            playerNode.volume = max(0, 1.0 - Float(step) / Float(fadeSteps))
            if step >= fadeSteps {
                t.invalidate()
                self.playerNode.volume = 1.0
                self.play(track: track)
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        playerNode.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }

    func resume() {
        guard !isPlaying, currentAudioFile != nil else { return }
        activateSession()
        playerNode.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func seek(to time: TimeInterval) {
        guard let file = currentAudioFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()
        playbackGeneration += 1
        let gen = playbackGeneration

        let sr          = file.processingFormat.sampleRate
        let startFrame  = AVAudioFramePosition(time * sr)
        let totalFrames = file.length
        guard startFrame < totalFrames else { return }

        let remaining = AVAudioFrameCount(totalFrames - startFrame)
        seekTime    = time
        currentTime = time
        crossfadeTriggered = false

        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remaining, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == gen else { return }
                self.isPlaying = false
                self.stopTimer()
                self.onTrackFinished?()
            }
        }

        if wasPlaying {
            activateSession()
            playerNode.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlaying()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, isPlaying else { return }

            // Get accurate position from player node
            if let nodeTime   = playerNode.lastRenderTime,
               let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
               playerTime.sampleRate > 0,
               playerTime.sampleTime >= 0 {
                let computed = Double(playerTime.sampleTime) / playerTime.sampleRate + seekTime
                currentTime  = duration > 0 ? min(computed, duration) : computed
            }

            // Update Now Playing periodically so lock screen progress bar moves
            updateNowPlaying()

            // Crossfade trigger
            if isCrossfadeEnabled && !crossfadeTriggered && duration > 0 {
                let remaining = duration - currentTime
                if remaining <= crossfadeDuration && remaining > 0 {
                    crossfadeTriggered = true
                    onCrossfadeNeeded?()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Now Playing Info

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                    track.title,
            MPMediaItemPropertyArtist:                   track.artist,
            MPMediaItemPropertyAlbumTitle:               track.album,
            MPMediaItemPropertyPlaybackDuration:         duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? Double(playbackRate) : 0.0
        ]
        if let art = track.artwork {
            let sz = CGSize(width: 500, height: 500)
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: sz) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget            { [weak self] _ in self?.resume();          return .success }
        cc.pauseCommand.addTarget           { [weak self] _ in self?.pause();           return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        cc.nextTrackCommand.addTarget       { [weak self] _ in self?.onNextRequested?();     return .success }
        cc.previousTrackCommand.addTarget   { [weak self] _ in self?.onPreviousRequested?(); return .success }
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
            return .success
        }
    }
}
