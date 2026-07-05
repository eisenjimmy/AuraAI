import { ipcMain, dialog, shell, BrowserWindow, app } from 'electron'
import { copyFileSync, existsSync, mkdirSync } from 'fs'
import { join, extname } from 'path'
import type { AppSettings, Persona, ProviderConfig, SendMessageRequest, MemoryNote } from '@common/types'
import { loadSettings, saveSettings, loadPersonas, savePersona, resetPersona, dataDir } from './store'
import { loadChat, clearChat } from './chats'
import { MemoryVault, defaultVaultPath } from './memory/vault'
import { createProvider, PROVIDER_PRESETS } from './providers'
import { OpenAICompatProvider } from './providers/openaiCompat'
import { ChatPipeline } from './agent/pipeline'

export function registerIpc(getWindow: () => BrowserWindow | null): void {
  const pipeline = new ChatPipeline(
    () => loadSettings(),
    (id: string) => loadPersonas().find(p => p.id === id),
    ev => getWindow()?.webContents.send('aura:stream', ev)
  )

  // ---------- settings ----------
  ipcMain.handle('settings:get', (): AppSettings => loadSettings())
  ipcMain.handle('settings:save', (_e, settings: AppSettings) => saveSettings(settings))
  ipcMain.handle('providers:presets', () => PROVIDER_PRESETS)

  // ---------- personas ----------
  ipcMain.handle('personas:get', (): Persona[] => loadPersonas())
  ipcMain.handle('personas:save', (_e, persona: Persona) => savePersona(persona))
  ipcMain.handle('personas:reset', (_e, id: string): Persona => resetPersona(id))

  ipcMain.handle('personas:pickAvatar', async (_e, personaId: string): Promise<string | null> => {
    const win = getWindow()
    if (!win) return null
    const result = await dialog.showOpenDialog(win, {
      title: 'Choose a profile image',
      filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'] }],
      properties: ['openFile']
    })
    if (result.canceled || result.filePaths.length === 0) return null
    const src = result.filePaths[0]
    const avatarsDir = join(dataDir(), 'avatars')
    if (!existsSync(avatarsDir)) mkdirSync(avatarsDir, { recursive: true })
    const fileName = `${personaId.replace(/[^a-z0-9_-]/gi, '_')}${extname(src).toLowerCase()}`
    copyFileSync(src, join(avatarsDir, fileName))
    // Filename goes in the path (not the authority) so any name is URL-safe.
    return `aura-avatar://a/${encodeURIComponent(fileName)}?v=${Date.now()}`
  })

  // ---------- chat ----------
  ipcMain.handle('chat:get', (_e, personaId: string) => loadChat(personaId))
  ipcMain.handle('chat:clear', (_e, personaId: string) => clearChat(personaId))
  ipcMain.handle('chat:send', async (_e, req: SendMessageRequest) => {
    await pipeline.send(req.personaId, req.text)
  })
  ipcMain.handle('chat:stop', (_e, personaId?: string) => pipeline.stop(personaId))
  ipcMain.handle('chat:active', () => pipeline.activePersonas())

  // ---------- memory ----------
  const vault = (): MemoryVault => new MemoryVault(loadSettings().memoryVaultPath || defaultVaultPath())
  ipcMain.handle('memory:list', (): MemoryNote[] => vault().list())
  ipcMain.handle('memory:delete', (_e, slug: string) => vault().delete(slug))
  ipcMain.handle('memory:save', (_e, note: MemoryNote) => vault().save(note))
  ipcMain.handle('memory:openVault', async () => {
    await shell.openPath(vault().path)
  })

  // ---------- providers ----------
  ipcMain.handle('provider:test', async (_e, config: ProviderConfig) => {
    try {
      return await createProvider(config).test()
    } catch (err) {
      return { ok: false, message: err instanceof Error ? err.message : String(err) }
    }
  })

  ipcMain.handle('provider:localModels', async (_e, baseUrl: string): Promise<string[]> => {
    try {
      return await new OpenAICompatProvider(baseUrl).listModels()
    } catch {
      return []
    }
  })

  ipcMain.handle('app:version', () => app.getVersion())
}
