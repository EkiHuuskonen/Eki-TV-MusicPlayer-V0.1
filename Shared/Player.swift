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
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var localFile: URL?

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
        #if os(iOS) || os(tvOS)
        // Toisto jatkuu taustalla ja äänettömän kytkimen yli
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
    }

    var debugInfo: String {
        "status=\(player.timeControlStatus.rawValue) reason=\(player.reasonForWaitingToPlay?.rawValue ?? "-") err=\(String(describing: player.currentItem?.error)) itemStatus=\(player.currentItem?.status.rawValue ?? -1) time=\(player.currentTime().seconds) url=\(current?.url.absoluteString ?? "-")"
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

    func resume() {
        guard current != nil, !isPlaying || player.timeControlStatus == .paused else { return }
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.play(); isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        guard current != nil else { return }
        player.pause(); isPlaying = false
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
        removeLocalFile()
        watch(item, for: track)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = track.duration ?? 0
        #if os(iOS) || os(tvOS)
        // Muut (esim. käynnistysääni) voivat jättää istunnon "mixWithOthers"-tilaan, jolloin lukitusnäytön ohjaimet katoavat
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
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

    // MARK: Varatoisto: jos suoratoisto epäonnistuu (esim. palvelin ei tue AVPlayerin vaatimia tavuhakuja),
    // kappale ladataan väliaikaistiedostoon ja soitetaan sieltä.

    private func watch(_ item: AVPlayerItem, for track: Track) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.fallbackToLocal(track) }
        }
    }

    private func removeLocalFile() {
        if let f = localFile { try? FileManager.default.removeItem(at: f) }
        localFile = nil
    }

    private func fallbackToLocal(_ track: Track) {
        guard current?.id == track.id, localFile == nil, !track.isLive else { return }
        Task {
            do {
                let (tmp, _) = try await URLSession.shared.download(from: track.url)
                guard self.current?.id == track.id else { try? FileManager.default.removeItem(at: tmp); return }
                let ext = (track.file as NSString).pathExtension
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (ext.isEmpty ? "mp3" : ext))
                try FileManager.default.moveItem(at: tmp, to: dest)
                self.localFile = dest
                let item = AVPlayerItem(url: dest)
                if let old = self.endObserver { NotificationCenter.default.removeObserver(old) }
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.next() }
                }
                self.statusObservation = nil
                self.player.replaceCurrentItem(with: item)
                self.player.play()
                self.isPlaying = true
            } catch {
                self.isPlaying = false
            }
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand, c.previousTrackCommand, c.changePlaybackPositionCommand] { cmd.isEnabled = true }
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }
}
