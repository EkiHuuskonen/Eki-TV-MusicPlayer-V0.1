// Automaattitesti: käynnistää rakennetun sovelluksen piilossa, ohjaa sitä Chrome DevTools -protokollalla,
// ottaa kuvakaappauksia ja tulostaa DOM-tarkistukset. Käyttö: node scripts/cdp-test.mjs <ulostulohakemisto>
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const electronPath = require('electron')
const out = process.argv[2] ?? './test-out'
mkdirSync(out, { recursive: true })
const PORT = 9333

const proc = spawn(electronPath, ['.', `--remote-debugging-port=${PORT}`], {
  env: { ...process.env, EKITV_TEST: '1' },
  stdio: ['ignore', 'pipe', 'pipe']
})
proc.stderr.on('data', () => {})
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function wsUrl() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()
      const page = list.find((p) => p.type === 'page')
      if (page) return page.webSocketDebuggerUrl
    } catch {}
    await sleep(500)
  }
  throw new Error('CDP ei vastaa')
}

const ws = new WebSocket(await wsUrl())
await new Promise((r) => (ws.onopen = r))
let id = 0
const waiting = new Map()
const consoleLines = []
ws.onmessage = (m) => {
  const d = JSON.parse(m.data)
  if (d.id && waiting.has(d.id)) {
    waiting.get(d.id)(d)
    waiting.delete(d.id)
  } else if (d.method === 'Runtime.consoleAPICalled') {
    consoleLines.push(d.params.type + ': ' + d.params.args.map((a) => a.value ?? a.description).join(' '))
  } else if (d.method === 'Runtime.exceptionThrown') {
    consoleLines.push('EXCEPTION: ' + (d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text))
  }
}
const send = (method, params = {}) =>
  new Promise((res) => {
    const i = ++id
    waiting.set(i, res)
    ws.send(JSON.stringify({ id: i, method, params }))
  })
const evalJs = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })
  return r.result?.result?.value
}
const shot = async (name) => {
  const r = await send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(`${out}/${name}.png`, Buffer.from(r.result.data, 'base64'))
  console.log('kuva:', `${out}/${name}.png`)
}
const waitFor = async (expr, secs = 30) => {
  for (let i = 0; i < secs * 2; i++) {
    if (await evalJs(expr)) return true
    await sleep(500)
  }
  return false
}

await send('Runtime.enable')
await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1320, height: 840, deviceScaleFactor: 1, mobile: false })

console.log('sovellus latautui:', await waitFor(`!!document.querySelector('.sidebar')`, 20))
console.log('hakutulokset ilmestyivät:', await waitFor(`document.querySelectorAll('.album-row, .track-row').length > 0`, 40))
console.log('albumeita:', await evalJs(`document.querySelectorAll('.album-row').length`), 'kappaleita:', await evalJs(`document.querySelectorAll('.track-row').length`))
console.log('lähteet/huomautukset:', await evalJs(`[...document.querySelectorAll('.note')].map(n=>n.textContent).join(' | ')`))
await sleep(1500)
await shot('1_haku')

// Hae artistia
await evalJs(`(() => { const i = document.querySelector('.search-bar input'); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; set.call(i,'EIME'); i.dispatchEvent(new Event('input',{bubbles:true})); i.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true})); })()`)
await sleep(5000)
console.log('EIME-haku, albumirivit:', await evalJs(`[...document.querySelectorAll('.album-row .title')].slice(0,4).map(n=>n.textContent).join(' | ')`))
await shot('2_artistihaku')

// Avaa ensimmäinen albumi
await evalJs(`document.querySelector('.album-row')?.click()`)
console.log('albumi avautui:', await waitFor(`document.querySelectorAll('.track-row').length > 0`, 20))
await shot('3_albumi')

// Mykistä (testi) ja soita koko albumi
await evalJs(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'m',ctrlKey:true,shiftKey:true,bubbles:true}))`)
await evalJs(`[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Soita kaikki'))?.click()`)
await sleep(2500)
console.log('soitin:', await evalJs(`document.querySelector('.playerbar .title')?.textContent + ' | ' + document.querySelector('.playerbar .time')?.textContent`))
console.log('sointuanalyysi valmis:', await waitFor(`!!document.querySelector('.cp-key')`, 60))
console.log('sävellaji:', await evalJs(`document.querySelector('.cp-key')?.textContent`), '| sointu nyt:', await evalJs(`document.querySelector('.cp-chord')?.textContent`))
console.log('sointuja listassa:', await evalJs(`document.querySelectorAll('.cp-item').length`))
await sleep(3000)
await shot('4_soi_soinnut')

// Suosikki ja kirjasto
await evalJs(`document.querySelector('.track-row .heart')?.click()`)
await sleep(500)
await evalJs(`document.querySelectorAll('.sidebar .nav')[2]?.click()`)
await sleep(800)
console.log('suosikkeja:', await evalJs(`document.querySelectorAll('.track-row').length`))
console.log('kirjastopuu:', await evalJs(`[...document.querySelectorAll('.sidebar .tree')].map(n=>n.textContent).join(' | ')`))
await shot('5_suosikit')

console.log('--- konsoli ---')
console.log(consoleLines.slice(0, 15).join('\n') || '(ei virheitä)')
ws.close()
proc.kill()
process.exit(0)
