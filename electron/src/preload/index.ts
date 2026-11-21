import { contextBridge, ipcRenderer } from 'electron'

const api = {
  getJson: (url: string): Promise<{ status: number; json: unknown; error?: string }> =>
    ipcRenderer.invoke('http:json', url),
  getAudio: (
    url: string,
    maxBytes: number
  ): Promise<{ ok: boolean; data?: Uint8Array; tooLarge?: boolean; error?: string }> =>
    ipcRenderer.invoke('http:audio', url, maxBytes),
  loadLibrary: (): Promise<unknown> => ipcRenderer.invoke('lib:load'),
  saveLibrary: (data: unknown): Promise<boolean> => ipcRenderer.invoke('lib:save', data),
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('shell:open', url),
  chooseDir: (defaultPath?: string): Promise<string | null> => ipcRenderer.invoke('dl:chooseDir', defaultPath),
  dlGet: (
    urls: string[]
  ): Promise<{ ok: boolean; data?: Uint8Array; url?: string; contentType?: string; error?: string }> =>
    ipcRenderer.invoke('dl:get', urls),
  dlSave: (dir: string, sub: string | null, filename: string, data: Uint8Array): Promise<string> =>
    ipcRenderer.invoke('dl:save', dir, sub, filename, data),
  showItem: (path: string): Promise<void> => ipcRenderer.invoke('shell:showItem', path)
}

contextBridge.exposeInMainWorld('api', api)

export type Api = typeof api
