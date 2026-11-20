import { useState } from 'react'
import { useStore } from '../store'
import { formatTime, isLive, thumbUrl } from '../util'
import { Cover } from './TrackList'

export default function PlayerBar(): React.JSX.Element {
  const t = useStore((s) => s.queue[s.index])
  const playing = useStore((s) => s.playing)
  const currentTime = useStore((s) => s.currentTime)
  const duration = useStore((s) => s.duration)
  const volume = useStore((s) => s.volume)
  const muted = useStore((s) => s.muted)
  const shuffle = useStore((s) => s.shuffle)
  const playError = useStore((s) => s.playError)
  const { toggle, next, prev, seek, setVolume, toggleMute, toggleShuffle, setView } = useStore.getState()
  const [scrub, setScrub] = useState<number | null>(null)
  const live = t ? isLive(t) : false

  const icon = muted || volume === 0 ? '🔇' : volume < 0.34 ? '🔈' : volume < 0.67 ? '🔉' : '🔊'
  const shown = scrub ?? currentTime

  return (
    <footer className="playerbar">
      <button className="now" onClick={() => setView({ kind: 'now' })} title="Näytä mikä soi">
        {t && <Cover url={thumbUrl(t)} size={46} round={6} />}
        <div className="meta">
          <div className="title">{t ? t.title : 'Ei soitettavaa'}</div>
          <div className="sub">
            {playError ?? [t?.artist, t?.albumTitle].filter(Boolean).join(' · ')}
          </div>
        </div>
      </button>

      <div className="controls">
        <button className="icon-btn" onClick={prev} disabled={!t} title="Edellinen (Ctrl+←)">
          ⏮
        </button>
        <button className="play-btn" onClick={toggle} disabled={!t} title="Toista / tauko (välilyönti)">
          {playing ? '⏸' : '▶'}
        </button>
        <button className="icon-btn" onClick={next} disabled={!t} title="Seuraava (Ctrl+→)">
          ⏭
        </button>
      </div>

      <div className="seek">
        <span className="time">{live ? 'LIVE' : formatTime(shown)}</span>
        <input
          type="range"
          min={0}
          max={Math.max(duration, 1)}
          step={0.5}
          value={Math.min(shown, Math.max(duration, 1))}
          disabled={live || !t}
          onChange={(e) => setScrub(Number(e.target.value))}
          onPointerUp={() => {
            if (scrub != null) seek(scrub)
            setScrub(null)
          }}
          onKeyUp={() => {
            if (scrub != null) seek(scrub)
            setScrub(null)
          }}
        />
        <span className="time">{live ? '' : formatTime(duration)}</span>
      </div>

      <button className={`icon-btn ${shuffle ? 'on' : ''}`} onClick={toggleShuffle} title="Satunnaistoisto">
        🔀
      </button>
      <button className="icon-btn" onClick={toggleMute} title={muted ? 'Poista mykistys' : 'Mykistä (Ctrl+Shift+M)'}>
        {icon}
      </button>
      <input
        className="vol"
        type="range"
        min={0}
        max={1}
        step={0.02}
        value={muted ? 0 : volume}
        onChange={(e) => setVolume(Number(e.target.value))}
        title="Äänenvoimakkuus (Ctrl+↑ / Ctrl+↓)"
      />
    </footer>
  )
}
