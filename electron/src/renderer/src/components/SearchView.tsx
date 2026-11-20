import { useEffect } from 'react'
import { useStore } from '../store'
import { SOURCE_TITLES, albumSourceLabel, albumThumb } from '../util'
import type { SourceId } from '../types'
import { Cover, TrackList } from './TrackList'

const GENRES: [string, string][] = [
  ['Blues', 'blues'],
  ['Jazz', 'jazz'],
  ['Klassinen', 'classical'],
  ['Rock', 'rock'],
  ['Folk', 'folk'],
  ['Elektroninen', 'electronic'],
  ['Hip hop', 'hip hop'],
  ['Ambient', 'ambient'],
  ['Suomi', 'finnish'],
  ['Podcast', 'podcast']
]

export default function SearchView(): React.JSX.Element {
  const s = useStore((st) => st.search)
  const setQuery = useStore((st) => st.setQuery)
  const setSource = useStore((st) => st.setSource)
  const runSearch = useStore((st) => st.runSearch)
  const setView = useStore((st) => st.setView)

  useEffect(() => {
    if (s.items.length === 0 && s.tracks.length === 0 && !s.loading && s.reqId === 0) void runSearch(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const empty = !s.loading && s.items.length === 0 && s.tracks.length === 0 && s.notes.length === 0 && s.reqId > 0

  return (
    <div className="page">
      <div className="search-head">
        <h1>{s.query ? `Haku: ${s.query}` : 'Suosituimmat'}</h1>
        <div className="search-bar">
          <input
            type="search"
            placeholder="Hae artistia, kappaletta tai aihetta"
            value={s.query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void runSearch(true)
            }}
          />
          <button className="primary" onClick={() => void runSearch(true)}>
            Hae
          </button>
          <select
            value={s.source}
            onChange={(e) => {
              setSource(e.target.value as SourceId)
              void runSearch(true)
            }}
            title="Lähde"
          >
            {(Object.keys(SOURCE_TITLES) as SourceId[]).map((k) => (
              <option key={k} value={k}>
                {SOURCE_TITLES[k]}
              </option>
            ))}
          </select>
        </div>
        <div className="chips">
          {GENRES.map(([label, q]) => (
            <button
              key={label}
              className="chip"
              onClick={() => {
                setQuery(q)
                void runSearch(true)
              }}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <div className="scroll">
        {s.notes.map((n) => (
          <div key={n} className="note">
            {n}
          </div>
        ))}

        {s.items.length > 0 && (
          <section>
            <h2>{s.query ? 'Albumit – artistin omat ensin' : 'Albumit'}</h2>
            {s.items.map((a) => (
              <div key={a.id} className="album-row" onClick={() => setView({ kind: 'album', item: a })}>
                <div className="cover-wrap">
                  <Cover url={albumThumb(a)} size={56} round={8} />
                  <span className="disc">💿</span>
                </div>
                <div className="grow">
                  <div className="title">
                    <span className="badge">ALBUMI</span>
                    {a.title}
                  </div>
                  <div className="sub">
                    {[a.creator, a.trackCount ? `${a.trackCount} kappaletta` : undefined, albumSourceLabel(a)]
                      .filter(Boolean)
                      .join(' · ')}
                  </div>
                </div>
                <span className="chev-r">›</span>
              </div>
            ))}
          </section>
        )}

        {s.tracks.length > 0 && (
          <section>
            <h2>{s.source === 'radio' ? 'Nettiradiot' : 'Yksittäiset kappaleet'}</h2>
            <TrackList tracks={s.tracks} />
          </section>
        )}

        {s.loading && <div className="center muted">Haetaan…</div>}
        {!s.loading && s.canMore && (
          <div className="center">
            <button onClick={() => void runSearch(false)}>Näytä lisää</button>
          </div>
        )}
        {empty && <div className="center muted">Ei tuloksia.</div>}
      </div>
    </div>
  )
}
