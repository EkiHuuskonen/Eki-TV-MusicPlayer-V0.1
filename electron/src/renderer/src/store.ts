import { create } from 'zustand'
import { COMBINED, fetchSource } from './sources'
import { SR } from './analyzer'
import { SOURCE_TITLES, detailsUrl, isLive, thumbUrl, trackId, trackUrl, uuid } from './util'
import type { AlbumItem, Analysis, Playlist, SourceId, Track } from './types'

export type View =
  | { kind: 'search' }
  | { kind: 'now' }
  | { kind: 'favorites' }
  | { kind: 'playlist'; id: string }
  | { kind: 'libArtist'; artist: string }
  | { kind: 'libAlbum'; artist: string; album: string }
  | { kind: 'album'; item: AlbumItem }

export type ChordState =
  | { kind: 'idle' }
  | { kind: 'loading'; msg: string }
  | { kind: 'failed'; msg: string }
  | { kind: 'done'; analysis: Analysis }

export interface SearchState {
  query: string
  source: SourceId
  items: AlbumItem[]
  tracks: Track[]
  page: number
  loading: boolean
  canMore: boolean
  notes: string[]
  reqId: number
}

export interface MenuItem {
  label: string
  onClick: () => void
  separator?: boolean
}

export interface DialogState {
  title: string
  value: string
  okLabel: string
  onOk: (value: string) => void
}

interface State {
  view: View
  setView: (v: View) => void

  // soitin
  queue: Track[]
  index: number
  playing: boolean
  currentTime: number
  duration: number
  volume: number
  muted: boolean
  shuffle: boolean
  play: (tracks: Track[], start?: number) => void
  toggle: () => void
  next: () => void
  prev: () => void
  seek: (t: number) => void
  setVolume: (v: number) => void
  changeVolume: (d: number) => void
  toggleMute: () => void
  toggleShuffle: () => void

  // kirjasto
  favorites: Track[]
  playlists: Playlist[]
  isFavorite: (t: Track) => boolean
  toggleFavorite: (t: Track) => void
  setFavorites: (tracks: Track[], on: boolean) => void
  removeFavoriteAt: (i: number) => void
  createPlaylist: (name: string, tracks?: Track[]) => string
  addToPlaylist: (id: string, tracks: Track[]) => void
  removeFromPlaylist: (id: string, i: number) => void
  renamePlaylist: (id: string, name: string) => void
  deletePlaylist: (id: string) => void

  // haku
  search: SearchState
  setQuery: (q: string) => void
  setSource: (s: SourceId) => void
  runSearch: (reset: boolean) => Promise<void>

  // soinnut
  chord: ChordState
  finnish: boolean
  setFinnish: (f: boolean) => void

  // käyttöliittymä
  menu: { x: number; y: number; items: MenuItem[] } | null
  openMenu: (x: number, y: number, items: MenuItem[]) => void
  closeMenu: () => void
  dialog: DialogState | null
  openDialog: (d: DialogState) => void
  closeDialog: () => void
  showChords: boolean
  toggleChords: () => void
  playError: string | null
}

const audio = new Audio()
audio.preload = 'auto'

const lsGet = (k: string): string | null => {
  try {
    return localStorage.getItem(k)
  } catch {
    return null
  }
}
const lsSet = (k: string, v: string): void => {
  try {
    localStorage.setItem(k, v)
  } catch {
    /* ei väliä */
  }
}

let saveTimer: ReturnType<typeof setTimeout> | undefined
function scheduleSave(get: () => State): void {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    const { favorites, playlists } = get()
    void window.api.saveLibrary({ favorites, playlists })
  }, 300)
}

// ---------- Sointuanalyysi ----------

let worker: Worker | null = null
let jobSeq = 0
const pending = new Map<number, (m: { result?: Analysis | null; error?: string }) => void>()
const analysisCache = new Map<string, Analysis>()
let analysisToken = 0

function getWorker(): Worker {
  if (!worker) {
    worker = new Worker(new URL('./analyzer.worker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = (e: MessageEvent<{ id: number; result?: Analysis | null; error?: string }>) => {
      pending.get(e.data.id)?.(e.data)
      pending.delete(e.data.id)
    }
  }
  return worker
}

async function analyzeTrack(track: Track, set: (p: Partial<State>) => void): Promise<void> {
  const token = ++analysisToken
  if (isLive(track)) {
    set({ chord: { kind: 'failed', msg: 'Radiolähetyksiä ei voi analysoida. Sävellaji ja soinnut tunnistetaan vain tiedostoista.' } })
    return
  }
  const cached = analysisCache.get(trackId(track))
  if (cached) {
    set({ chord: { kind: 'done', analysis: cached } })
    return
  }
  set({ chord: { kind: 'loading', msg: 'Ladataan kappaletta…' } })
  try {
    const r = await window.api.getAudio(trackUrl(track), 80_000_000)
    if (token !== analysisToken) return
    if (!r.ok || !r.data) {
      set({
        chord: {
          kind: 'failed',
          msg: r.tooLarge ? 'Kappale on liian pitkä (yli 80 Mt) analysoitavaksi.' : 'Kappaleen lataus analyysia varten epäonnistui.'
        }
      })
      return
    }
    set({ chord: { kind: 'loading', msg: 'Analysoidaan sävellajia ja sointuja…' } })
    const ctx = new OfflineAudioContext(1, 1, SR)
    const ab = r.data.buffer.slice(r.data.byteOffset, r.data.byteOffset + r.data.byteLength) as ArrayBuffer
    const buf = await ctx.decodeAudioData(ab)
    if (token !== analysisToken) return
    const len = Math.min(buf.length, SR * 600)
    const samples = new Float32Array(len)
    for (let c = 0; c < buf.numberOfChannels; c++) {
      const ch = buf.getChannelData(c)
      for (let i = 0; i < len; i++) samples[i] += ch[i] / buf.numberOfChannels
    }
    const id = ++jobSeq
    const msg = await new Promise<{ result?: Analysis | null; error?: string }>((resolve) => {
      pending.set(id, resolve)
      getWorker().postMessage({ id, samples }, [samples.buffer])
    })
    if (token !== analysisToken) return
    if (msg.error || !msg.result) {
      set({ chord: { kind: 'failed', msg: msg.error ? `Analyysi epäonnistui: ${msg.error}` : 'Kappale on liian lyhyt analysoitavaksi.' } })
      return
    }
    analysisCache.set(trackId(track), msg.result)
    set({ chord: { kind: 'done', analysis: msg.result } })
  } catch (e) {
    if (token === analysisToken) set({ chord: { kind: 'failed', msg: `Analyysi epäonnistui: ${String(e)}` } })
  }
}

// ---------- Kirjasto: artisti → albumi ----------

export const artistKey = (t: Track): string => {
  if (isLive(t)) return 'Nettiradiot'
  const a = t.artist?.trim() ?? ''
  return a || 'Tuntematon artisti'
}
export const albumKey = (t: Track): string => {
  if (isLive(t)) return 'Radioasemat'
  return t.collection ?? (t.source ? undefined : t.albumTitle) ?? 'Yksittäiset kappaleet'
}
const sortKey = (s: string): string => {
  const l = s.toLowerCase()
  return l.startsWith('the ') ? l.slice(4) : l
}
const cmp = (a: string, b: string): number => sortKey(a).localeCompare(sortKey(b), 'fi', { numeric: true })

export interface LibAlbum {
  artist: string
  title: string
  tracks: Track[]
}
export interface LibArtist {
  name: string
  albums: LibAlbum[]
}

export function buildTree(favorites: Track[]): LibArtist[] {
  const map = new Map<string, Map<string, Track[]>>()
  for (const t of favorites) {
    const a = artistKey(t)
    const al = albumKey(t)
    if (!map.has(a)) map.set(a, new Map())
    const m = map.get(a)!
    if (!m.has(al)) m.set(al, [])
    m.get(al)!.push(t)
  }
  return [...map.entries()]
    .map(([name, albums]) => ({
      name,
      albums: [...albums.entries()]
        .map(([title, tracks]) => ({ artist: name, title, tracks }))
        .sort((x, y) => cmp(x.title, y.title))
    }))
    .sort((x, y) => cmp(x.name, y.name))
}

// ---------- Store ----------

export const useStore = create<State>()((set, get) => {
  const loadTrack = (): void => {
    const t = get().queue[get().index]
    if (!t) return
    audio.src = trackUrl(t)
    set({ currentTime: 0, duration: t.duration ?? 0, playError: null })
    void audio.play().catch((e) => set({ playError: String(e) }))
    updateMediaSession(t)
    void analyzeTrack(t, set)
  }

  return {
    view: { kind: 'search' },
    setView: (v) => set({ view: v }),

    queue: [],
    index: 0,
    playing: false,
    currentTime: 0,
    duration: 0,
    volume: Number(lsGet('volume') ?? 0.8),
    muted: false,
    shuffle: lsGet('shuffle') === '1',
    playError: null,

    play: (tracks, start = 0) => {
      if (!tracks[start]) return
      set({ queue: tracks, index: start })
      loadTrack()
    },
    toggle: () => {
      if (!get().queue[get().index]) return
      if (audio.paused) void audio.play()
      else audio.pause()
    },
    next: () => {
      const { queue, index, shuffle } = get()
      if (!queue.length) return
      if (shuffle && queue.length > 1) {
        let n = index
        while (n === index) n = Math.floor(Math.random() * queue.length)
        set({ index: n })
      } else if (index + 1 < queue.length) {
        set({ index: index + 1 })
      } else {
        audio.pause()
        audio.currentTime = 0
        return
      }
      loadTrack()
    },
    prev: () => {
      const { queue, index } = get()
      if (!queue.length) return
      if (audio.currentTime > 3 || index === 0) {
        audio.currentTime = 0
      } else {
        set({ index: index - 1 })
        loadTrack()
      }
    },
    seek: (t) => {
      if (isFinite(t)) audio.currentTime = t
      set({ currentTime: t })
    },
    setVolume: (v) => {
      const vol = Math.min(1, Math.max(0, v))
      audio.volume = vol
      if (vol > 0 && get().muted) {
        audio.muted = false
        set({ muted: false })
      }
      lsSet('volume', String(vol))
      set({ volume: vol })
    },
    changeVolume: (d) => get().setVolume(get().volume + d),
    toggleMute: () => {
      const m = !get().muted
      audio.muted = m
      set({ muted: m })
    },
    toggleShuffle: () => {
      const s = !get().shuffle
      lsSet('shuffle', s ? '1' : '0')
      set({ shuffle: s })
    },

    favorites: [],
    playlists: [],
    isFavorite: (t) => get().favorites.some((f) => trackId(f) === trackId(t)),
    toggleFavorite: (t) => {
      const id = trackId(t)
      const favs = get().favorites
      set({ favorites: favs.some((f) => trackId(f) === id) ? favs.filter((f) => trackId(f) !== id) : [t, ...favs] })
      scheduleSave(get)
    },
    setFavorites: (tracks, on) => {
      if (on) {
        const have = new Set(get().favorites.map(trackId))
        set({ favorites: [...tracks.filter((t) => !have.has(trackId(t))), ...get().favorites] })
      } else {
        const ids = new Set(tracks.map(trackId))
        set({ favorites: get().favorites.filter((f) => !ids.has(trackId(f))) })
      }
      scheduleSave(get)
    },
    removeFavoriteAt: (i) => {
      set({ favorites: get().favorites.filter((_, k) => k !== i) })
      scheduleSave(get)
    },
    createPlaylist: (name, tracks = []) => {
      const p: Playlist = { id: uuid(), name: name.trim() || 'Uusi soittolista', tracks }
      set({ playlists: [...get().playlists, p] })
      scheduleSave(get)
      return p.id
    },
    addToPlaylist: (id, tracks) => {
      set({
        playlists: get().playlists.map((p) => {
          if (p.id !== id) return p
          const have = new Set(p.tracks.map(trackId))
          return { ...p, tracks: [...p.tracks, ...tracks.filter((t) => !have.has(trackId(t)))] }
        })
      })
      scheduleSave(get)
    },
    removeFromPlaylist: (id, i) => {
      set({ playlists: get().playlists.map((p) => (p.id === id ? { ...p, tracks: p.tracks.filter((_, k) => k !== i) } : p)) })
      scheduleSave(get)
    },
    renamePlaylist: (id, name) => {
      if (!name.trim()) return
      set({ playlists: get().playlists.map((p) => (p.id === id ? { ...p, name: name.trim() } : p)) })
      scheduleSave(get)
    },
    deletePlaylist: (id) => {
      set({ playlists: get().playlists.filter((p) => p.id !== id) })
      const v = get().view
      if (v.kind === 'playlist' && v.id === id) set({ view: { kind: 'search' } })
      scheduleSave(get)
    },

    search: { query: '', source: 'all', items: [], tracks: [], page: 1, loading: false, canMore: false, notes: [], reqId: 0 },
    setQuery: (q) => set({ search: { ...get().search, query: q } }),
    setSource: (s) => set({ search: { ...get().search, source: s } }),
    runSearch: async (reset) => {
      const st = get().search
      const reqId = st.reqId + 1
      const page = reset ? 1 : st.page + 1
      const q = st.query.trim()
      const targets: SourceId[] = st.source === 'all' ? COMBINED : [st.source]
      set({
        search: { ...st, reqId, page, loading: true, ...(reset ? { items: [], tracks: [], notes: [] } : {}) }
      })

      const results = await Promise.all(
        targets.map(async (s) => {
          try {
            return { s, batch: await fetchSource(s, q, page), err: undefined as string | undefined }
          } catch (e) {
            return { s, batch: undefined, err: `${SOURCE_TITLES[s]}: ${e instanceof Error ? e.message : String(e)}` }
          }
        })
      )
      const cur = get().search
      if (cur.reqId !== reqId) return // uudempi haku on jo käynnissä

      const notes = [...cur.notes]
      let items = [...cur.items]
      let more = false
      const lists: Track[][] = []
      for (const r of results) {
        if (r.err) notes.push(r.err)
        if (!r.batch) continue
        items = items.concat(r.batch.items)
        lists.push(r.batch.tracks)
        if (r.batch.full) more = true
      }
      // Artistin omat albumit ryhmitellään listan alkuun
      const ql = q.toLowerCase()
      if (ql) {
        const m = (i: AlbumItem): boolean => (i.creator ?? '').toLowerCase().includes(ql)
        items = [...items.filter(m), ...items.filter((i) => !m(i))]
      }
      const known = new Set(cur.tracks.map(trackId))
      const tracks = [...cur.tracks]
      const longest = Math.max(0, ...lists.map((l) => l.length))
      for (let i = 0; i < longest; i++) {
        for (const l of lists) {
          if (i < l.length && !known.has(trackId(l[i]))) {
            known.add(trackId(l[i]))
            tracks.push(l[i])
          }
        }
      }
      set({ search: { ...cur, items, tracks, notes, canMore: more, loading: false } })
    },

    chord: { kind: 'idle' },
    finnish: lsGet('finnish') !== '0',
    setFinnish: (f) => {
      lsSet('finnish', f ? '1' : '0')
      set({ finnish: f })
    },

    menu: null,
    openMenu: (x, y, items) => set({ menu: { x, y, items } }),
    closeMenu: () => set({ menu: null }),
    dialog: null,
    openDialog: (d) => set({ dialog: d }),
    closeDialog: () => set({ dialog: null }),
    showChords: true,
    toggleChords: () => set({ showChords: !get().showChords })
  }
})

// ---------- Äänielementin tapahtumat ja Media Session ----------

function updateMediaSession(t: Track): void {
  if (!('mediaSession' in navigator)) return
  const art = thumbUrl(t)
  navigator.mediaSession.metadata = new MediaMetadata({
    title: t.title,
    artist: t.artist ?? '',
    album: t.albumTitle ?? '',
    artwork: art ? [{ src: art }] : []
  })
}

export function initPlayer(): void {
  audio.volume = useStore.getState().volume
  audio.addEventListener('timeupdate', () => useStore.setState({ currentTime: audio.currentTime }))
  audio.addEventListener('durationchange', () => {
    if (isFinite(audio.duration) && audio.duration > 0) useStore.setState({ duration: audio.duration })
  })
  audio.addEventListener('play', () => useStore.setState({ playing: true }))
  audio.addEventListener('pause', () => useStore.setState({ playing: false }))
  audio.addEventListener('ended', () => useStore.getState().next())
  audio.addEventListener('error', () => useStore.setState({ playing: false, playError: 'Kappaletta ei voitu toistaa.' }))

  if ('mediaSession' in navigator) {
    const ms = navigator.mediaSession
    ms.setActionHandler('play', () => useStore.getState().toggle())
    ms.setActionHandler('pause', () => useStore.getState().toggle())
    ms.setActionHandler('previoustrack', () => useStore.getState().prev())
    ms.setActionHandler('nexttrack', () => useStore.getState().next())
    ms.setActionHandler('seekto', (d) => {
      if (d.seekTime != null) useStore.getState().seek(d.seekTime)
    })
  }

  void window.api.loadLibrary().then((data) => {
    const d = data as { favorites?: Track[]; playlists?: Playlist[] } | null
    if (d) useStore.setState({ favorites: d.favorites ?? [], playlists: d.playlists ?? [] })
  })
}

export { detailsUrl }
