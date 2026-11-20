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
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('shell:open', url)
}

contextBridge.exposeInMainWorld('api', api)

export type Api = typeof api
