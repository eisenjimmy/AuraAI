import { randomUUID } from 'crypto'
import { ipcMain, dialog, shell, BrowserWindow, app } from 'electron'
import { copyFileSync, existsSync, mkdirSync, statSync } from 'fs'
import { basename, join, extname } from 'path'
import type { AppSettings, Persona, ProviderConfig, SendMessageRequest, MemoryNote, ChatAttachment } from '@common/types'
import { loadSettings, saveSettings, loadPersonas, savePersona, resetPersona, dataDir, defaultImageStoragePath } from './store'
import { loadChat, clearChat } from './chats'
import { MemoryVault, defaultVaultPath } from './memory/vault'
import { createProvider, PROVIDER_PRESETS } from './providers'
import { OpenAICompatProvider } from './providers/openaiCompat'
import { ChatPipeline } from './agent/pipeline'
import { IS_KOREAN_EDITION } from '@common/edition'

const uiText = IS_KOREAN_EDITION
  ? {
      chooseProfileImage: '프로필 이미지 선택',
      addImages: '이미지 추가',
      imageFilter: '이미지',
      chooseImageFolder: '이미지 저장 폴더 선택'
    }
  : {
      chooseProfileImage: 'Choose a profile image',
      addImages: 'Add images',
      imageFilter: 'Images',
      chooseImageFolder: 'Choose image storage folder'
    }

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
      title: uiText.chooseProfileImage,
      filters: [{ name: uiText.imageFilter, extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'] }],
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

  ipcMain.handle('images:pick', async (): Promise<ChatAttachment[]> => {
    const win = getWindow()
    if (!win) return []
    const result = await dialog.showOpenDialog(win, {
      title: uiText.addImages,
      filters: [{ name: uiText.imageFilter, extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'] }],
      properties: ['openFile', 'multiSelections']
    })
    if (result.canceled || result.filePaths.length === 0) return []

    const settings = loadSettings()
    const imageDir = settings.imageStoragePath || defaultImageStoragePath()
    if (!existsSync(imageDir)) mkdirSync(imageDir, { recursive: true })

    return result.filePaths.map(src => {
      const ext = extname(src).toLowerCase()
      const id = randomUUID()
      const safeBase = basename(src, ext).replace(/[^a-z0-9._ -]/gi, '').slice(0, 80) || 'image'
      const fileName = `${new Date().toISOString().replace(/[:.]/g, '-')}-${id}-${safeBase}${ext}`
      const dest = join(imageDir, fileName)
      copyFileSync(src, dest)
      const stat = statSync(dest)
      return {
        id,
        kind: 'image',
        name: basename(src),
        mimeType: mimeForExt(ext),
        size: stat.size,
        path: dest,
        url: imageUrl(dest)
      }
    })
  })

  ipcMain.handle('images:chooseStorageFolder', async (): Promise<string | null> => {
    const win = getWindow()
    if (!win) return null
    const result = await dialog.showOpenDialog(win, {
      title: uiText.chooseImageFolder,
      properties: ['openDirectory', 'createDirectory']
    })
    if (result.canceled || result.filePaths.length === 0) return null
    return result.filePaths[0]
  })

  // ---------- chat ----------
  ipcMain.handle('chat:get', (_e, personaId: string) => loadChat(personaId))
  ipcMain.handle('chat:clear', (_e, personaId: string) => clearChat(personaId))
  ipcMain.handle('chat:send', async (_e, req: SendMessageRequest) => {
    await pipeline.send(req.personaId, req.text, req.attachments ?? [])
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

export function imageUrl(filePath: string): string {
  return `aura-image://a/${encodeURIComponent(Buffer.from(filePath, 'utf8').toString('base64url'))}`
}

function mimeForExt(ext: string): string {
  switch (ext.toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg'
    case '.webp':
      return 'image/webp'
    case '.gif':
      return 'image/gif'
    default:
      return 'image/png'
  }
}
