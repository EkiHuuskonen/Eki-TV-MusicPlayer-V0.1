import { app, BrowserWindow, dialog, ipcMain, shell, net } from 'electron'
import { join } from 'path'
import { promises as fs } from 'fs'

const UA = 'Eki-TV-MusicPlayer/0.1 (+https://github.com/EkiHuuskonen/Eki-TV-MusicPlayer-V0.1)'

// Salli toisto ilman erillistä käyttäjän eleenpainallusta (mediapainikkeet, automaattinen jatkaminen)
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required')

function createWindow(): void {
  const win = new BrowserWindow({
    show: !process.env['EKITV_TEST'], // testiajossa ikkuna pidetään piilossa
    width: 1320,
    height: 840,
    minWidth: 960,
    minHeight: 620,
    backgroundColor: '#1b1b22',
    title: 'Eki-TV MusicPlayer',
    autoHideMenuBar: true,
    icon: join(__dirname, '../../build/icon.png'),
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  // Ulkoiset linkit avataan oletusselaimessa
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url)
    return { action: 'deny' }
  })
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith('http://localhost') && !url.startsWith('file://')) {
      e.preventDefault()
      if (/^https?:\/\//.test(url)) shell.openExternal(url)
    }
  })

  if (process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

// --- IPC: verkkopyynnöt tehdään pääprosessissa, jolloin selaimen CORS-rajoitukset eivät haittaa ---

ipcMain.handle('http:json', async (_e, url: string) => {
  try {
    const r = await net.fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
    const text = await r.text()
    let json: unknown = null
    try {
      json = JSON.parse(text)
    } catch {
      json = null
    }
    return { status: r.status, json }
  } catch (err) {
    return { status: 0, json: null, error: String(err) }
  }
})

ipcMain.handle('http:audio', async (_e, url: string, maxBytes: number) => {
  try {
    const r = await net.fetch(url, { headers: { 'User-Agent': UA } })
    if (!r.ok) return { ok: false, error: `HTTP ${r.status}` }
    const len = Number(r.headers.get('content-length') ?? 0)
    if (len > maxBytes) return { ok: false, tooLarge: true }
    const buf = Buffer.from(await r.arrayBuffer())
    if (buf.length > maxBytes) return { ok: false, tooLarge: true }
    return { ok: true, data: new Uint8Array(buf) }
  } catch (err) {
    return { ok: false, error: String(err) }
  }
})

const libraryFile = (): string => join(app.getPath('userData'), 'library.json')

ipcMain.handle('lib:load', async () => {
  try {
    return JSON.parse(await fs.readFile(libraryFile(), 'utf-8'))
  } catch {
    return null
  }
})

ipcMain.handle('lib:save', async (_e, data: unknown) => {
  await fs.mkdir(app.getPath('userData'), { recursive: true })
  const tmp = libraryFile() + '.tmp'
  await fs.writeFile(tmp, JSON.stringify(data), 'utf-8')
  await fs.rename(tmp, libraryFile())
  return true
})

// --- Lataukset ---

ipcMain.handle('dl:chooseDir', async (_e, defaultPath?: string) => {
  if (process.env['EKITV_TEST_DIR']) return process.env['EKITV_TEST_DIR'] // automaattitesti ohittaa valintaikkunan
  const r = await dialog.showOpenDialog({
    title: 'Valitse kansio, johon musiikki tallennetaan',
    properties: ['openDirectory', 'createDirectory'],
    defaultPath: defaultPath || app.getPath('music')
  })
  return r.canceled || !r.filePaths[0] ? null : r.filePaths[0]
})

// Hakee tiedoston: kokeilee osoitteita järjestyksessä (paras laatu ensin, varaosoite perässä)
ipcMain.handle('dl:get', async (_e, urls: string[]) => {
  let last = 'tuntematon virhe'
  for (const url of urls) {
    try {
      const headers: Record<string, string> = { 'User-Agent': UA }
      if (new URL(url).hostname.endsWith('ccmixter.org')) headers['Referer'] = 'https://ccmixter.org/'
      const r = await net.fetch(url, { headers })
      if (!r.ok) {
        last = `HTTP ${r.status}`
        continue
      }
      const buf = Buffer.from(await r.arrayBuffer())
      return { ok: true, data: new Uint8Array(buf), url, contentType: r.headers.get('content-type') ?? '' }
    } catch (err) {
      last = String(err)
    }
  }
  return { ok: false, error: last }
})

ipcMain.handle('dl:save', async (_e, dir: string, sub: string | null, filename: string, data: Uint8Array) => {
  const folder = sub ? join(dir, sub) : dir
  await fs.mkdir(folder, { recursive: true })
  const dot = filename.lastIndexOf('.')
  const stem = dot > 0 ? filename.slice(0, dot) : filename
  const ext = dot > 0 ? filename.slice(dot) : ''
  let path = join(folder, filename)
  for (let n = 2; ; n++) {
    try {
      await fs.access(path)
      path = join(folder, `${stem} (${n})${ext}`)
    } catch {
      break
    }
  }
  await fs.writeFile(path, data)
  return path
})

ipcMain.handle('shell:showItem', (_e, path: string) => {
  shell.showItemInFolder(path)
})

ipcMain.handle('shell:open', async (_e, url: string) => {
  if (/^https?:\/\//.test(url)) await shell.openExternal(url)
})

app.whenReady().then(() => {
  createWindow()
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
