import { useMemo, useState } from 'react'
import { buildTree, useStore } from '../store'
import { trackId } from '../util'

export default function Sidebar(): React.JSX.Element {
  const view = useStore((s) => s.view)
  const setView = useStore((s) => s.setView)
  const favorites = useStore((s) => s.favorites)
  const playlists = useStore((s) => s.playlists)
  const queue = useStore((s) => s.queue)
  const index = useStore((s) => s.index)
  const play = useStore((s) => s.play)
  const openMenu = useStore((s) => s.openMenu)
  const openDialog = useStore((s) => s.openDialog)
  const showChords = useStore((s) => s.showChords)
  const toggleChords = useStore((s) => s.toggleChords)

  const tree = useMemo(() => buildTree(favorites), [favorites])
  const sortedPlaylists = useMemo(
    () => [...playlists].sort((a, b) => a.name.localeCompare(b.name, 'fi', { numeric: true })),
    [playlists]
  )
  const [open, setOpen] = useState<Set<string>>(new Set())
  const toggle = (k: string): void => {
    const n = new Set(open)
    if (n.has(k)) n.delete(k)
    else n.add(k)
    setOpen(n)
  }
  const curId = queue[index] ? trackId(queue[index]) : null

  const newPlaylist = (): void =>
    openDialog({
      title: 'Uusi soittolista',
      value: '',
      okLabel: 'Luo',
      onOk: (v) => {
        const id = useStore.getState().createPlaylist(v)
        useStore.getState().setView({ kind: 'playlist', id })
      }
    })

  return (
    <aside className="sidebar">
      <div className="brand">
        <span className="logo">♫</span> Eki-TV <b>MusicPlayer</b>
      </div>

      <nav>
        <button className={`nav ${view.kind === 'search' || view.kind === 'album' ? 'active' : ''}`} onClick={() => setView({ kind: 'search' })}>
          🔍 Haku
        </button>
        <button className={`nav ${view.kind === 'now' ? 'active' : ''}`} onClick={() => setView({ kind: 'now' })}>
          ◉ Nyt soi
        </button>
        <button className={`nav ${view.kind === 'favorites' ? 'active' : ''}`} onClick={() => setView({ kind: 'favorites' })}>
          ♥ Suosikit
        </button>
      </nav>

      <div className="side-scroll">
        <div className="side-title">Kirjasto</div>
        {tree.length === 0 && (
          <div className="side-hint">Suosikkeihin lisätyt kappaleet ja albumit näkyvät tässä artisteittain ja albumeittain.</div>
        )}
        {tree.map((a) => {
          const ak = 'a:' + a.name
          return (
            <div key={ak}>
              <div className="tree-row">
                <button className="chev" onClick={() => toggle(ak)}>
                  {open.has(ak) ? '▾' : '▸'}
                </button>
                <button
                  className={`nav tree ${view.kind === 'libArtist' && view.artist === a.name ? 'active' : ''}`}
                  onClick={() => setView({ kind: 'libArtist', artist: a.name })}
                  title={a.name}
                >
                  🎤 {a.name}
                </button>
              </div>
              {open.has(ak) &&
                a.albums.map((al) => {
                  const alk = ak + '|' + al.title
                  return (
                    <div key={alk} className="indent">
                      <div className="tree-row">
                        <button className="chev" onClick={() => toggle(alk)}>
                          {open.has(alk) ? '▾' : '▸'}
                        </button>
                        <button
                          className={`nav tree ${view.kind === 'libAlbum' && view.artist === a.name && view.album === al.title ? 'active' : ''}`}
                          onClick={() => setView({ kind: 'libAlbum', artist: a.name, album: al.title })}
                          title={al.title}
                        >
                          💿 {al.title}
                        </button>
                      </div>
                      {open.has(alk) &&
                        al.tracks.map((t, i) => (
                          <div key={trackId(t) + i} className="indent">
                            <button
                              className={`nav tree track ${curId === trackId(t) ? 'playing' : ''}`}
                              onClick={() => play(al.tracks, i)}
                              title={t.title}
                            >
                              {curId === trackId(t) ? '🔊' : '♪'} {t.title}
                            </button>
                          </div>
                        ))}
                    </div>
                  )
                })}
            </div>
          )
        })}

        <div className="side-title row">
          <span>Soittolistat</span>
          <button className="icon-btn" onClick={newPlaylist} title="Uusi soittolista">
            ＋
          </button>
        </div>
        {sortedPlaylists.map((p) => (
          <button
            key={p.id}
            className={`nav ${view.kind === 'playlist' && view.id === p.id ? 'active' : ''}`}
            onClick={() => setView({ kind: 'playlist', id: p.id })}
            onContextMenu={(e) => {
              e.preventDefault()
              openMenu(e.clientX, e.clientY, [
                {
                  label: 'Nimeä uudelleen…',
                  onClick: () =>
                    openDialog({
                      title: 'Nimeä uudelleen',
                      value: p.name,
                      okLabel: 'Tallenna',
                      onOk: (v) => useStore.getState().renamePlaylist(p.id, v)
                    })
                },
                { label: 'Poista soittolista', onClick: () => useStore.getState().deletePlaylist(p.id) }
              ])
            }}
          >
            ☰ {p.name}
          </button>
        ))}
      </div>

      <button className="nav chord-toggle" onClick={toggleChords}>
        {showChords ? '◧ Piilota sointupaneeli' : '◨ Näytä sointupaneeli'}
      </button>
    </aside>
  )
}
