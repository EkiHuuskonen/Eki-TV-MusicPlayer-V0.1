// Sävellajin ja soinnun tunnistus: spektrihuiput → kroma → Krumhansl–Kessler (sävellaji)
// + kosinipohjainen sointupisteytys ja Viterbi-tasoitus. Portti Mac-version ChordAnalyzer.swift:stä.

import type { Analysis, ChordSegment } from './types'

export const SR = 22050
const N = 8192
const HOP = 4096
const LOG2N = 13

const MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
const MINOR = [6.33, 2.68, 3.52, 5.38, 2.6, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

// --- FFT (radix-2) ---
const cosT = new Float64Array(N / 2)
const sinT = new Float64Array(N / 2)
const rev = new Uint16Array(N)
for (let i = 0; i < N / 2; i++) {
  cosT[i] = Math.cos((2 * Math.PI * i) / N)
  sinT[i] = -Math.sin((2 * Math.PI * i) / N)
}
for (let i = 0; i < N; i++) {
  let r = 0
  for (let b = 0; b < LOG2N; b++) if (i & (1 << b)) r |= 1 << (LOG2N - 1 - b)
  rev[i] = r
}

function fft(re: Float64Array, im: Float64Array): void {
  for (let i = 0; i < N; i++) {
    const j = rev[i]
    if (j > i) {
      const tr = re[i]
      re[i] = re[j]
      re[j] = tr
      const ti = im[i]
      im[i] = im[j]
      im[j] = ti
    }
  }
  for (let size = 2; size <= N; size <<= 1) {
    const half = size >> 1
    const step = N / size
    for (let start = 0; start < N; start += size) {
      for (let k = 0; k < half; k++) {
        const c = cosT[k * step]
        const s = sinT[k * step]
        const a = start + k
        const b = a + half
        const tr = re[b] * c - im[b] * s
        const ti = re[b] * s + im[b] * c
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] += tr
        im[a] += ti
      }
    }
  }
}

// --- Sointumallit ---
const WEIGHTS: Record<number, number>[] = [
  { 0: 1.0, 4: 0.85, 7: 0.9 },
  { 0: 1.0, 3: 0.85, 7: 0.9 },
  { 0: 1.0, 4: 0.8, 7: 0.85, 10: 0.6 },
  { 0: 1.0, 3: 0.8, 7: 0.85, 10: 0.6 }
]
const BIAS = [0, 0, -0.04, -0.04]

function buildTemplates(): Float64Array[] {
  const out: Float64Array[] = []
  for (let q = 0; q < 4; q++) {
    for (let root = 0; root < 12; root++) {
      const t = new Float64Array(12)
      for (const [iv, w] of Object.entries(WEIGHTS[q])) t[(root + Number(iv)) % 12] = w
      let n = 0
      for (let i = 0; i < 12; i++) n += t[i] * t[i]
      n = Math.sqrt(n)
      for (let i = 0; i < 12; i++) t[i] /= n
      out.push(t)
    }
  }
  return out
}
const TEMPLATES = buildTemplates()

function corr(x: number[], y: number[]): number {
  const mx = x.reduce((a, b) => a + b, 0) / 12
  const my = y.reduce((a, b) => a + b, 0) / 12
  let sxy = 0
  let sxx = 0
  let syy = 0
  for (let i = 0; i < 12; i++) {
    sxy += (x[i] - mx) * (y[i] - my)
    sxx += (x[i] - mx) ** 2
    syy += (y[i] - my) ** 2
  }
  return sxx > 0 && syy > 0 ? sxy / Math.sqrt(sxx * syy) : 0
}

export function analyzeSamples(samples: Float32Array): Analysis | null {
  if (samples.length < N * 4) return null
  const frames = Math.floor((samples.length - N) / HOP) + 1

  const window = new Float64Array(N)
  for (let i = 0; i < N; i++) window[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / N)

  const kLo = Math.floor((100 * N) / SR) - 1
  const kHi = Math.ceil((2000 * N) / SR) + 1
  const nb = kHi - kLo + 1

  const re = new Float64Array(N)
  const im = new Float64Array(N)
  const mags = new Float64Array(nb)

  const peakStart = new Int32Array(frames + 1)
  const peakMidi: number[] = []
  const peakW: number[] = []

  for (let f = 0; f < frames; f++) {
    peakStart[f] = peakMidi.length
    const s = f * HOP
    for (let i = 0; i < N; i++) {
      re[i] = samples[s + i] * window[i]
      im[i] = 0
    }
    fft(re, im)
    for (let j = 0; j < nb; j++) {
      const k = kLo + j
      mags[j] = Math.hypot(re[k], im[k])
    }
    for (let j = 1; j < nb - 1; j++) {
      const b = mags[j]
      const a = mags[j - 1]
      const c = mags[j + 1]
      if (b > a && b >= c && b > 1e-6) {
        const denom = a - 2 * b + c
        const delta = denom !== 0 ? (0.5 * (a - c)) / denom : 0
        const freq = ((kLo + j + delta) * SR) / N
        peakMidi.push(12 * Math.log2(freq / 440) + 69)
        peakW.push(Math.sqrt(b))
      }
    }
  }
  peakStart[frames] = peakMidi.length

  // Viritys
  let sc = 0
  let ss = 0
  for (let i = 0; i < peakMidi.length; i++) {
    const dev = peakMidi[i] - Math.round(peakMidi[i])
    sc += peakW[i] * Math.cos(2 * Math.PI * dev)
    ss += peakW[i] * Math.sin(2 * Math.PI * dev)
  }
  const tuning = Math.atan2(ss, sc) / (2 * Math.PI)

  // Kroma
  const chroma = new Float64Array(frames * 12)
  const energy = new Float64Array(frames)
  for (let f = 0; f < frames; f++) {
    for (let i = peakStart[f]; i < peakStart[f + 1]; i++) {
      const pc = (((Math.round(peakMidi[i] - tuning) % 12) + 12) % 12) as number
      chroma[f * 12 + pc] += peakW[i]
      energy[f] += peakW[i]
    }
  }

  // Pehmennys + normalisointi
  const smooth = new Float64Array(frames * 12)
  for (let f = 0; f < frames; f++) {
    const a = Math.max(0, f - 1)
    const b = Math.min(frames - 1, f + 1)
    for (let g = a; g <= b; g++) for (let p = 0; p < 12; p++) smooth[f * 12 + p] += chroma[g * 12 + p]
    let norm = 0
    for (let p = 0; p < 12; p++) norm += smooth[f * 12 + p] ** 2
    norm = Math.sqrt(norm)
    if (norm > 0) for (let p = 0; p < 12; p++) smooth[f * 12 + p] /= norm
  }

  // Sävellaji
  const mean = new Array<number>(12).fill(0)
  for (let f = 0; f < frames; f++) {
    let norm = 0
    for (let p = 0; p < 12; p++) norm += chroma[f * 12 + p] ** 2
    norm = Math.sqrt(norm)
    if (norm > 0) for (let p = 0; p < 12; p++) mean[p] += chroma[f * 12 + p] / norm
  }
  let best = { root: 0, minor: false, c: -2 }
  for (let root = 0; root < 12; root++) {
    const rot = Array.from({ length: 12 }, (_, i) => mean[(i + root) % 12])
    const cm = corr(rot, MAJOR)
    const cn = corr(rot, MINOR)
    if (cm > best.c) best = { root, minor: false, c: cm }
    if (cn > best.c) best = { root, minor: true, c: cn }
  }

  // Soinnut: Viterbi
  const sorted = Array.from(energy).sort((a, b) => a - b)
  const silent = sorted[Math.floor(sorted.length / 2)] * 0.08
  const S = 49
  const penalty = 0.45
  const emission = (f: number, s: number): number => {
    if (energy[f] < silent) return s === 48 ? 1 : 0
    if (s === 48) return 0.2
    const t = TEMPLATES[s]
    let d = 0
    for (let p = 0; p < 12; p++) d += smooth[f * 12 + p] * t[p]
    return d + BIAS[Math.floor(s / 12)]
  }
  let score = new Float64Array(S)
  for (let s = 0; s < S; s++) score[s] = emission(0, s)
  const back = new Uint8Array(frames * S)
  for (let f = 1; f < frames; f++) {
    let bestPrev = -Infinity
    let arg = 0
    for (let s = 0; s < S; s++) {
      if (score[s] > bestPrev) {
        bestPrev = score[s]
        arg = s
      }
    }
    const next = new Float64Array(S)
    const jump = bestPrev - penalty
    for (let s = 0; s < S; s++) {
      if (score[s] >= jump) {
        next[s] = score[s] + emission(f, s)
        back[f * S + s] = s
      } else {
        next[s] = jump + emission(f, s)
        back[f * S + s] = arg
      }
    }
    score = next
  }
  let state = 0
  let bestFinal = -Infinity
  for (let s = 0; s < S; s++) {
    if (score[s] > bestFinal) {
      bestFinal = score[s]
      state = s
    }
  }
  const path = new Array<number>(frames)
  for (let f = frames - 1; f >= 0; f--) {
    path[f] = state
    state = back[f * S + state]
  }

  // Segmentit
  const hopSec = HOP / SR
  const total = samples.length / SR
  const segments: ChordSegment[] = []
  let startFrame = 0
  for (let f = 1; f <= frames; f++) {
    if (f === frames || path[f] !== path[startFrame]) {
      const start = startFrame === 0 ? 0 : startFrame * hopSec + N / 2 / SR - hopSec / 2
      const end = f === frames ? total : f * hopSec + N / 2 / SR - hopSec / 2
      segments.push({ start, end, state: path[startFrame] })
      startFrame = f
    }
  }
  return { keyRoot: best.root, keyMinor: best.minor, keyConfidence: best.c, segments }
}
