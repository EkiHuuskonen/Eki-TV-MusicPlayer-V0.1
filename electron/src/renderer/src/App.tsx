import { useEffect } from 'react'
import { useStore } from './store'
import Sidebar from './components/Sidebar'
import SearchView from './components/SearchView'
import { AlbumView, FavoritesView, LibraryTracksView, NowPlayingView, PlaylistView } from './components/Views'
import PlayerBar from './components/PlayerBar'
import ChordPanel from './components/ChordPanel'
import { ContextMenu, DialogHost, DownloadBanner } from './components/Overlays'

export default function App(): React.JSX.Element {
  const view = useStore((s) => s.view)
  const showChords = useStore((s) => s.showChords)

  // Näppäinoikotiet: välilyönti, Ctrl/⌘ + nuolet, Ctrl/⌘+Shift+M
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      const st = useStore.getState()
      const tag = (e.target as HTMLElement | null)?.tagName
      const typing = tag === 'INPUT' || tag === 'TEXTAREA'
      const mod = e.ctrlKey || e.metaKey
      if (e.key === 'Escape') {
        st.closeMenu()
        return
      }
      if (e.code === 'Space' && !typing && !mod) {
        e.preventDefault()
        st.toggle()
      } else if (mod && e.key === 'ArrowUp') {
        e.preventDefault()
        st.changeVolume(0.1)
      } else if (mod && e.key === 'ArrowDown') {
        e.preventDefault()
        st.changeVolume(-0.1)
      } else if (mod && e.key === 'ArrowRight') {
        e.preventDefault()
        st.next()
      } else if (mod && e.key === 'ArrowLeft') {
        e.preventDefault()
        st.prev()
      } else if (mod && e.shiftKey && e.key.toLowerCase() === 'm') {
        e.preventDefault()
        st.toggleMute()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  let main: React.JSX.Element
  switch (view.kind) {
    case 'now':
      main = <NowPlayingView />
      break
    case 'favorites':
      main = <FavoritesView />
      break
    case 'playlist':
      main = <PlaylistView id={view.id} />
      break
    case 'libArtist':
      main = <LibraryTracksView artist={view.artist} album={null} />
      break
    case 'libAlbum':
      main = <LibraryTracksView artist={view.artist} album={view.album} />
      break
    case 'album':
      main = <AlbumView key={view.item.id} item={view.item} />
      break
    default:
      main = <SearchView />
  }

  return (
    <div className="app">
      <div className={`body ${showChords ? 'with-chords' : ''}`}>
        <Sidebar />
        <main className="main">{main}</main>
        {showChords && <ChordPanel />}
      </div>
      <PlayerBar />
      <DownloadBanner />
      <ContextMenu />
      <DialogHost />
    </div>
  )
}
