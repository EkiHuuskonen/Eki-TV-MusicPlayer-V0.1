import SwiftUI

struct ChordPanel: View {
    @Environment(Player.self) private var player
    @AppStorage("finnishNotation") private var finnish = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sävellaji ja soinnut").font(.headline)
                Spacer()
                Picker("Nuottinimet", selection: $finnish) {
                    Text("H").tag(true)
                    Text("B").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 70)
                .help("Nuottinimet: H/B (suomalainen) tai B/Bb (kansainvälinen)")
            }

            switch player.engine.state {
            case .idle:
                placeholder("music.note", "Soita kappale, niin sävellaji ja soinnut näkyvät tässä.")
            case .loading(let msg):
                VStack(spacing: 10) { ProgressView(); Text(msg).foregroundStyle(.secondary).font(.callout) }
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .failed(let msg):
                placeholder("exclamationmark.triangle", msg)
            case .done(let a):
                AnalysisContent(analysis: a, finnish: finnish)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).font(.callout)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct AnalysisContent: View {
    let analysis: TrackAnalysis
    let finnish: Bool
    @Environment(Player.self) private var player

    var body: some View {
        let flats = analysis.useFlats
        let idx = analysis.index(at: player.currentTime)
        let seg = idx.map { analysis.segments[$0] }
        let nextSeg: ChordSegment? = idx.flatMap { i in
            analysis.segments[(i + 1)...].first(where: { !$0.isNoChord })
        }
        let relRoot = analysis.keyMinor ? (analysis.keyRoot + 3) % 12 : (analysis.keyRoot + 9) % 12

        VStack(alignment: .leading, spacing: 14) {
            // Sävellaji
            VStack(alignment: .leading, spacing: 2) {
                Text("SÄVELLAJI").font(.caption2).foregroundStyle(.secondary)
                Text(Notation.key(root: analysis.keyRoot, minor: analysis.keyMinor, flats: flats, finnish: finnish))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Suhteellinen: " + Notation.key(root: relRoot, minor: !analysis.keyMinor, flats: flats, finnish: finnish))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            // Nykyinen sointu
            VStack(alignment: .leading, spacing: 4) {
                Text("NYT").font(.caption2).foregroundStyle(.secondary)
                Text(seg.map { Notation.chord($0, flats: flats, finnish: finnish) } ?? "–")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.identity)
                if let seg { Text(Notation.chordNotes(seg, flats: flats, finnish: finnish)).font(.callout).foregroundStyle(.secondary) }
                if let n = nextSeg {
                    Text("Seuraavaksi: ").font(.callout).foregroundStyle(.secondary)
                        + Text(Notation.chord(n, flats: flats, finnish: finnish)).font(.callout.bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            // Sointulista
            Text("SOINTUKULKU").font(.caption2).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(analysis.segments) { s in
                            HStack {
                                Text(formatTime(s.start)).monospacedDigit().font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                                Text(Notation.chord(s, flats: flats, finnish: finnish)).font(.body.weight(s.id == idx ? .bold : .regular))
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(s.id == idx ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { player.seek(to: s.start + 0.05) }
                            .id(s.id)
                        }
                    }
                }
                .onChange(of: idx) { _, new in
                    if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            Text("Automaattinen arvio – toimii parhaiten selkeillä sointuilla. Analysoidaan korkeintaan 10 ensimmäistä minuuttia.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
