import SwiftUI

/// "Nyt soi" Apple TV:lle: iso kansikuva ja ohjaimet vasemmalla, sävellaji ja soinnut isolla oikealla.
struct TVNowPlayingTab: View {
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @AppStorage("finnishNotation") private var finnish = true

    var body: some View {
        if let t = player.current {
            HStack(alignment: .top, spacing: 80) {
                VStack(spacing: 28) {
                    Cover(url: t.thumbnailURL, size: 520, radius: 24)
                        .shadow(radius: 20, y: 10)
                    VStack(spacing: 6) {
                        Text(t.title).font(.title2.bold()).lineLimit(2).multilineTextAlignment(.center)
                        if let a = t.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    ProgressView(value: min(player.currentTime, max(player.duration, 1)), total: max(player.duration, 1))
                        .frame(width: 520)
                    HStack(spacing: 30) {
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Button { player.togglePlay() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                        Button { library.toggleFavorite(t) } label: {
                            Image(systemName: library.isFavorite(t) ? "heart.fill" : "heart")
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.primary)
                }
                .frame(width: 560)

                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Sävellaji ja soinnut").font(.title3.bold())
                        Spacer()
                        Picker("Nuotinimet", selection: $finnish) {
                            Text("H").tag(true)
                            Text("B").tag(false)
                        }
                        .pickerStyle(.segmented).frame(width: 200)
                    }
                    TVChordView(finnish: finnish)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(60)
        } else {
            ContentUnavailableView("Ei soitettavaa", systemImage: "waveform", description: Text("Valitse kappale hausta tai kirjastosta."))
        }
    }
}

struct TVChordView: View {
    let finnish: Bool
    @Environment(Player.self) private var player

    var body: some View {
        switch player.engine.state {
        case .idle:
            Text("Soita kappale, niin sävellaji ja soinnut näkyvät tässä.").foregroundStyle(.secondary)
        case .loading(let msg):
            HStack(spacing: 16) { ProgressView(); Text(msg).foregroundStyle(.secondary) }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        case .done(let a):
            content(a)
        }
    }

    @ViewBuilder
    private func content(_ a: TrackAnalysis) -> some View {
        let flats = a.useFlats
        let idx = a.index(at: player.currentTime)
        let seg = idx.map { a.segments[$0] }
        let upcoming: [ChordSegment] = idx.map { i in
            Array(a.segments[(i + 1)...].filter { !$0.isNoChord }.prefix(5))
        } ?? []
        let rel = a.keyMinor ? (a.keyRoot + 3) % 12 : (a.keyRoot + 9) % 12

        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SÄVELLAJI").font(.caption).foregroundStyle(.secondary)
                Text(Notation.key(root: a.keyRoot, minor: a.keyMinor, flats: flats, finnish: finnish))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                Text("Suhteellinen: " + Notation.key(root: rel, minor: !a.keyMinor, flats: flats, finnish: finnish))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("NYT").font(.caption).foregroundStyle(.secondary)
                Text(seg.map { Notation.chord($0, flats: flats, finnish: finnish) } ?? "–")
                    .font(.system(size: 150, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                if let seg { Text(Notation.chordNotes(seg, flats: flats, finnish: finnish)).font(.title3).foregroundStyle(.secondary) }
            }
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEURAAVAKSI").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 28) {
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { i, s in
                            Text(Notation.chord(s, flats: flats, finnish: finnish))
                                .font(.system(size: i == 0 ? 56 : 42, weight: i == 0 ? .bold : .regular, design: .rounded))
                                .foregroundStyle(i == 0 ? Color.primary : .secondary)
                        }
                    }
                }
            }
        }
    }
}
