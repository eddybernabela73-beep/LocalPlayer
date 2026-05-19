import Foundation
import AVFoundation

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

// MARK: - PlayerViewModel

@Observable
final class PlayerViewModel {

    // MARK: - Library state
    var tracks: [Track] = []
    var isLoading = false
    var folderName = ""

    // MARK: - Playback state
    var currentIndex = -1
    var isShuffled = false
    var repeatMode: RepeatMode = .off

    // MARK: - UI state
    var showPlayer = false
    var showFilePicker = false

    // MARK: - Forwarded from AudioPlayerService
    var isPlaying: Bool        { audioService.isPlaying }
    var currentTime: TimeInterval { audioService.currentTime }
    var duration: TimeInterval  { audioService.duration }
    var currentTrack: Track?   { audioService.currentTrack }

    // MARK: - Private
    private let audioService = AudioPlayerService()
    private var shuffleQueue: [Int] = []
    private var folderURL: URL?
    private var isFolderAccessing = false
    private let defaults = UserDefaults.standard

    init() {
        audioService.onTrackFinished = { [weak self] in
            Task { @MainActor in self?.advance() }
        }
        audioService.onNextRequested = { [weak self] in
            Task { @MainActor in self?.playNext() }
        }
        audioService.onPreviousRequested = { [weak self] in
            Task { @MainActor in self?.playPrevious() }
        }
        restoreSession()
    }

    deinit {
        releaseFolder()
    }

    // MARK: - Folder Management

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

        let supportedExtensions = Set(["mp3", "m4a", "wav", "aac", "flac", "aiff", "opus", "m4b", "caf"])

        let files = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.nameKey],
            options: .skipsHiddenFiles
        )) ?? []

        let audioFiles = files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var loaded: [Track] = []
        for fileURL in audioFiles {
            let track = await loadTrackMetadata(url: fileURL)
            loaded.append(track)
        }

        tracks = loaded
        isLoading = false

        // Restore last played track by filename
        if let lastName = defaults.string(forKey: "lastTrackFile") {
            currentIndex = tracks.firstIndex(where: { $0.url.lastPathComponent == lastName }) ?? -1
        }
    }

    private func loadTrackMetadata(url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        var title  = url.deletingPathExtension().lastPathComponent
        var artist = "Desconocido"
        var album  = ""
        var artworkData: Data?
        var duration: TimeInterval = 0

        if let dur = try? await asset.load(.duration) {
            duration = dur.seconds.isNaN ? 0 : max(0, dur.seconds)
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                switch item.commonKey {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.trimmingCharacters(in: .whitespaces).isEmpty {
                        title = v
                    }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue) { album = v }
                case .commonKeyArtwork:
                    if let v = try? await item.load(.dataValue) { artworkData = v }
                default:
                    break
                }
            }
        }

        return Track(
            id: UUID(),
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkData: artworkData
        )
    }

    // MARK: - Playback Control

    func play(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        currentIndex = index
        audioService.play(track: tracks[index])
        defaults.set(tracks[index].url.lastPathComponent, forKey: "lastTrackFile")
        if isShuffled { buildShuffleQueue(excluding: index) }
    }

    func togglePlayPause() {
        if currentTrack == nil, !tracks.isEmpty {
            play(at: currentIndex >= 0 ? currentIndex : 0)
        } else {
            audioService.togglePlayPause()
        }
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

    func seek(to time: TimeInterval) {
        audioService.seek(to: time)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled { buildShuffleQueue(excluding: currentIndex) }
    }

    func toggleRepeat() {
        repeatMode = repeatMode.next
    }

    // MARK: - Queue Logic

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
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
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
