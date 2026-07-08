"use strict";
const electron = require("electron");
const api = {
  getSettings: () => electron.ipcRenderer.invoke("settings:get"),
  saveSettings: (settings) => electron.ipcRenderer.invoke("settings:save", settings),
  getPersonas: () => electron.ipcRenderer.invoke("personas:get"),
  savePersona: (persona) => electron.ipcRenderer.invoke("personas:save", persona),
  resetPersona: (id) => electron.ipcRenderer.invoke("personas:reset", id),
  pickAvatar: (personaId) => electron.ipcRenderer.invoke("personas:pickAvatar", personaId),
  pickChatImages: () => electron.ipcRenderer.invoke("images:pick"),
  chooseImageStorageFolder: () => electron.ipcRenderer.invoke("images:chooseStorageFolder"),
  getChat: (personaId) => electron.ipcRenderer.invoke("chat:get", personaId),
  clearChat: (personaId) => electron.ipcRenderer.invoke("chat:clear", personaId),
  sendMessage: (req) => electron.ipcRenderer.invoke("chat:send", req),
  stopGeneration: (personaId) => electron.ipcRenderer.invoke("chat:stop", personaId),
  getActiveGenerations: () => electron.ipcRenderer.invoke("chat:active"),
  onStream: (cb) => {
    const listener = (_e, ev) => cb(ev);
    electron.ipcRenderer.on("aura:stream", listener);
    return () => electron.ipcRenderer.removeListener("aura:stream", listener);
  },
  listMemories: () => electron.ipcRenderer.invoke("memory:list"),
  deleteMemory: (slug) => electron.ipcRenderer.invoke("memory:delete", slug),
  saveMemory: (note) => electron.ipcRenderer.invoke("memory:save", note),
  openMemoryVault: () => electron.ipcRenderer.invoke("memory:openVault"),
  testProvider: (config) => electron.ipcRenderer.invoke("provider:test", config),
  listLocalModels: (baseUrl) => electron.ipcRenderer.invoke("provider:localModels", baseUrl)
};
electron.contextBridge.exposeInMainWorld("aura", api);
electron.contextBridge.exposeInMainWorld("auraPresets", {
  getProviderPresets: () => electron.ipcRenderer.invoke("providers:presets")
});
