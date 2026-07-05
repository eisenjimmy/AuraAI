import { app, BrowserWindow, protocol, net, shell } from 'electron'
import { existsSync } from 'fs'
import { join } from 'path'
import { pathToFileURL } from 'url'
import { registerIpc } from './ipc'
import { dataDir } from './store'

let mainWindow: BrowserWindow | null = null

// Only one Aura at a time — two instances would race on the same data files.
if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })
}

// Serve user-uploaded persona avatars from the app data folder via a
// dedicated scheme so the renderer never needs file:// access.
protocol.registerSchemesAsPrivileged([
  { scheme: 'aura-avatar', privileges: { standard: false, secure: true, supportFetchAPI: true } }
])

const DEV_URL = !app.isPackaged ? process.env['ELECTRON_RENDERER_URL'] : undefined

function createWindow(): void {
  const iconPath = join(__dirname, '../../build/icon.png')
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 780,
    minWidth: 860,
    minHeight: 560,
    title: 'Aura AI',
    backgroundColor: '#0d0f12',
    autoHideMenuBar: true,
    ...(existsSync(iconPath) ? { icon: iconPath } : {}),
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  mainWindow.on('closed', () => {
    mainWindow = null
  })

  // External links open in the system browser, never inside the app.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http')) void shell.openExternal(url)
    return { action: 'deny' }
  })

  // The window may only ever display our own UI — block all navigation
  // (e.g. a dragged-in URL or file) away from it.
  mainWindow.webContents.on('will-navigate', (event, url) => {
    const allowed = DEV_URL ? url.startsWith(DEV_URL) : url.startsWith('file://')
    if (!allowed) event.preventDefault()
  })

  if (DEV_URL) {
    void mainWindow.loadURL(DEV_URL)
  } else {
    void mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

app.whenReady().then(() => {
  protocol.handle('aura-avatar', request => {
    // aura-avatar://a/<encoded filename>?v=cachebuster
    const url = new URL(request.url)
    const name = decodeURIComponent(url.pathname.replace(/^\//, ''))
    const clean = name.replace(/[^a-z0-9._ -]/gi, '').replace(/\.\./g, '')
    const file = join(dataDir(), 'avatars', clean)
    return net.fetch(pathToFileURL(file).toString())
  })

  registerIpc(() => mainWindow)
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
