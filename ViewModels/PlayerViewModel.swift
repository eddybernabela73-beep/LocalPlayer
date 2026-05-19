import Foundation
import AVFoundation

// MARK: - Sort Mode

enum SortMode: String, CaseIterable, Identifiable {
    case title    = "Título"
    case artist   = "Artista"
    case album    = "Álbum"
    case duration = "Duración"
    var id: String { rawValue }
}

// MARK: - Repeat Mode

enum RepeatMode: String {
    case off, one, all

    var next: RepeatMode {
        switch self {
        case .off: .one
        case .one: .all
        case .all: .off
        }
    }
    var systemImage: String {
        switch self {
        case .off:  "repeat"
        case .one:  "repeat.1"
        case .all:  "repeat"
        }
    }
    var isActive: Bool { self != .off }
}

// MARK: - Lyrics response

private struct LyricsResponse: Decodable {
    let lyrics: String
}

// MARK: - PlayerViewModel

@Observable
final class PlayerViewModel {

    // MARK: - Library
    var tracks: [Track] = []
    var isLoading = false
    var folderName = ""
    var searchText = ""
    var sortMode: SortMode = .title

    var displayTracks: [Track] {
        var result = tracks
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)  ||
                $0.artist.localizedCaseInsensitiveContains(searchText) ||
                $0.album.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortMode {
        case .title:    result.sort { $0.title.localizedCaseInsensitiveCompare($1.title)    == .orderedAscending }
        case .artist:   result.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist)  == .orderedAscending }
        case .album:    result.sort { $0.album.localizedCaseInsensitiveCompare($1.album)    == .orderedAscending }
        case .duration: result.sort { $0.duration < $1.duration }
        }
        return result
    }

    // MARK: - Playback state
    var currentIndex = -1
    var isShuffled   = false
    var repeatMode: RepeatMode = .off

    // MARK: - Speed
    static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var playbackSpeed: Float {
        get { audioService.playbackRate }
        set { audioService.playbackRate = newValue }
    }
    var speedLabel: String {
        let s = playbackSpeed
        return s == Float(Int(s)) ? "\(Int(s))x" : String(format: "%.2gx", s)
    }
    func cycleSpeed() {
        let opts = PlayerViewModel.speedOptions
        let idx  = opts.firstIndex(of: playbackSpeed) ?? 2
        playbackSpeed = opts[(idx + 1) % opts.count]
    }

    // MARK: - Crossfade
    var isCrossfadeEnabled: Bool {
        get { audioService.isCrossfadeEnabled }
        set { audioService.isCrossfadeEnabled = newValue }
    }

    // MARK: - Sleep Timer
    var sleepTimerActive    = false
    var sleepTimerRemaining: TimeInterval = 0
    private var sleepTimer: Timer?

    var sleepTimerLabel: String {
        let total = Int(sleepTimerRemaining)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        sleepTimerRemaining = TimeInterval(minutes * 60)
        sleepTimerActive    = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sleepTimerRemaining -= 1
                if self.sleepTimerRemaining <= 0 {
                    self.audioService.pause()
                    self.cancelSleepTimer()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }
    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerActive    = false
        sleepTimerRemaining = 0
    }

    // MARK: - EQ
    var eqGains: [Float] {
        get { audioService.eqGains }
        set { audioService.eqGains = newValue }
    }
    func resetEQ() { audioService.eqGains = [0, 0, 0, 0, 0] }

    // MARK: - Lyrics
    var lyrics        = ""
    var lyricsLoading = false
    var lyricsError   = false

    func fetchLyrics() {
        guard let track = currentTrack else { return }
        let artist = track.artist == "Desconocido" ? "" : track.artist
        guard !artist.isEmpty else { lyricsError = true; return }

        let a = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let t = track.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://api.lyrics.ovh/v1/\(a)/\(t)") else { return }

        lyricsLoading = true
        lyricsError   = false
        lyrics        = ""

        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let resp = try JSONDecoder().decode(LyricsResponse.self, from: data)
                lyrics        = resp.lyrics
                lyricsLoading = false
            } catch {
                lyricsError   = true
                lyricsLoading = false
            }
        }
    }

    // MARK: - UI state
    var showPlayer    = false
    var showFilePicker = false

    // MARK: - Forwarded from AudioPlayerService
    var isPlaying:   Bool          { audioService.isPlaying }
    var currentTime: TimeInterval  { audioService.currentTime }
    var duration:    TimeInterval  { audioService.duration }
    var currentTrack: Track?       { audioService.currentTrack }

    // MARK: - Private
    private let audioService = AudioPlayerService()
    private var shuffleQueue: [Int] = []
    private var folderURL: URL?
    private var isFolderAccessing = false
    private let defaults = UserDefaults.standard

    init() {
        audioService.onTrackFinished    = { [weak self] in Task { @MainActor in self?.advance() } }
        audioService.onNextRequested    = { [weak self] in Task { @MainActor in self?.playNext() } }
        audioService.onPreviousRequested = { [weak self] in Task { @MainActor in self?.playPrevious() } }
        audioService.onCrossfadeNeeded  = { [weak self] in Task { @MainActor in self?.handleCrossfade() } }
        restoreSession()
    }

    deinit { releaseFolder() }

    // MARK: - Folder

    func loadFolder(url: URL) {
        releaseFolder()
        folderURL = url
        isFolderAccessing = url.startAccessingSecurityScopedResource()
        folderName = url.lastPathComponent
        saveBookmark(url: url)
        Task { await scanFolder(url: url) }
    }

    private func releaseFolder() {
        if isFolderAccessing, let url = folderURL {
            url.stopAccessingSecurityScopedResource()
            isFolderAccessing = false
        }
    }

    @MainActor
    private func scanFolder(url: URL) async {
        isLoading = true
        let ext = Set(["mp3","m4a","wav","aac","flac","aiff","opus","m4b","caf"])
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.nameKey], options: .skipsHiddenFiles
        )) ?? []
        let audioFiles = files
            .filter { ext.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var loaded: [Track] = []
        for fileURL in audioFiles { loaded.append(await loadTrackMetadata(url: fileURL)) }
        tracks    = loaded
        isLoading = false
        if let last = defaults.string(forKey: "lastTrackFile") {
            currentIndex = tracks.firstIndex { $0.url.lastPathComponent == last } ?? -1
        }
    }

    private func loadTrackMetadata(url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Desconocido"
        var album  = ""
        var artworkData: Data?
        var dur: TimeInterval = 0

        if let d = try? await asset.load(.duration) { dur = d.seconds.isNaN ? 0 : max(0, d.seconds) }
        if let meta = try? await asset.load(.commonMetadata) {
            for item in meta {
                switch item.commonKey {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.trimmingCharacters(in: .whitespaces).isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue) { album = v }
                case .commonKeyArtwork:
                    if let v = try? await item.load(.dataValue) { artworkData = v }
                default: break
                }
            }
        }
        return Track(id: UUID(), url: url, title: title, artist: artist, album: album, duration: dur, artworkData: artworkData)
    }

    // MARK: - Playback

    func play(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        currentIndex = index
        audioService.play(track: tracks[index])
        defaults.set(tracks[index].url.lastPathComponent, forKey: "lastTrackFile")
        if isShuffled { buildShuffleQueue(excluding: index) }
        // Reset lyrics when track changes
        lyrics = ""; lyricsError = false; lyricsLoading = false
    }

    func play(track: Track) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        play(at: idx)
    }

    func togglePlayPause() {
        if currentTrack == nil, !tracks.isEmpty { play(at: currentIndex >= 0 ? currentIndex : 0) }
        else { audioService.togglePlayPause() }
    }

    func playNext() {
        guard !tracks.isEmpty else { return }
        if repeatMode == .one { play(at: currentIndex); return }
        if let next = nextIndex() { play(at: next) }
    }

    func playPrevious() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3 { seek(to: 0); return }
        play(at: previousIndex())
    }

    func seek(to time: TimeInterval) { audioService.seek(to: time) }
    func toggleShuffle() { isShuffled.toggle(); if isShuffled { buildShuffleQueue(excluding: currentIndex) } }
    func toggleRepeat()  { repeatMode = repeatMode.next }

    // MARK: - Crossfade

    private func handleCrossfade() {
        guard !tracks.isEmpty else { return }
        if repeatMode == .one { audioService.startCrossfadeTo(track: tracks[currentIndex]); return }
        if let next = nextIndex() {
            currentIndex = next
            audioService.startCrossfadeTo(track: tracks[next])
            defaults.set(tracks[next].url.lastPathComponent, forKey: "lastTrackFile")
        }
    }

    // MARK: - Queue

    private func advance() {
        if repeatMode == .one { play(at: currentIndex); return }
        if let next = nextIndex() { play(at: next) }
    }

    private func nextIndex() -> Int? {
        guard !tracks.isEmpty else { return nil }
        if isShuffled {
            if let next = shuffleQueue.first {
                shuffleQueue.removeFirst()
                if shuffleQueue.isEmpty { buildShuffleQueue(excluding: next) }
                return next
            }
            return nil
        }
        let next = currentIndex + 1
        if next < tracks.count { return next }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func previousIndex() -> Int {
        guard !tracks.isEmpty else { return 0 }
        if isShuffled { return Int.random(in: 0..<tracks.count) }
        return max(0, currentIndex - 1)
    }

    private func buildShuffleQueue(excluding index: Int) {
        shuffleQueue = Array(0..<tracks.count).filter { $0 != index }.shuffled()
    }

    // MARK: - Persistence

    private func saveBookmark(url: URL) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(data, forKey: "folderBookmark")
        }
        defaults.set(url.lastPathComponent, forKey: "folderName")
    }

    private func restoreSession() {
        folderName = defaults.string(forKey: "folderName") ?? ""
        guard let data = defaults.data(forKey: "folderBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        if stale { saveBookmark(url: url) }
        folderURL = url
        isFolderAccessing = url.startAccessingSecurityScopedResource()
        Task { await scanFolder(url: url) }
    }
}
