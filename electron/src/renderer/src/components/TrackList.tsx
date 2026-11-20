import { useState } from 'react'
import { useStore } from '../store'
import type { MenuItem } from '../store'
import { formatTime, isLive, sourceLabel, thumbUrl, trackId } from '../util'
import type { Track } from '../types'

export function Cover({ url, size, round = 6 }: { url?: string; size: number; round?: number }): React.JSX.Element {
  const [failed, setFailed] = useState(false)
  const style = { width: size, height: size, borderRadius: round }
  if (!url || failed) {
    return (
      <div className="cover placeholder" style={style}>
        ♪
      </div>
    )
  }
  return <img className="cover" style={style} src={url} alt="" onError={() => setFailed(true)} />
}

export function trackMenu(t: Track, tracks: Track[], index: number): MenuItem[] {
  const st = useStore.getState()
  const items: MenuItem[] = [
    { label: 'Soita', onClick: () => st.play(tracks, index) },
    {
      label: st.isFavorite(t) ? 'Poista suosikeista' : 'Lisää suosikkeihin',
      onClick: () => st.toggleFavorite(t)
    },
    { label: '', onClick: () => {}, separator: true }
  ]
  for (const p of st.playlists) {
    items.push({ label: `Lisää soittolistalle: ${p.name}`, onClick: () => useStore.getState().addToPlaylist(p.id, [t]) })
  }
  items.push({
    label: 'Uusi soittolista…',
    onClick: () =>
      useStore.getState().openDialog({
        title: 'Uusi soittolista',
        value: 'Uusi soittolista',
        okLabel: 'Luo',
        onOk: (v) => useStore.getState().createPlaylist(v, [t])
      })
  })
  return items
}

export function TrackRow({
  tracks,
  index,
  onRemove
}: {
  tracks: Track[]
  index: number
  onRemove?: (i: number) => void
}): React.JSX.Element {
  const t = tracks[index]
  const id = trackId(t)
  const current = useStore((s) => {
    const c = s.queue[s.index]
    return c ? trackId(c) === id : false
  })
  const playing = useStore((s) => s.playing)
  const fav = useStore((s) => s.favorites.some((f) => trackId(f) === id))
  const play = useStore((s) => s.play)
  const toggleFavorite = useStore((s) => s.toggleFavorite)
  const openMenu = useStore((s) => s.openMenu)

  const sub = [t.artist, t.source ? sourceLabel(t) : undefined].filter(Boolean).join(' · ')
  const thumb = t.source ? thumbUrl(t) : undefined

  return (
    <div
      className={`track-row ${current ? 'current' : ''}`}
      onDoubleClick={() => play(tracks, index)}
      onContextMenu={(e) => {
        e.preventDefault()
        openMenu(e.clientX, e.clientY, trackMenu(t, tracks, index))
      }}
    >
      <button className="num" onClick={() => play(tracks, index)} title="Soita">
        {current ? (playing ? '🔊' : '🔈') : index + 1}
      </button>
      {t.source && <Cover url={thumb} size={34} round={4} />}
      <div className="grow">
        <div className="title">{t.title}</div>
        {sub && <div className="sub">{sub}</div>}
      </div>
      <button
        className={`icon-btn heart ${fav ? 'on' : ''}`}
        onClick={() => toggleFavorite(t)}
        title={fav ? 'Poista suosikeista' : 'Lisää suosikkeihin'}
      >
        {fav ? '♥' : '♡'}
      </button>
      {isLive(t) ? (
        <span className="live">LIVE</span>
      ) : (
        t.duration != null && <span className="dur">{formatTime(t.duration)}</span>
      )}
      {onRemove && (
        <button className="icon-btn remove" onClick={() => onRemove(index)} title="Poista listalta">
          ✕
        </button>
      )}
    </div>
  )
}

export function TrackList({
  tracks,
  onRemove
}: {
  tracks: Track[]
  onRemove?: (i: number) => void
}): React.JSX.Element {
  return (
    <div className="track-list">
      {tracks.map((t, i) => (
        <TrackRow key={`${trackId(t)}#${i}`} tracks={tracks} index={i} onRemove={onRemove} />
      ))}
    </div>
  )
}
