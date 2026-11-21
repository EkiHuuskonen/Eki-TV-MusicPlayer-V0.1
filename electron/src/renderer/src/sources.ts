import type { AlbumItem, Batch, ItemDetail, SourceId, Track } from './types'

const PAGE = 20
export const COMBINED: SourceId[] = ['archive', 'audius', 'ccmixter', 'openverse']

async function getJSON<T>(url: string): Promise<T> {
  const r = await window.api.getJson(url)
  if (r.status === 429) throw new Error('liian monta hakua, yritä hetken kuluttua uudelleen')
  if (r.status !== 200 || r.json == null) throw new Error('palvelu ei vastannut odotetusti')
  return r.json as T
}

const flex = (v: unknown): string | undefined => {
  if (v == null) return undefined
  if (Array.isArray(v)) return v.map(String).join(', ')
  return String(v)
}

const https = (s?: string | null): string | undefined => {
  if (!s) return undefined
  return s.startsWith('http://') ? 'https://' + s.slice(7) : s
}

const qs = (params: [string, string][]): string =>
  params.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')

function parseClock(s?: string): number | undefined {
  if (!s) return undefined
  const parts = s.split(':').map(Number)
  if (parts.some((n) => Number.isNaN(n))) return undefined
  return parts.reduce((a, b) => a * 60 + b, 0)
}

// ================= Internet Archive =================

const ARCHIVE_BASE =
  'mediatype:audio AND format:MP3 AND collection:(opensource_audio OR netlabels OR 78rpm OR etree OR audio_music)'

async function archiveSearch(text: string, page: number, rows = 40, field?: string): Promise<AlbumItem[]> {
  const t = text.trim()
  const term = field ? `${field}:(${t})` : `(${t})`
  const q = t ? `${term} AND ${ARCHIVE_BASE}` : ARCHIVE_BASE
  const url =
    'https://archive.org/advancedsearch.php?' +
    qs([
      ['q', q],
      ['fl[]', 'identifier'],
      ['fl[]', 'title'],
      ['fl[]', 'creator'],
      ['sort[]', 'downloads desc'],
      ['rows', String(rows)],
      ['page', String(page)],
      ['output', 'json']
    ])
  const j = await getJSON<{ response: { docs: Record<string, unknown>[] } }>(url)
  return j.response.docs.map((d) => ({
    id: String(d.identifier),
    title: flex(d.title) ?? String(d.identifier),
    creator: flex(d.creator),
    source: 'archive' as const
  }))
}

function trackNumber(s?: string): number {
  if (!s) return Number.MAX_SAFE_INTEGER
  const n = parseInt(s.split('/')[0], 10)
  return Number.isNaN(n) ? Number.MAX_SAFE_INTEGER : n
}

export async function archiveDetails(id: string): Promise<ItemDetail> {
  const j = await getJSON<{
    metadata?: Record<string, unknown>
    files?: Record<string, unknown>[]
  }>(`https://archive.org/metadata/${encodeURIComponent(id)}`)
  const files = (j.files ?? []).filter((f) => String(f.format ?? '').includes('MP3'))
  const formats = new Set(files.map((f) => String(f.format)))
  const pick =
    ['VBR MP3', 'MP3', '192Kbps MP3', '128Kbps MP3', '64Kbps MP3'].find((f) => formats.has(f)) ?? [...formats][0]
  const chosen = files
    .filter((f) => f.format === pick)
    .sort((a, b) => {
      const d = trackNumber(flex(a.track)) - trackNumber(flex(b.track))
      return d !== 0 ? d : String(a.name).localeCompare(String(b.name), undefined, { numeric: true })
    })
  const meta = j.metadata ?? {}
  const albumArtist = flex(meta.creator)
  const albumTitle = flex(meta.title) ?? id
  const tracks: Track[] = chosen.map((f) => ({
    itemID: id,
    file: String(f.name),
    title: flex(f.title) ?? String(f.name).replace(/^.*\//, '').replace(/\.[^.]+$/, ''),
    artist: flex(f.creator) ?? albumArtist,
    duration: parseLength(flex(f.length)),
    albumTitle,
    license: flex(meta.licenseurl)
  }))
  return { title: albumTitle, creator: albumArtist, licenseURL: flex(meta.licenseurl), tracks }
}

function parseLength(s?: string): number | undefined {
  if (!s) return undefined
  const d = Number(s)
  if (!Number.isNaN(d)) return d
  return parseClock(s)
}

// ================= Audius =================

interface AudiusTrack {
  id: string
  title: string
  duration?: number
  user?: { name?: string }
  artwork?: Record<string, string> | null
  permalink?: string
  is_streamable?: boolean
  genre?: string
  is_downloadable?: boolean
  download?: { is_downloadable?: boolean } | null
}

function audiusTrack(t: AudiusTrack, album?: string): Track {
  return {
    itemID: t.id,
    file: '',
    title: t.title,
    artist: t.user?.name,
    duration: t.duration,
    albumTitle: album ?? t.genre,
    source: 'audius',
    streamString: `https://api.audius.co/v1/tracks/${t.id}/stream?app_name=EkiTVMusicPlayer`,
    artworkString: https(t.artwork?.['480x480']),
    pageString: t.permalink ? 'https://audius.co' + t.permalink : undefined,
    collection: album,
    downloadable: t.is_downloadable ?? t.download?.is_downloadable ?? undefined
  }
}

async function audiusAlbums(q: string): Promise<AlbumItem[]> {
  const app = 'EkiTVMusicPlayer'
  const users = await getJSON<{ data: { id: string; name?: string; album_count?: number }[] }>(
    'https://api.audius.co/v1/users/search?' +
      qs([
        ['query', q],
        ['app_name', app],
        ['limit', '5']
      ])
  )
  const artists = users.data.filter((u) => (u.album_count ?? 0) > 0).slice(0, 3)
  const lists = await Promise.all(
    artists.map(async (u) => {
      const r = await getJSON<{
        data: {
          id: string
          playlist_name: string
          track_count?: number
          user?: { name?: string }
          artwork?: Record<string, string> | null
        }[]
      }>(`https://api.audius.co/v1/users/${u.id}/albums?` + qs([['app_name', app], ['limit', '20']]))
      return r.data
        .filter((p) => (p.track_count ?? 0) > 0)
        .map<AlbumItem>((p) => ({
          id: `audius:${p.id}`,
          title: p.playlist_name,
          creator: p.user?.name ?? u.name,
          source: 'audius',
          artworkString: https(p.artwork?.['480x480']),
          trackCount: p.track_count
        }))
    })
  )
  return lists.flat()
}

export async function audiusAlbum(item: AlbumItem): Promise<ItemDetail> {
  const id = item.id.replace(/^audius:/, '')
  const r = await getJSON<{ data: AudiusTrack[] }>(
    `https://api.audius.co/v1/playlists/${id}/tracks?` + qs([['app_name', 'EkiTVMusicPlayer']])
  )
  const tracks = r.data.filter((t) => t.is_streamable !== false).map((t) => audiusTrack(t, item.title))
  return { title: item.title, creator: item.creator, tracks }
}

async function audius(q: string, page: number): Promise<Batch> {
  const common: [string, string][] = [
    ['app_name', 'EkiTVMusicPlayer'],
    ['limit', String(PAGE)],
    ['offset', String((page - 1) * PAGE)]
  ]
  const url = q
    ? 'https://api.audius.co/v1/tracks/search?' + qs([['query', q], ...common])
    : 'https://api.audius.co/v1/tracks/trending?' + qs(common)
  const albums = q && page === 1 ? audiusAlbums(q).catch(() => [] as AlbumItem[]) : Promise.resolve([] as AlbumItem[])
  const r = await getJSON<{ data: AudiusTrack[] }>(url)
  const tracks = r.data.filter((t) => t.is_streamable !== false).map((t) => audiusTrack(t))
  return { items: await albums, tracks, full: r.data.length >= PAGE }
}

// ================= ccMixter =================

interface CCItem {
  upload_id: number
  upload_name: string
  user_name?: string
  user_real_name?: string
  file_page_url?: string
  license_name?: string
  files?: { download_url?: string; file_format_info?: { ps?: string } | unknown[] }[]
}

/** Paras ladattava tiedosto: samasta miksauksesta häviötön (flac, wav, aiff) mp3:n sijaan. */
function bestCCFile(files: CCItem['files']): string | undefined {
  const urls = (files ?? []).map((f) => https(f.download_url)).filter((u): u is string => !!u)
  const mp3 = urls.find((u) => u.toLowerCase().endsWith('.mp3'))
  if (!mp3) return undefined
  const base = mp3.slice(0, -4).toLowerCase()
  for (const ext of ['flac', 'wav', 'aiff', 'aif']) {
    const m = urls.find((u) => u.toLowerCase() === `${base}.${ext}`)
    if (m) return m
  }
  return mp3
}

async function ccmixter(q: string, page: number): Promise<Batch> {
  const params: [string, string][] = [
    ['f', 'json'],
    ['search_type', 'all'],
    ['tags', 'mp3'],
    ['sort', 'rank'],
    ['limit', String(PAGE)],
    ['offset', String((page - 1) * PAGE)]
  ]
  if (q) params.push(['search', q])
  const r = await getJSON<CCItem[]>('https://ccmixter.org/api/query?' + qs(params))
  const tracks: Track[] = []
  for (const it of r) {
    const f = it.files?.find((x) => (x.download_url ?? '').toLowerCase().endsWith('.mp3'))
    const stream = https(f?.download_url)
    if (!f || !stream) continue
    const info = f.file_format_info as { ps?: string } | undefined
    tracks.push({
      itemID: String(it.upload_id),
      file: '',
      title: it.upload_name,
      artist: it.user_real_name ?? it.user_name,
      duration: parseClock(info && !Array.isArray(info) ? info.ps : undefined),
      albumTitle: 'ccMixter',
      source: 'ccmixter',
      streamString: stream,
      pageString: https(it.file_page_url),
      license: it.license_name?.split(/\s+/).filter(Boolean).join(' '),
      downloadString: bestCCFile(it.files)
    })
  }
  return { items: [], tracks, full: r.length >= PAGE }
}

// ================= Openverse (sis. Jamendon, Freesoundin, Wikimedian CC-musiikkia) =================

interface OVResult {
  id: string
  title?: string
  creator?: string
  url?: string
  foreign_landing_url?: string
  thumbnail?: string
  license?: string
  license_version?: string
  duration?: number
  filetype?: string
  source?: string
}

async function openverse(q: string, page: number): Promise<Batch> {
  const url =
    'https://api.openverse.org/v1/audio/?' +
    qs([
      ['q', q || 'music'],
      ['category', 'music'],
      ['page_size', String(PAGE)],
      ['page', String(page)]
    ])
  const r = await getJSON<{ results: OVResult[] }>(url)
  const bad = new Set(['ogg', 'oga', 'opus', 'webm'])
  const tracks: Track[] = []
  for (const t of r.results) {
    const stream = https(t.url)
    if (!stream || bad.has((t.filetype ?? '').toLowerCase())) continue
    tracks.push({
      itemID: t.id,
      file: '',
      title: t.title ?? 'Nimetön',
      artist: t.creator,
      duration: t.duration ? t.duration / 1000 : undefined,
      albumTitle: t.source ? t.source.charAt(0).toUpperCase() + t.source.slice(1) : undefined,
      source: 'openverse',
      streamString: stream,
      artworkString: https(t.thumbnail),
      pageString: https(t.foreign_landing_url),
      license: t.license ? `CC ${t.license.toUpperCase()}${t.license_version ? ' ' + t.license_version : ''}` : undefined
    })
  }
  return { items: [], tracks, full: r.results.length >= PAGE }
}

// ================= Nettiradiot (Radio Browser) =================

interface Station {
  stationuuid: string
  name: string
  url_resolved?: string
  homepage?: string
  favicon?: string
  codec?: string
  bitrate?: number
  tags?: string
  countrycode?: string
}

async function radioRequest(params: [string, string][]): Promise<Station[]> {
  let lastError: unknown = new Error('palvelu ei vastannut odotetusti')
  for (const host of ['de1', 'fi1', 'nl1', 'at1']) {
    try {
      return await getJSON<Station[]>(`https://${host}.api.radio-browser.info/json/stations/search?` + qs(params))
    } catch (e) {
      lastError = e
    }
  }
  throw lastError
}

async function radio(q: string, page: number): Promise<Batch> {
  const base: [string, string][] = [
    ['limit', String(PAGE)],
    ['offset', String((page - 1) * PAGE)],
    ['hidebroken', 'true'],
    ['order', 'clickcount'],
    ['reverse', 'true']
  ]
  let stations: Station[]
  if (!q) {
    stations = await radioRequest([...base, ['countrycode', 'FI']])
  } else {
    const [byName, byTag] = await Promise.all([
      radioRequest([...base, ['name', q]]).catch(() => [] as Station[]),
      radioRequest([...base, ['tag', q]]).catch(() => [] as Station[])
    ])
    const known = new Set(byName.map((s) => s.stationuuid))
    stations = [...byName, ...byTag.filter((s) => !known.has(s.stationuuid))]
  }
  const tracks: Track[] = []
  for (const s of stations) {
    if (!s.url_resolved || (s.codec ?? '').toUpperCase().includes('OGG')) continue
    const tags = (s.tags ?? '').split(',').filter(Boolean).slice(0, 3).join(', ')
    const subtitle = [s.countrycode, tags].filter(Boolean).join(' · ')
    const quality = [s.codec, s.bitrate ? `${s.bitrate} kbps` : undefined].filter(Boolean).join(' ')
    tracks.push({
      itemID: s.stationuuid,
      file: '',
      title: s.name.trim().slice(0, 50),
      artist: subtitle || undefined,
      albumTitle: quality || 'Radio',
      source: 'radio',
      streamString: s.url_resolved,
      artworkString: https(s.favicon),
      pageString: https(s.homepage)
    })
  }
  return { items: [], tracks, full: stations.length >= PAGE }
}

// ================= Yhteinen sisäänkäynti =================

export async function fetchSource(source: SourceId, query: string, page: number): Promise<Batch> {
  const q = query.trim()
  switch (source) {
    case 'archive': {
      if (q && page === 1) {
        // Artistin omat julkaisut ensin, sen jälkeen koko tekstihaku
        const [byArtist, all] = await Promise.all([
          archiveSearch(q, 1, 20, 'creator').catch(() => [] as AlbumItem[]),
          archiveSearch(q, 1)
        ])
        const known = new Set(byArtist.map((i) => i.id))
        return { items: [...byArtist, ...all.filter((i) => !known.has(i.id))], tracks: [], full: all.length >= 40 }
      }
      const items = await archiveSearch(q, page)
      return { items, tracks: [], full: items.length >= 40 }
    }
    case 'audius':
      return audius(q, page)
    case 'ccmixter':
      return ccmixter(q, page)
    case 'openverse':
      return openverse(q, page)
    case 'radio':
      return radio(q, page)
    default:
      return { items: [], tracks: [], full: false }
  }
}

export const albumDetail = (item: AlbumItem): Promise<ItemDetail> =>
  item.source === 'audius' ? audiusAlbum(item) : archiveDetails(item.id)
