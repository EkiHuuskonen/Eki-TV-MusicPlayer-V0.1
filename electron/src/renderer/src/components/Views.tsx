import { useEffect, useMemo, useState } from 'react'
import { buildTree, useStore } from '../store'
import { albumDetail } from '../sources'
import { albumThumb, albumSourceLabel, detailsUrl, sourceLabel, thumbUrl } from '../util'
import type { AlbumItem, ItemDetail, Track } from '../types'
import { Cover, TrackList } from './TrackList'
import { allDownloadItems } from '../download'

function DownloadAllButton({ tracks, name }: { tracks: Track[]; name: string }): React.JSX.Element {
  const openMenu = useStore((s) => s.openMenu)
  return (
    <button
      onClick={(e) => {
        e.stopPropagation()
        const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
        openMenu(r.left, r.bottom + 4, allDownloadItems(tracks, name))
      }}
    >
      ⭳ Lataa kaikki ▾
    </button>
  )
}

function AddToPlaylistButton({ tracks, label }: { tracks: Track[]; label: string }): React.JSX.Element {
  const openMenu = useStore((s) => s.openMenu)
  return (
    <button
      onClick={(e) => {
        e.stopPropagation()
        const st = useStore.getState()
        const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
        openMenu(r.left, r.bottom + 4, [
          ...st.playlists.map((p) => ({
            label: p.name,
            onClick: () => useStore.getState().addToPlaylist(p.id, tracks)
          })),
          {
            label: 'Uusi soittolista…',
            onClick: () =>
              useStore.getState().openDialog({
                title: 'Uusi soittolista',
                value: 'Uusi soittolista',
                okLabel: 'Luo',
                onOk: (v) => useStore.getState().createPlaylist(v, tracks)
              })
          }
        ])
      }}
    >
      {label} ▾
    </button>
  )
}

// ---------- Albumi hausta ----------

export function AlbumView({ item }: { item: AlbumItem }): React.JSX.Element {
  const play = useStore((s) => s.play)
  const setView = useStore((s) => s.setView)
  const setFavorites = useStore((s) => s.setFavorites)
  const favorites = useStore((s) => s.favorites)
  const [detail, setDetail] = useState<ItemDetail | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    setDetail(null)
    setError(null)
    albumDetail(item)
      .then((d) => !cancel && setDetail(d))
      .catch((e) => !cancel && setError(`Lataus epäonnistui: ${e instanceof Error ? e.message : String(e)}`))
    return () => {
      cancel = true
    }
  }, [item])

  const tracks = detail?.tracks ?? []
  const allFav = useMemo(() => {
    const ids = new Set(favorites.map((f) => `${f.source ?? ''}|${f.itemID}|${f.file}`))
    return tracks.length > 0 && tracks.every((t) => ids.has(`${t.source ?? ''}|${t.itemID}|${t.file}`))
  }, [favorites, tracks])

  return (
    <div className="page">
      <div className="back-bar">
        <button onClick={() => setView({ kind: 'search' })}>‹ Takaisin hakuun</button>
      </div>
      <div className="album-head">
        <Cover url={albumThumb(item)} size={130} round={10} />
        <div className="grow">
          <span className="badge">ALBUMI</span>
          <h1>{item.title}</h1>
          {item.creator && <div className="muted">{item.creator}</div>}
          {detail?.licenseURL ? (
            <a href={detail.licenseURL} target="_blank" rel="noreferrer" className="small">
              Lisenssi
            </a>
          ) : (
            <div className="small muted">Lähde: {albumSourceLabel(item)}</div>
          )}
          {tracks.length > 0 && (
            <div className="actions">
              <button className="primary" onClick={() => play(tracks)}>
                ▶ Soita kaikki
              </button>
              <button className={allFav ? 'fav-on' : ''} onClick={() => setFavorites(tracks, !allFav)}>
                {allFav ? '♥ Albumi suosikeissa' : '♡ Lisää albumi suosikkeihin'}
              </button>
              <AddToPlaylistButton tracks={tracks} label="Lisää kaikki soittolistalle" />
              <DownloadAllButton tracks={tracks} name={[item.creator, item.title].filter(Boolean).join(' - ')} />
            </div>
          )}
        </div>
      </div>
      <div className="scroll">
        {!detail && !error && <div className="center muted">Ladataan…</div>}
        {error && <div className="note">{error}</div>}
        {detail && tracks.length === 0 && <div className="center muted">Tässä julkaisussa ei ole soitettavia MP3-kappaleita.</div>}
        {tracks.length > 0 && <TrackList tracks={tracks} />}
      </div>
    </div>
  )
}

// ---------- Suosikit ----------

export function FavoritesView(): React.JSX.Element {
  const favorites = useStore((s) => s.favorites)
  const play = useStore((s) => s.play)
  const removeFavoriteAt = useStore((s) => s.removeFavoriteAt)
  return (
    <div className="page">
      <div className="page-head">
        <h1>Suosikit</h1>
        {favorites.length > 0 && (
          <div className="actions">
            <DownloadAllButton tracks={favorites} name="Suosikit" />
            <button className="primary" onClick={() => play(favorites)}>
              ▶ Soita
            </button>
          </div>
        )}
      </div>
      <div className="scroll">
        {favorites.length === 0 ? (
          <div className="center muted">Ei suosikkeja. Lisää kappale sydänpainikkeella tai hiiren oikealla painikkeella.</div>
        ) : (
          <TrackList tracks={favorites} onRemove={removeFavoriteAt} />
        )}
      </div>
    </div>
  )
}

// ---------- Soittolista ----------

export function PlaylistView({ id }: { id: string }): React.JSX.Element {
  const p = useStore((s) => s.playlists.find((x) => x.id === id))
  const play = useStore((s) => s.play)
  const remove = useStore((s) => s.removeFromPlaylist)
  if (!p) return <div className="center muted">Soittolistaa ei löydy.</div>
  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>{p.name}</h1>
          <div className="muted">{p.tracks.length} kappaletta</div>
        </div>
        {p.tracks.length > 0 && (
          <div className="actions">
            <DownloadAllButton tracks={p.tracks} name={p.name} />
            <button className="primary" onClick={() => play(p.tracks)}>
              ▶ Soita
            </button>
          </div>
        )}
      </div>
      <div className="scroll">
        {p.tracks.length === 0 ? (
          <div className="center muted">Tyhjä soittolista. Lisää kappaleita hausta hiiren oikealla painikkeella.</div>
        ) : (
          <TrackList tracks={p.tracks} onRemove={(i) => remove(id, i)} />
        )}
      </div>
    </div>
  )
}

// ---------- Kirjaston artisti / albumi ----------

export function LibraryTracksView({ artist, album }: { artist: string; album: string | null }): React.JSX.Element {
  const favorites = useStore((s) => s.favorites)
  const play = useStore((s) => s.play)
  const tree = useMemo(() => buildTree(favorites), [favorites])
  const a = tree.find((x) => x.name === artist)
  const tracks = album == null ? (a?.albums.flatMap((x) => x.tracks) ?? []) : (a?.albums.find((x) => x.title === album)?.tracks ?? [])
  if (tracks.length === 0) return <div className="center muted">Tämä kohta on tyhjä kirjastossa.</div>
  return (
    <div className="page">
      <div className="album-head">
        <Cover url={thumbUrl(tracks[0])} size={96} round={10} />
        <div className="grow">
          <h1>{album ?? artist}</h1>
          <div className="muted">{album == null ? 'Kaikki kirjaston kappaleet' : artist}</div>
          <div className="small muted">{tracks.length} kappaletta</div>
          <div className="actions">
            <button className="primary" onClick={() => play(tracks)}>
              ▶ Soita
            </button>
            <DownloadAllButton tracks={tracks} name={album ? `${artist} - ${album}` : artist} />
          </div>
        </div>
      </div>
      <div className="scroll">
        <TrackList tracks={tracks} />
      </div>
    </div>
  )
}

// ---------- Nyt soi ----------

export function NowPlayingView(): React.JSX.Element {
  const t = useStore((s) => s.queue[s.index])
  const queue = useStore((s) => s.queue)
  const openLink = (u: string): void => void window.api.openExternal(u)
  if (!t) return <div className="center muted">Ei soitettavaa. Valitse kappale hausta, suosikeista tai soittolistalta.</div>
  const link = detailsUrl(t)
  return (
    <div className="page">
      <div className="album-head">
        <Cover url={thumbUrl(t)} size={170} round={12} />
        <div className="grow">
          <div className="small muted">NYT SOI</div>
          <h1>{t.title}</h1>
          {t.artist && <div className="big muted">{t.artist}</div>}
          {t.albumTitle && <div className="muted">Julkaisu: {t.albumTitle}</div>}
          <div className="muted">Lähde: {sourceLabel(t)}</div>
          {t.license && <div className="small muted">Lisenssi: {t.license}</div>}
          {link && (
            <div className="actions">
              <button onClick={() => openLink(link)}>Avaa lähdesivu ↗</button>
            </div>
          )}
        </div>
      </div>
      <h2 className="pad">Soittojono</h2>
      <div className="scroll">
        <TrackList tracks={queue} />
      </div>
    </div>
  )
}
