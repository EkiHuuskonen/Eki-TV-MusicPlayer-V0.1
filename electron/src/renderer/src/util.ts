import type { AlbumItem, Analysis, ChordSegment, SourceId, Track } from './types'

export const isLive = (t: Track): boolean => t.source === 'radio'

export const trackId = (t: Track): string => (t.source ? `${t.source}:${t.itemID}` : `${t.itemID}/${t.file}`)

export function trackUrl(t: Track): string {
  if (t.streamString) return t.streamString
  const enc = t.file.split('/').map(encodeURIComponent).join('/')
  return `https://archive.org/download/${t.itemID}/${enc}`
}

export function thumbUrl(t: Track): string | undefined {
  if (t.artworkString) return t.artworkString
  return t.source ? undefined : `https://archive.org/services/img/${t.itemID}`
}

export function detailsUrl(t: Track): string | undefined {
  if (t.pageString) return t.pageString
  return t.source ? undefined : `https://archive.org/details/${t.itemID}`
}

export function albumThumb(a: AlbumItem): string {
  return a.artworkString ?? `https://archive.org/services/img/${a.id}`
}

export const sourceLabel = (t: Track): string =>
  ({ audius: 'Audius', ccmixter: 'ccMixter', openverse: 'Openverse', radio: 'Radio' } as Record<string, string>)[
    t.source ?? ''
  ] ?? 'Internet Archive'

export const albumSourceLabel = (a: AlbumItem): string => (a.source === 'audius' ? 'Audius' : 'Internet Archive')

export const SOURCE_TITLES: Record<SourceId, string> = {
  all: 'Kaikki lähteet',
  archive: 'Internet Archive',
  audius: 'Audius',
  ccmixter: 'ccMixter',
  openverse: 'Openverse (Jamendo ym.)',
  radio: 'Nettiradiot'
}

export function formatTime(sec: number): string {
  if (!isFinite(sec) || sec <= 0) return '0:00'
  const s = Math.floor(sec)
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

// --- Nuottien nimet ---

const SHARPS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
const FLATS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']
const SUFFIX = ['', 'm', '7', 'm7']
const INTERVALS = [
  [0, 4, 7],
  [0, 3, 7],
  [0, 4, 7, 10],
  [0, 3, 7, 10]
]

export function noteName(pc: number, flats: boolean, finnish: boolean): string {
  let n = (flats ? FLATS : SHARPS)[((pc % 12) + 12) % 12]
  if (finnish) {
    if (n === 'B') n = 'H'
    else if (n === 'Bb') n = 'B'
  }
  return n
}

export const useFlats = (a: Analysis): boolean =>
  a.keyMinor ? [2, 7, 0, 5, 10, 3].includes(a.keyRoot) : [5, 10, 3, 8, 1, 6].includes(a.keyRoot)

export const isNoChord = (s: ChordSegment): boolean => s.state >= 48

export function chordName(s: ChordSegment, flats: boolean, finnish: boolean): string {
  if (isNoChord(s)) return '–'
  return noteName(s.state % 12, flats, finnish) + SUFFIX[Math.floor(s.state / 12)]
}

export function chordNotes(s: ChordSegment, flats: boolean, finnish: boolean): string {
  if (isNoChord(s)) return ''
  const root = s.state % 12
  return INTERVALS[Math.floor(s.state / 12)].map((i) => noteName(root + i, flats, finnish)).join(' – ')
}

export function keyName(root: number, minor: boolean, flats: boolean, finnish: boolean): string {
  const n = noteName(root, flats, finnish)
  return finnish ? n + (minor ? '-molli' : '-duuri') : n + (minor ? ' minor' : ' major')
}

export function segmentIndexAt(a: Analysis, t: number): number {
  let lo = 0
  let hi = a.segments.length - 1
  if (hi < 0) return -1
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2)
    if (a.segments[mid].start <= t) lo = mid
    else hi = mid - 1
  }
  return lo
}

export const uuid = (): string => crypto.randomUUID()
