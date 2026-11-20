import { useEffect, useRef } from 'react'
import { useStore } from '../store'
import {
  chordName,
  chordNotes,
  formatTime,
  isNoChord,
  keyName,
  segmentIndexAt,
  useFlats
} from '../util'
import type { Analysis } from '../types'

export default function ChordPanel(): React.JSX.Element {
  const chord = useStore((s) => s.chord)
  const finnish = useStore((s) => s.finnish)
  const setFinnish = useStore((s) => s.setFinnish)

  return (
    <aside className="chordpanel">
      <div className="cp-head">
        <h3>Sävellaji ja soinnut</h3>
        <div className="seg" title="Nuotinimet: H/B (suomalainen) tai B/Bb (kansainvälinen)">
          <button className={finnish ? 'on' : ''} onClick={() => setFinnish(true)}>
            H
          </button>
          <button className={!finnish ? 'on' : ''} onClick={() => setFinnish(false)}>
            B
          </button>
        </div>
      </div>
      {chord.kind === 'idle' && (
        <div className="cp-empty">Soita kappale, niin sävellaji ja soinnut näkyvät tässä.</div>
      )}
      {chord.kind === 'loading' && (
        <div className="cp-empty">
          <div className="spinner" />
          {chord.msg}
        </div>
      )}
      {chord.kind === 'failed' && <div className="cp-empty">⚠ {chord.msg}</div>}
      {chord.kind === 'done' && <AnalysisContent analysis={chord.analysis} finnish={finnish} />}
    </aside>
  )
}

function AnalysisContent({ analysis, finnish }: { analysis: Analysis; finnish: boolean }): React.JSX.Element {
  const currentTime = useStore((s) => s.currentTime)
  const seek = useStore((s) => s.seek)
  const flats = useFlats(analysis)
  const idx = segmentIndexAt(analysis, currentTime)
  const seg = idx >= 0 ? analysis.segments[idx] : undefined
  const next = idx >= 0 ? analysis.segments.slice(idx + 1).find((s) => !isNoChord(s)) : undefined
  const relRoot = analysis.keyMinor ? (analysis.keyRoot + 3) % 12 : (analysis.keyRoot + 9) % 12

  const listRef = useRef<HTMLDivElement>(null)
  const activeRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const c = listRef.current
    const a = activeRef.current
    if (c && a) c.scrollTo({ top: a.offsetTop - c.clientHeight / 2 + a.clientHeight / 2, behavior: 'smooth' })
  }, [idx])

  return (
    <div className="cp-body">
      <div className="cp-card">
        <div className="cp-label">SÄVELLAJI</div>
        <div className="cp-key">{keyName(analysis.keyRoot, analysis.keyMinor, flats, finnish)}</div>
        <div className="cp-sub">Suhteellinen: {keyName(relRoot, !analysis.keyMinor, flats, finnish)}</div>
      </div>
      <div className="cp-card">
        <div className="cp-label">NYT</div>
        <div className="cp-chord">{seg ? chordName(seg, flats, finnish) : '–'}</div>
        {seg && <div className="cp-sub">{chordNotes(seg, flats, finnish)}</div>}
        {next && (
          <div className="cp-sub">
            Seuraavaksi: <b>{chordName(next, flats, finnish)}</b>
          </div>
        )}
      </div>
      <div className="cp-label">SOINTUKULKU</div>
      <div className="cp-list" ref={listRef}>
        {analysis.segments.map((s, i) => (
          <div
            key={i}
            ref={i === idx ? activeRef : undefined}
            className={`cp-item ${i === idx ? 'active' : ''}`}
            onClick={() => seek(s.start + 0.05)}
          >
            <span className="t">{formatTime(s.start)}</span>
            <span className="c">{chordName(s, flats, finnish)}</span>
          </div>
        ))}
      </div>
      <div className="cp-foot">
        Automaattinen arvio – toimii parhaiten selkeillä sointuilla. Analysoidaan korkeintaan 10 ensimmäistä minuuttia.
      </div>
    </div>
  )
}
