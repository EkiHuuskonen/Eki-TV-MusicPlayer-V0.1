// Tietotyypit. Track/Playlist-muoto on yhteensopiva Mac-version library.json-tiedoston kanssa.

export interface Track {
  itemID: string
  file: string
  title: string
  artist?: string
  duration?: number
  albumTitle?: string
  /** puuttuu = Internet Archive; muuten audius | ccmixter | openverse | radio */
  source?: string
  streamString?: string
  artworkString?: string
  pageString?: string
  license?: string
  /** todellisen albumin nimi (Audius-albumit) */
  collection?: string
  /** parhaan laadun latausosoite, jos se tunnetaan jo haussa (ccMixter: flac/wav ennen mp3:a) */
  downloadString?: string
  /** Audius: saako kappaleen ladata (artistin valinta) */
  downloadable?: boolean
}

export interface AlbumItem {
  id: string
  title: string
  creator?: string
  source: 'archive' | 'audius'
  artworkString?: string
  trackCount?: number
}

export interface Playlist {
  id: string
  name: string
  tracks: Track[]
}

export interface ItemDetail {
  title: string
  creator?: string
  licenseURL?: string
  tracks: Track[]
}

export interface Batch {
  items: AlbumItem[]
  tracks: Track[]
  full: boolean
}

export type SourceId = 'all' | 'archive' | 'audius' | 'ccmixter' | 'openverse' | 'radio'

export interface ChordSegment {
  start: number
  end: number
  /** 0..47 = sointu (juuri + 12 * laatu), 48 = ei sointua */
  state: number
}

export interface Analysis {
  keyRoot: number
  keyMinor: boolean
  keyConfidence: number
  segments: ChordSegment[]
}

declare global {
  interface Window {
    api: import('../../preload/index').Api
  }
}
