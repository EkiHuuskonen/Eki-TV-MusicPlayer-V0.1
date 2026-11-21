// Lataustesti: käynnistää sovelluksen piilossa, hakee kappaleet oikeista lähteistä ja lataa ne (paras laatu + WAV).
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import { mkdirSync, readdirSync, statSync, rmSync } from 'node:fs'
const require = createRequire(import.meta.url)
const electronPath = require('electron')
const dir = process.argv[2]
rmSync(dir, { recursive: true, force: true }); mkdirSync(dir, { recursive: true })
const PORT = 9334
const proc = spawn(electronPath, ['.', `--remote-debugging-port=${PORT}`], { env: { ...process.env, EKITV_TEST: '1', EKITV_TEST_DIR: dir }, stdio: ['ignore', 'pipe', 'pipe'] })
proc.stderr.on('data', () => {})
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let url
for (let i = 0; i < 60 && !url; i++) { try { url = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((p) => p.type === 'page')?.webSocketDebuggerUrl } catch {} ; await sleep(500) }
const ws = new WebSocket(url); await new Promise((r) => (ws.onopen = r))
let id = 0; const waiting = new Map()
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id) } }
const send = (method, params = {}) => new Promise((res) => { const i = ++id; waiting.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result?.result?.value ?? r.result?.exceptionDetails?.exception?.description }
await send('Runtime.enable')
await ev("localStorage.setItem('ekitv.test','1')")
await send('Page.reload'); await sleep(3000)
const js = `(async () => {
  const { fetchSource } = await import('/src/sources.ts').catch(() => ({}))
  return typeof window.__dl
})()`
console.log('__dl:', await ev('typeof window.__dl'))
// haetaan kappaleet sovelluksen omalla hakutoiminnolla (store)
const res = await ev(`(async () => {
  const out = []
  const api = window.api
  const j = await api.getJson('https://archive.org/advancedsearch.php?q=' + encodeURIComponent('mediatype:audio AND format:Flac AND collection:78rpm') + '&fl[]=identifier&rows=1&output=json')
  const ident = j.json.response.docs[0].identifier
  const m = await api.getJson('https://archive.org/metadata/' + ident)
  const f = m.json.files.find((x) => (x.format||'').includes('MP3') && x.name.endsWith('.mp3'))
  const t = { itemID: ident, file: f.name, title: f.title || f.name, artist: 'Testi', albumTitle: ident, license: m.json.metadata.licenseurl }
  await window.__dl.downloadTracks([t], null, 'best')
  await window.__dl.downloadTracks([t], null, 'wav')
  return ident + ' / ' + f.name
})()`)
console.log('kappale:', res)
await sleep(500)
for (const f of readdirSync(dir)) console.log(' ', f, Math.round(statSync(`${dir}/${f}`).size / 1024) + ' kt')
proc.kill(); process.exit(0)
