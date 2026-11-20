import Foundation
import AVFoundation
import Accelerate

// Tila 0...47 = sointu (juuri + 12 * laatu), 48 = ei sointua
enum ChordQuality: Int, CaseIterable {
    case major, minor, dom7, min7
    var suffix: String { ["", "m", "7", "m7"][rawValue] }
    var intervals: [Int] { [[0, 4, 7], [0, 3, 7], [0, 4, 7, 10], [0, 3, 7, 10]][rawValue] }
}

struct ChordSegment: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let state: Int
    var isNoChord: Bool { state >= 48 }
    var root: Int { state % 12 }
    var quality: ChordQuality { ChordQuality(rawValue: state / 12) ?? .major }
}

struct TrackAnalysis {
    let keyRoot: Int
    let keyMinor: Bool
    let keyConfidence: Double
    let segments: [ChordSegment]

    /// Käytetäänkö bemolleja nuottien kirjoitusasussa (sävellajin mukaan)
    var useFlats: Bool {
        keyMinor ? [2, 7, 0, 5, 10, 3].contains(keyRoot) : [5, 10, 3, 8, 1, 6].contains(keyRoot)
    }

    func index(at t: Double) -> Int? {
        guard !segments.isEmpty else { return nil }
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

enum Notation {
    static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func note(_ pc: Int, flats useFlats: Bool, finnish: Bool) -> String {
        var n = (useFlats ? flats : sharps)[((pc % 12) + 12) % 12]
        if finnish {
            if n == "B" { n = "H" } else if n == "Bb" { n = "B" }
        }
        return n
    }

    static func chord(_ seg: ChordSegment, flats: Bool, finnish: Bool) -> String {
        if seg.isNoChord { return "–" }
        return note(seg.root, flats: flats, finnish: finnish) + seg.quality.suffix
    }

    static func chordNotes(_ seg: ChordSegment, flats: Bool, finnish: Bool) -> String {
        if seg.isNoChord { return "" }
        return seg.quality.intervals.map { note(seg.root + $0, flats: flats, finnish: finnish) }.joined(separator: " – ")
    }

    static func key(root: Int, minor: Bool, flats: Bool, finnish: Bool) -> String {
        let n = note(root, flats: flats, finnish: finnish)
        if finnish { return n + (minor ? "-molli" : "-duuri") }
        return n + (minor ? " minor" : " major")
    }
}

enum AnalysisError: LocalizedError {
    case noAudio, tooShort, readFailed
    var errorDescription: String? {
        switch self {
        case .noAudio: return "Äänidataa ei löytynyt."
        case .tooShort: return "Kappale on liian lyhyt analysoitavaksi."
        case .readFailed: return "Äänen purku epäonnistui."
        }
    }
}

enum ChordAnalyzer {
    static let sr: Double = 22050
    static let N = 8192
    static let hop = 4096

    static func analyze(url: URL, maxSeconds: Double = 600) async throws -> TrackAnalysis {
        let samples = try await decode(url: url, maxSeconds: maxSeconds)
        guard samples.count > N * 4 else { throw AnalysisError.tooShort }
        try Task.checkCancellation()

        let frames = (samples.count - N) / hop + 1
        let (peakStart, peakMidi, peakW) = spectralPeaks(samples: samples, frames: frames)
        try Task.checkCancellation()

        // Viritys: painotettu ympyräkeskiarvo nuottien poikkeamasta
        var sc: Float = 0, ss: Float = 0
        for i in 0..<peakMidi.count {
            let dev = peakMidi[i] - peakMidi[i].rounded()
            sc += peakW[i] * cosf(2 * .pi * dev)
            ss += peakW[i] * sinf(2 * .pi * dev)
        }
        let tuning: Float = atan2f(ss, sc) / (2 * .pi)

        // Kroma jokaiselle kehykselle
        var chroma = [Float](repeating: 0, count: frames * 12)
        var energy = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            for i in peakStart[f]..<peakStart[f + 1] {
                let pc = ((Int((peakMidi[i] - tuning).rounded()) % 12) + 12) % 12
                chroma[f * 12 + pc] += peakW[i]
                energy[f] += peakW[i]
            }
        }

        // Pehmennys (3 kehystä) ja normalisointi
        var smooth = [Float](repeating: 0, count: frames * 12)
        for f in 0..<frames {
            let a = max(0, f - 1), b = min(frames - 1, f + 1)
            for g in a...b { for p in 0..<12 { smooth[f * 12 + p] += chroma[g * 12 + p] } }
            var norm: Float = 0
            for p in 0..<12 { norm += smooth[f * 12 + p] * smooth[f * 12 + p] }
            norm = sqrtf(norm)
            if norm > 0 { for p in 0..<12 { smooth[f * 12 + p] /= norm } }
        }

        let key = estimateKey(chroma: chroma, frames: frames)
        let states = decodeChords(chroma: smooth, energy: energy, frames: frames)

        // Segmentit
        let hopSec = Double(hop) / sr
        let total = Double(samples.count) / sr
        var segments: [ChordSegment] = []
        var startFrame = 0
        for f in 1...frames {
            if f == frames || states[f] != states[startFrame] {
                let start = startFrame == 0 ? 0 : Double(startFrame) * hopSec + Double(N / 2) * 1 / sr - hopSec / 2
                let end = f == frames ? total : Double(f) * hopSec + Double(N / 2) / sr - hopSec / 2
                segments.append(ChordSegment(id: segments.count, start: start, end: end, state: states[startFrame]))
                startFrame = f
            }
        }
        return TrackAnalysis(keyRoot: key.root, keyMinor: key.minor, keyConfidence: key.confidence, segments: segments)
    }

    // MARK: Äänen purku

    private static func decode(url: URL, maxSeconds: Double) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw AnalysisError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
        ]
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(out)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        guard reader.startReading() else { throw reader.error ?? AnalysisError.readFailed }
        var samples = [Float]()
        samples.reserveCapacity(Int(sr * min(maxSeconds, 400)))
        while let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let len = CMBlockBufferGetDataLength(bb)
            var chunk = [Float](repeating: 0, count: len / 4)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: raw.baseAddress!)
            }
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed { throw reader.error ?? AnalysisError.readFailed }
        return samples
    }

    // MARK: Spektrin huiput (100–2000 Hz)

    private static func spectralPeaks(samples: [Float], frames: Int) -> ([Int], [Float], [Float]) {
        let log2n = vDSP_Length(13)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: N)
        vDSP_hann_window(&window, vDSP_Length(N), Int32(vDSP_HANN_NORM))

        let kLo = Int((100.0 * Double(N) / sr).rounded(.down)) - 1
        let kHi = Int((2000.0 * Double(N) / sr).rounded(.up)) + 1
        let nb = kHi - kLo + 1

        var real = [Float](repeating: 0, count: N / 2)
        var imag = [Float](repeating: 0, count: N / 2)
        var frame = [Float](repeating: 0, count: N)
        var mags = [Float](repeating: 0, count: nb)

        var peakStart = [Int](repeating: 0, count: frames + 1)
        var peakMidi = [Float]()
        var peakW = [Float]()

        for f in 0..<frames {
            peakStart[f] = peakMidi.count
            let s = f * hop
            samples.withUnsafeBufferPointer { sp in
                vDSP_vmul(sp.baseAddress! + s, 1, window, 1, &frame, 1, vDSP_Length(N))
            }
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(N / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    for j in 0..<nb {
                        let k = kLo + j
                        let r = rp[k], i = ip[k]
                        mags[j] = sqrtf(r * r + i * i)
                    }
                }
            }
            for j in 1..<(nb - 1) {
                let b = mags[j]
                let a = mags[j - 1], c = mags[j + 1]
                if b > a && b >= c && b > 1e-4 {
                    let denom = a - 2 * b + c
                    let delta: Float = denom != 0 ? 0.5 * (a - c) / denom : 0
                    let freq = (Float(kLo + j) + delta) * Float(sr) / Float(N)
                    peakMidi.append(12 * log2f(freq / 440) + 69)
                    peakW.append(sqrtf(b))
                }
            }
        }
        peakStart[frames] = peakMidi.count
        return (peakStart, peakMidi, peakW)
    }

    // MARK: Sävellaji (Krumhansl–Kessler)

    private static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private static func estimateKey(chroma: [Float], frames: Int) -> (root: Int, minor: Bool, confidence: Double) {
        var mean = [Float](repeating: 0, count: 12)
        for f in 0..<frames {
            var norm: Float = 0
            for p in 0..<12 { norm += chroma[f * 12 + p] * chroma[f * 12 + p] }
            norm = sqrtf(norm)
            if norm > 0 { for p in 0..<12 { mean[p] += chroma[f * 12 + p] / norm } }
        }
        func corr(_ x: [Float], _ y: [Float]) -> Float {
            let mx = x.reduce(0, +) / 12, my = y.reduce(0, +) / 12
            var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
            for i in 0..<12 { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) * (x[i] - mx); syy += (y[i] - my) * (y[i] - my) }
            return sxx > 0 && syy > 0 ? sxy / sqrtf(sxx * syy) : 0
        }
        var best: (Int, Bool, Float) = (0, false, -2)
        for root in 0..<12 {
            let rotated: [Float] = (0..<12).map { mean[($0 + root) % 12] }
            let cm = corr(rotated, majorProfile)
            let cn = corr(rotated, minorProfile)
            if cm > best.2 { best = (root, false, cm) }
            if cn > best.2 { best = (root, true, cn) }
        }
        return (best.0, best.1, Double(best.2))
    }

    // MARK: Soinnut (kosinipohjainen pisteytys + Viterbi-tasoitus)

    private static func decodeChords(chroma: [Float], energy: [Float], frames: Int) -> [Int] {
        // Pohjasävelpohjaiset mallit
        var templates = [[Float]](repeating: [Float](repeating: 0, count: 12), count: 48)
        let weights: [[Int: Float]] = [
            [0: 1.0, 4: 0.85, 7: 0.9],
            [0: 1.0, 3: 0.85, 7: 0.9],
            [0: 1.0, 4: 0.8, 7: 0.85, 10: 0.6],
            [0: 1.0, 3: 0.8, 7: 0.85, 10: 0.6],
        ]
        let bias: [Float] = [0, 0, -0.04, -0.04]
        for q in 0..<4 {
            for root in 0..<12 {
                var t = [Float](repeating: 0, count: 12)
                for (iv, w) in weights[q] { t[(root + iv) % 12] = w }
                let n = sqrtf(t.reduce(0) { $0 + $1 * $1 })
                templates[q * 12 + root] = t.map { $0 / n }
            }
        }

        let sortedEnergy = energy.sorted()
        let median = sortedEnergy[sortedEnergy.count / 2]
        let silent: Float = median * 0.08

        let S = 49
        var score = [Float](repeating: 0, count: S)
        var back = [[UInt8]](repeating: [UInt8](repeating: 0, count: S), count: frames)
        let penalty: Float = 0.45

        func emission(_ f: Int, _ s: Int) -> Float {
            if energy[f] < silent { return s == 48 ? 1 : 0 }
            if s == 48 { return 0.2 }
            let t = templates[s]
            var d: Float = 0
            for p in 0..<12 { d += chroma[f * 12 + p] * t[p] }
            return d + bias[s / 12]
        }

        for s in 0..<S { score[s] = emission(0, s) }
        for f in 1..<frames {
            var bestPrev: Float = -.infinity
            var arg = 0
            for s in 0..<S where score[s] > bestPrev { bestPrev = score[s]; arg = s }
            var next = [Float](repeating: 0, count: S)
            for s in 0..<S {
                let stay = score[s]
                let jump = bestPrev - penalty
                if stay >= jump { next[s] = stay + emission(f, s); back[f][s] = UInt8(s) }
                else { next[s] = jump + emission(f, s); back[f][s] = UInt8(arg) }
            }
            score = next
        }
        var state = 0
        var bestFinal: Float = -.infinity
        for s in 0..<S where score[s] > bestFinal { bestFinal = score[s]; state = s }
        var path = [Int](repeating: 0, count: frames)
        for f in stride(from: frames - 1, through: 0, by: -1) {
            path[f] = state
            state = Int(back[f][state])
        }
        return path
    }
}
