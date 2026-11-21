import { useStore } from './store'
import type { MenuItem } from './store'
import { albumDetail } from './sources'
import { detailsUrl, isLive, sourceLabel, trackUrl } from './util'
import type { AlbumItem, Track } from './types'

export type DlFormat = 'best' | 'wav'
export const FORMAT_LABEL: Record<DlFormat, string> = { best: 'Paras laatu (alkuperäinen)', wav: 'WAV' }

export type Permission = { ok: true; note?: string } | { ok: false; message: string }

/** Saako kappaleen ladata? Radiota ei voi, Audiuksessa artisti päättää, muiden lähteiden lisenssi näytetään. */
export function permission(t: Track): Permission {
  if (isLive(t)) return { ok: false, message: 'Nettiradiota ei voi ladata.' }
  if (t.source === 'audius') {
    if (t.downloadable === false) return { ok: false, message: 'Artisti ei salli tämän kappaleen latausta Audiuksessa.' }
    return { ok: true }
  }
  if (!t.license || !t.license.trim()) return { ok: true, note: 'Lisenssi tuntematon: tarkista käyttöoikeudet ennen käyttöä.' }
  return { ok: true }
}

// ---------- Parhaan laadun valinta ----------

const LOSSLESS: Record<string, number> = { '24bit flac': 0, flac: 1, wave: 2, wav: 2, aiff: 3, 'apple lossless audio': 4 }

async function bestArchiveUrl(t: Track): Promise<string> {
  const fallback = trackUrl(t)
  try {
    const r = await window.api.getJson(`https://archive.org/metadata/${encodeURIComponent(t.itemID)}`)
    const files = ((r.json as { files?: { name: string; format?: string }[] } | null)?.files ?? [])
    const base = (s: string): string => s.replace(/\.[^./]+$/, '').toLowerCase()
    const want = base(t.file)
    let best: { rank: number; name: string } | null = null
    for (const f of files) {
      if (base(f.name) !== want) continue
      const rank = LOSSLESS[(f.format ?? '').toLowerCase()]
      if (rank !== undefined && (!best || rank < best.rank)) best = { rank, name: f.name }
    }
    if (!best) return fallback
    return `https://archive.org/download/${t.itemID}/${best.name.split('/').map(encodeURIComponent).join('/')}`
  } catch {
    return fallback
  }
}

async function audiusDownloadable(t: Track): Promise<boolean> {
  if (t.downloadable !== undefined) return t.downloadable
  const r = await window.api.getJson(`https://api.audius.co/v1/tracks/${t.itemID}?app_name=EkiTVMusicPlayer`)
  const d = (r.json as { data?: { is_downloadable?: boolean; download?: { is_downloadable?: boolean } } } | null)?.data
  return d?.is_downloadable ?? d?.download?.is_downloadable ?? false
}

/** Osoitteet paras ensin, varaosoite perässä. */
async function resolve(t: Track): Promise<string[]> {
  const p = permission(t)
  if (!p.ok) throw new Error(p.message)
  switch (t.source) {
    case 'audius':
      if (!(await audiusDownloadable(t))) throw new Error('Artisti ei salli tämän kappaleen latausta Audiuksessa.')
      // Alkuperäinen ensin; jos Audius vaatii kirjautumisen, varalla palvelun paras stream (320 kbps mp3)
      return [`https://api.audius.co/v1/tracks/${t.itemID}/download?app_name=EkiTVMusicPlayer`, trackUrl(t)]
    case 'ccmixter':
      return [t.downloadString, trackUrl(t)].filter((u): u is string => !!u)
    case undefined:
      return [await bestArchiveUrl(t), trackUrl(t)]
    default:
      return [trackUrl(t)]
  }
}

// ---------- Tiedostomuodot ----------

function extOf(url: string, contentType: string): string {
  const m = /\.([a-z0-9]{3,5})(?:\?|$)/i.exec(url.split('#')[0])
  const fromUrl = m?.[1].toLowerCase()
  if (fromUrl && ['mp3', 'flac', 'wav', 'aif', 'aiff', 'm4a', 'ogg', 'opus'].includes(fromUrl)) return fromUrl
  const map: Record<string, string> = {
    'audio/mpeg': 'mp3', 'audio/mp3': 'mp3', 'audio/flac': 'flac', 'audio/x-flac': 'flac', 'audio/wav': 'wav',
    'audio/x-wav': 'wav', 'audio/aiff': 'aiff', 'audio/x-aiff': 'aiff', 'audio/mp4': 'm4a', 'audio/x-m4a': 'm4a', 'audio/ogg': 'ogg'
  }
  return map[contentType.split(';')[0].trim().toLowerCase()] ?? 'mp3'
}

function qualityLabel(ext: string): string {
  switch (ext) {
    case 'flac': return 'FLAC (häviötön)'
    case 'wav': return 'WAV (häviötön)'
    case 'aif':
    case 'aiff': return 'AIFF (häviötön)'
    default: return ext.toUpperCase()
  }
}

/** Näytteenottotaajuus ja bittisyvyys tiedoston otsikosta, jotta WAV-muunnos ei muuta taajuutta. */
function sniff(d: Uint8Array): { rate?: number; bits?: number } {
  const dv = new DataView(d.buffer, d.byteOffset, d.byteLength)
  const tag = String.fromCharCode(d[0], d[1], d[2], d[3])
  if (tag === 'fLaC' && d.length > 22) {
    return { rate: (d[18] << 12) | (d[19] << 4) | (d[20] >> 4), bits: (((d[20] & 1) << 4) | (d[21] >> 4)) + 1 }
  }
  if (tag === 'RIFF' && d.length > 36) return { rate: dv.getUint32(24, true), bits: dv.getUint16(34, true) }
  // MP3: ohita ID3v2, etsi ensimmäinen kehys
  let i = 0
  if (tag.startsWith('ID3') && d.length > 10) i = 10 + (((d[6] & 0x7f) << 21) | ((d[7] & 0x7f) << 14) | ((d[8] & 0x7f) << 7) | (d[9] & 0x7f))
  for (; i + 4 < Math.min(d.length, 200_000); i++) {
    if (d[i] === 0xff && (d[i + 1] & 0xe0) === 0xe0) {
      const ver = (d[i + 1] >> 3) & 3 // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
      const idx = (d[i + 2] >> 2) & 3
      const tbl: Record<number, number[]> = { 3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000] }
      const rate = tbl[ver]?.[idx]
      if (rate) return { rate }
    }
  }
  return {}
}

/** Muuntaa äänitiedoston WAViksi dekoodaamalla sen selaimen omalla dekooderilla (mp3, flac, wav, m4a). */
async function toWav(data: Uint8Array): Promise<Uint8Array> {
  const info = sniff(data)
  const ctx = new OfflineAudioContext(2, 1, info.rate ?? 44100)   // dekoodaus tehdään tiedoston omalla taajuudella
  const copy = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer
  const ab = await ctx.decodeAudioData(copy)
  const ch = ab.numberOfChannels
  const frames = ab.length
  const bytes = (info.bits ?? 16) > 16 ? 3 : 2
  const out = new Uint8Array(44 + frames * ch * bytes)
  const dv = new DataView(out.buffer)
  const w = (o: number, s: string): void => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)) }
  w(0, 'RIFF'); dv.setUint32(4, 36 + frames * ch * bytes, true); w(8, 'WAVE'); w(12, 'fmt ')
  dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, ch, true)
  dv.setUint32(24, ab.sampleRate, true); dv.setUint32(28, ab.sampleRate * ch * bytes, true)
  dv.setUint16(32, ch * bytes, true); dv.setUint16(34, bytes * 8, true); w(36, 'data'); dv.setUint32(40, frames * ch * bytes, true)
  const chans = Array.from({ length: ch }, (_, c) => ab.getChannelData(c))
  let o = 44
  for (let i = 0; i < frames; i++) {
    for (let c = 0; c < ch; c++) {
      const x = Math.max(-1, Math.min(1, chans[c][i]))
      if (bytes === 2) { dv.setInt16(o, Math.round(x < 0 ? x * 0x8000 : x * 0x7fff), true); o += 2 }
      else {
        const v = Math.round(x < 0 ? x * 0x800000 : x * 0x7fffff)
        dv.setUint8(o, v & 0xff); dv.setUint8(o + 1, (v >> 8) & 0xff); dv.setUint8(o + 2, (v >> 16) & 0xff); o += 3
      }
    }
  }
  return out
}

const safeName = (s: string): string => {
  const c = s.replace(/[/\\:*?"<>|\u0000-\u001f]/g, '-').replace(/^[\s.-]+|[\s.-]+$/g, '')
  return (c || 'kappale').slice(0, 120)
}

interface Done { filename: string; track: Track; quality: string; note?: string }

async function downloadOne(t: Track, dir: string, sub: string | null, format: DlFormat, number?: number): Promise<Done> {
  const urls = await resolve(t)
  const r = await window.api.dlGet(urls)
  if (!r.ok || !r.data) throw new Error(r.error ?? 'lataus epäonnistui')
  const ext = extOf(r.url ?? urls[0], r.contentType ?? '')
  const base = (number ? String(number).padStart(2, '0') + ' ' : '') + safeName([t.artist, t.title].filter(Boolean).join(' - '))
  const note = permission(t).ok ? (permission(t) as { note?: string }).note : undefined
  if (format === 'wav' && ext !== 'wav') {
    try {
      const wav = await toWav(r.data)
      const path = await window.api.dlSave(dir, sub, base + '.wav', wav)
      return { filename: path.split(/[\\/]/).pop() ?? base + '.wav', track: t, quality: `WAV (muunnettu ${qualityLabel(ext)}:sta)`, note }
    } catch (e) {
      const path = await window.api.dlSave(dir, sub, `${base}.${ext}`, r.data)
      return {
        filename: path.split(/[\\/]/).pop() ?? base, track: t, quality: qualityLabel(ext),
        note: `WAV-muunnos ei onnistunut, tallennettiin alkuperäinen: ${e instanceof Error ? e.message : String(e)}`
      }
    }
  }
  const path = await window.api.dlSave(dir, sub, `${base}.${ext}`, r.data)
  return { filename: path.split(/[\\/]/).pop() ?? base, track: t, quality: qualityLabel(ext), note }
}

function infoText(title: string, done: Done[]): string {
  let s = `${title}\nLadattu Eki-TV MusicPlayer -sovelluksella ${new Date().toLocaleString('fi-FI')}\n\n`
  done.forEach((d, i) => {
    const t = d.track
    s += `${i + 1}. ${t.artist ? t.artist + ' – ' : ''}${t.title}\n`
    s += `   Tiedosto: ${d.filename} · Laatu: ${d.quality}\n`
    s += `   Lähde: ${sourceLabel(t)}${detailsUrl(t) ? ' · ' + detailsUrl(t) : ''}\n`
    s += `   Lisenssi: ${t.license && t.license.trim() ? t.license : 'tuntematon'}\n`
    if (d.note) s += `   Huomio: ${d.note}\n`
    s += '\n'
  })
  return s
}

let running = false

/** Lataa kappaleet käyttäjän valitsemaan kansioon. folderName != null: luodaan alikansio (albumi). */
export async function downloadTracks(all: Track[], folderName: string | null, format: DlFormat): Promise<void> {
  if (running) return
  const { setDl } = useStore.getState()
  const failed: string[] = []
  const tracks = all.filter((t) => {
    const p = permission(t)
    if (!p.ok) failed.push(`${t.title}: ${p.message}`)
    return p.ok
  })
  if (tracks.length === 0) {
    setDl({ busy: false, error: failed[0] ?? 'Ei ladattavia kappaleita.' })
    return
  }
  const last = localStorage.getItem('dl.dir') ?? undefined
  const dir = await window.api.chooseDir(last)
  if (!dir) return
  localStorage.setItem('dl.dir', dir)
  const sub = folderName ? safeName(folderName) : null
  running = true
  const done: Done[] = []
  try {
    for (let i = 0; i < tracks.length; i++) {
      const t = tracks[i]
      setDl({ busy: true, status: tracks.length > 1 ? `Ladataan ${i + 1}/${tracks.length}: ${t.title}` : `Ladataan: ${t.title}` })
      try {
        done.push(await downloadOne(t, dir, sub, format, folderName ? i + 1 : undefined))
      } catch (e) {
        failed.push(`${t.title}: ${e instanceof Error ? e.message : String(e)}`)
      }
    }
    if (done.length > 0) {
      const text = infoText(folderName ?? done[0].track.title, done)
      const infoName = folderName ? 'TIEDOT.txt' : done[0].filename.replace(/\.[^.]+$/, '') + ' (tiedot).txt'
      const infoPath = await window.api.dlSave(dir, sub, infoName, new TextEncoder().encode(text))
      void window.api.showItem(infoPath)
    }
    setDl({
      busy: false,
      status: done.length ? `Valmis: ${done.length} tiedostoa${failed.length ? `, ${failed.length} ohitettu` : ''}` : undefined,
      error: failed.length ? failed.join('\n') : undefined
    })
  } finally {
    running = false
  }
}

export async function downloadAlbumItem(item: AlbumItem, format: DlFormat): Promise<void> {
  useStore.getState().setDl({ busy: true, status: 'Haetaan kappalelista…' })
  try {
    const d = await albumDetail(item)
    useStore.getState().setDl(null)
    await downloadTracks(d.tracks, [item.creator, item.title].filter(Boolean).join(' - '), format)
  } catch (e) {
    useStore.getState().setDl({ busy: false, error: `Kappalelistan haku epäonnistui: ${e instanceof Error ? e.message : String(e)}` })
  }
}

// ---------- Valikot ----------

export function trackDownloadItems(t: Track): MenuItem[] {
  const p = permission(t)
  if (!p.ok) return [{ label: `Lataus ei sallittu: ${p.message}`, onClick: () => {} }]
  return (['best', 'wav'] as DlFormat[]).map((f) => ({ label: `Lataa: ${FORMAT_LABEL[f]}`, onClick: () => void downloadTracks([t], null, f) }))
}

export function allDownloadItems(tracks: Track[], name: string): MenuItem[] {
  return (['best', 'wav'] as DlFormat[]).map((f) => ({
    label: `Lataa kaikki: ${FORMAT_LABEL[f]}`,
    onClick: () => void downloadTracks(tracks, name, f)
  }))
}

export function albumItemDownloadItems(item: AlbumItem): MenuItem[] {
  return (['best', 'wav'] as DlFormat[]).map((f) => ({
    label: `Lataa albumi: ${FORMAT_LABEL[f]}`,
    onClick: () => void downloadAlbumItem(item, f)
  }))
}

// Automaattitestiä varten (ei vaikutusta normaalikäyttöön)
if (typeof localStorage !== 'undefined' && localStorage.getItem('ekitv.test') === '1') {
  ;(window as unknown as { __dl: unknown }).__dl = { downloadTracks, permission }
}
