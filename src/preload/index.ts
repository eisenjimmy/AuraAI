import { contextBridge, ipcRenderer } from 'electron'
import type { AuraApi, StreamEvent } from '@common/types'

const api: AuraApi = {
  getSettings: () => ipcRenderer.invoke('settings:get'),
  saveSettings: settings => ipcRenderer.invoke('settings:save', settings),
  getPersonas: () => ipcRenderer.invoke('personas:get'),
  savePersona: persona => ipcRenderer.invoke('personas:save', persona),
  resetPersona: id => ipcRenderer.invoke('personas:reset', id),
  pickAvatar: personaId => ipcRenderer.invoke('personas:pickAvatar', personaId),
  pickChatImages: () => ipcRenderer.invoke('images:pick'),
  chooseImageStorageFolder: () => ipcRenderer.invoke('images:chooseStorageFolder'),

  getChat: personaId => ipcRenderer.invoke('chat:get', personaId),
  clearChat: personaId => ipcRenderer.invoke('chat:clear', personaId),
  sendMessage: req => ipcRenderer.invoke('chat:send', req),
  stopGeneration: personaId => ipcRenderer.invoke('chat:stop', personaId),
  getActiveGenerations: () => ipcRenderer.invoke('chat:active'),
  onStream: (cb: (ev: StreamEvent) => void) => {
    const listener = (_e: unknown, ev: StreamEvent): void => cb(ev)
    ipcRenderer.on('aura:stream', listener)
    return () => ipcRenderer.removeListener('aura:stream', listener)
  },

  listMemories: () => ipcRenderer.invoke('memory:list'),
  deleteMemory: slug => ipcRenderer.invoke('memory:delete', slug),
  saveMemory: note => ipcRenderer.invoke('memory:save', note),
  openMemoryVault: () => ipcRenderer.invoke('memory:openVault'),

  testProvider: config => ipcRenderer.invoke('provider:test', config),
  listLocalModels: baseUrl => ipcRenderer.invoke('provider:localModels', baseUrl)
}

contextBridge.exposeInMainWorld('aura', api)
contextBridge.exposeInMainWorld('auraPresets', {
  getProviderPresets: () => ipcRenderer.invoke('providers:presets')
})
