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

    // MARK: - Engine  playerNode → eqNode → timePitchNode → mainMixerNode
    private let engine        = AVAudioEngine()
    private let playerNode    = AVAudioPlayerNode()
    private let eqNode        = AVAudioUnitEQ(numberOfBands: 5)
    private let timePitchNode = AVAudioUnitTimePitch()

    private var currentFile: AVAudioFile?
    private var seekOffset:  TimeInterval = 0   // time base when the current buffer chain started

    // Incremented on every play/seek — old completion callbacks drop themselves
    private var generation = 0

    // Buffer pipeline: schedule N overlapping 2-second chunks so background
    // rendering never starves even if the main queue is briefly busy.
    private let preloadCount  = 3
    private let bufferFrames: AVAudioFrameCount = 88_200  // ≈ 2 s at 44.1 kHz

    private var progressTimer:     Timer?
    private var crossfadeTriggered = false
    private var notificationTokens: [Any] = []

    // MARK: - Init / Deinit

    init() {
        setupAudioSession()   // session must be active BEFORE engine starts
        setupEngine()
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
        connectNodes()
        configureEQBands()
        timePitchNode.rate    = 1.0
        timePitchNode.pitch   = 0
        timePitchNode.overlap = 4.0
        startEngine()
    }

    /// Separated so it can be called after AVAudioEngineConfigurationChange
    /// resets all connections.
    private func connectNodes() {
        engine.connect(playerNode,    to: eqNode,               format: nil)
        engine.connect(eqNode,        to: timePitchNode,        format: nil)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: nil)
    }

    private func configureEQBands() {
        let freqs: [Float] = [60, 250, 1000, 4000, 16000]
        for (i, f) in freqs.enumerated() {
            eqNode.bands[i].filterType = .parametric
            eqNode.bands[i].frequency  = f
            eqNode.bands[i].bandwidth  = 1.0
            eqNode.bands[i].gain       = 0
            eqNode.bands[i].bypass     = false
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do { try engine.start() }
        catch { print("[Audio] Engine start: \(error)") }
    }

    /// Full restart: reconnect nodes (iOS may have reset them), restart engine,
    /// then resume the buffer chain from the current playback position.
    private func restartAndResume() {
        connectNodes()
        startEngine()
        guard isPlaying, let file = currentFile else { return }
        beginBufferChain(file: file, from: currentTime)
        playerNode.play()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true)
        } catch { print("[Audio] Session: \(error)") }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngine()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let s = AVAudioSession.sharedInstance()

        let t1 = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: s, queue: .main
        ) { [weak self] n in self?.handleInterruption(n) }

        let t2 = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: s, queue: .main
        ) { [weak self] n in self?.handleRouteChange(n) }

        // When iOS reconfigures audio (Bluetooth, screen lock route change…)
        // it disconnects all engine nodes — reconnect + resume.
        let t3 = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartAndResume() }

        notificationTokens = [t1, t2, t3]
    }

    private func handleInterruption(_ n: Notification) {
        guard let val  = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: val) else { return }
        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            activateSession()
            let opts = AVAudioSession.InterruptionOptions(
                rawValue: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if opts.contains(.shouldResume) { resume() }
        @unknown default: break
        }
    }

    private func handleRouteChange(_ n: Notification) {
        guard let val    = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: val) else { return }
        if reason == .oldDeviceUnavailable { pause() }   // headphones unplugged
    }

    // MARK: - Buffer pipeline
    //
    // Instead of scheduleFile (one-shot, fragile in background), we schedule
    // short PCM buffers in a self-replenishing chain.  Each buffer's completion
    // handler queues the next one on the main thread before the audio clock
    // needs it, giving the engine a 4-6 second look-ahead.

    private func beginBufferChain(file: AVAudioFile, from time: TimeInterval) {
        let sr = file.processingFormat.sampleRate
        file.framePosition = AVAudioFramePosition(max(0, time * sr))
        seekOffset = time
        let gen = generation
        for _ in 0..<preloadCount { pumpBuffer(file: file, gen: gen) }
    }

    private func pumpBuffer(file: AVAudioFile, gen: Int) {
        guard gen == generation else { return }

        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: bufferFrames) else { return }
        do { try file.read(into: buf) } catch { return }

        if buf.frameLength == 0 {
            // Reached end of file — update state on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.isPlaying = false
                self.stopTimer()
                self.onTrackFinished?()
            }
            return
        }

        playerNode.scheduleBuffer(buf, completionCallbackType: .dataConsumed) { [weak self] _ in
            // ⚠️  Do NOT dispatch to main here.
            // When the app is in background the main queue is throttled and
            // can stall for seconds, starving the audio pipeline and cutting
            // the sound.  The audio-engine completion thread keeps running in
            // background even when main is sleeping, so pump the next buffer
            // directly from here.
            self?.pumpBuffer(file: file, gen: gen)
        }
    }

    // MARK: - Playback

    func play(track: Track) {
        playerNode.stop()
        generation        += 1
        currentTime        = 0
        crossfadeTriggered = false

        do {
            let file = try AVAudioFile(forReading: track.url)
            currentFile  = file
            let sr       = file.processingFormat.sampleRate
            duration     = sr > 0 ? Double(file.length) / sr : 0
            currentTrack = track

            activateSession()
            timePitchNode.rate = playbackRate

            beginBufferChain(file: file, from: 0)
            playerNode.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        } catch {
            print("[Audio] Play error: \(error)")
        }
    }

    func startCrossfadeTo(track: Track) {
        let steps    = 20
        let interval = crossfadeDuration / Double(steps)
        var step     = 0
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            step += 1
            playerNode.volume = max(0, 1.0 - Float(step) / Float(steps))
            if step >= steps {
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
        guard !isPlaying, currentFile != nil else { return }
        activateSession()
        playerNode.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()
        generation        += 1
        currentTime        = time
        crossfadeTriggered = false

        beginBufferChain(file: file, from: time)

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
            guard let self, self.isPlaying else { return }

            // Safety net: if the engine died silently in background, revive it
            if !self.engine.isRunning {
                self.restartAndResume()
                return
            }

            // Playback position = engine sample position + seek base
            if let nodeTime   = self.playerNode.lastRenderTime,
               let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime),
               playerTime.sampleRate > 0, playerTime.sampleTime >= 0 {
                let pos          = Double(playerTime.sampleTime) / playerTime.sampleRate + self.seekOffset
                self.currentTime = self.duration > 0 ? min(pos, self.duration) : pos
            }

            self.updateNowPlaying()

            if self.isCrossfadeEnabled && !self.crossfadeTriggered && self.duration > 0 {
                let left = self.duration - self.currentTime
                if left <= self.crossfadeDuration && left > 0 {
                    self.crossfadeTriggered = true
                    self.onCrossfadeNeeded?()
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

    // MARK: - Now Playing

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
