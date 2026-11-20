import AVFoundation
import MediaPlayer
import Observation

@Observable @MainActor
final class Player {
    var queue: [Track] = []
    var index = 0
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var shuffle = false
    var volume: Float = 0.8 { didSet { player.volume = volume; if volume > 0 && isMuted { isMuted = false } } }
    var isMuted = false { didSet { player.isMuted = isMuted } }

    func changeVolume(by delta: Float) { volume = min(1, max(0, volume + delta)) }

    let engine = ChordEngine()

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.volume = volume
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = t.seconds.isFinite ? t.seconds : 0
                self.isPlaying = self.player.timeControlStatus != .paused
            }
        }
        setupRemoteCommands()
    }

    func play(_ tracks: [Track], start: Int = 0) {
        guard tracks.indices.contains(start) else { return }
        queue = tracks
        index = start
        load()
    }

    func togglePlay() {
        guard current != nil else { return }
        if player.timeControlStatus == .paused { player.play(); isPlaying = true }
        else { player.pause(); isPlaying = false }
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if shuffle, queue.count > 1 {
            var n = index
            while n == index { n = Int.random(in: 0..<queue.count) }
            index = n
        } else if index + 1 < queue.count {
            index += 1
        } else {
            player.pause(); isPlaying = false; seek(to: 0); return
        }
        load()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || index == 0 { seek(to: 0) }
        else { index -= 1; load() }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    private func load() {
        guard let track = current else { return }
        let item = AVPlayerItem(url: track.url)
        if let old = endObserver { NotificationCenter.default.removeObserver(old) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = track.duration ?? 0
        player.play()
        isPlaying = true
        updateNowPlaying()
        engine.analyze(track)
        Task {
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
                if self.current?.id == track.id { self.duration = d.seconds; self.updateNowPlaying() }
            }
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
    }
}
