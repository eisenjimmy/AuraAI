import { app } from 'electron'
import { createWriteStream, existsSync, mkdirSync, statSync, renameSync, unlinkSync } from 'fs'
import { dirname, join, basename } from 'path'
import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from 'child_process'
import { get } from 'https'
import type { AppSettings, LocalLlmSettings, LocalLlmStatus } from '@common/types'
import { dataDir } from './store'

const RECOMMENDED_MODEL = 'Gemma 4 E4B Instruct GGUF'
const RECOMMENDED_HF = 'unsloth/gemma-4-E4B-it-GGUF'
const RECOMMENDED_FILE = 'gemma-4-E4B-it-Q4_K_M.gguf'
const RECOMMENDED_URL = `https://huggingface.co/${RECOMMENDED_HF}/resolve/main/${RECOMMENDED_FILE}?download=true`

let processRef: ChildProcessWithoutNullStreams | null = null
let downloading = false
let progress: LocalLlmStatus['downloadProgress']
let message = ''

export function defaultModelPath(): string {
  return join(dataDir(), 'models', RECOMMENDED_FILE)
}

export function localBaseUrl(settings?: LocalLlmSettings): string {
  const port = settings?.port || 8080
  return `http://127.0.0.1:${port}/v1`
}

export function localModelId(settings?: LocalLlmSettings): string {
  const path = settings?.modelPath || defaultModelPath()
  return basename(path, '.gguf') || 'gemma-4-E4B-it'
}

export function status(settings?: LocalLlmSettings): LocalLlmStatus {
  const modelPath = settings?.modelPath || defaultModelPath()
  const binaryPath = settings?.binaryPath || detectLlamaBinary()
  return {
    mode: settings?.mode || 'manual',
    running: processRef !== null && !processRef.killed,
    pid: processRef?.pid,
    binaryPath,
    binaryFound: Boolean(binaryPath),
    modelPath,
    modelExists: existsSync(modelPath),
    modelBytes: safeSize(modelPath),
    downloading,
    downloadProgress: progress,
    downloadMessage: message,
    baseUrl: localBaseUrl(settings),
    recommendedModel: RECOMMENDED_MODEL,
    recommendedHf: RECOMMENDED_HF
  }
}

export async function downloadRecommended(settings: AppSettings, onStatus?: (s: LocalLlmStatus) => void): Promise<LocalLlmStatus> {
  const llm = normalized(settings.localLlm)
  const dest = llm.modelPath || defaultModelPath()
  if (existsSync(dest) && safeSize(dest) > 1024 * 1024) {
    message = 'Model already downloaded.'
    return status(llm)
  }
  if (downloading) return status(llm)

  downloading = true
  progress = 0
  message = 'Starting download...'
  onStatus?.(status(llm))

  try {
    if (!existsSync(dirname(dest))) mkdirSync(dirname(dest), { recursive: true })
    await downloadFile(RECOMMENDED_URL, dest + '.download', dest, pct => {
      progress = pct
      message = pct !== undefined ? `Downloading ${Math.round(pct * 100)}%` : 'Downloading...'
      onStatus?.(status(llm))
    })
    progress = 1
    message = 'Download complete.'
  } finally {
    downloading = false
    onStatus?.(status(llm))
  }
  return status(llm)
}

export async function start(settings: AppSettings): Promise<LocalLlmStatus> {
  const llm = normalized(settings.localLlm)
  if (processRef && !processRef.killed) return status(llm)

  const binary = llm.binaryPath || detectLlamaBinary()
  if (!binary) {
    message = 'llama.cpp executable not found. Install llama.cpp or choose llama-server in Settings.'
    return status(llm)
  }

  const model = llm.modelPath || defaultModelPath()
  if (!existsSync(model)) {
    message = 'Model file is missing. Download Gemma 4 E4B first or choose a GGUF model.'
    return status(llm)
  }

  const port = String(llm.port || 8080)
  const args = basename(binary).includes('llama-server')
    ? ['-m', model, '--host', '127.0.0.1', '--port', port, '--ctx-size', '8192', '--n-gpu-layers', '999']
    : ['serve', '-m', model, '--host', '127.0.0.1', '--port', port, '--ctx-size', '8192', '--n-gpu-layers', '999']

  processRef = spawn(binary, args, {
    cwd: dirname(model),
    env: { ...process.env, LLAMA_CACHE: join(dataDir(), 'models') }
  })
  message = 'Starting llama.cpp...'
  processRef.stdout.on('data', data => {
    const text = String(data)
    if (text.trim()) message = text.trim().slice(-240)
  })
  processRef.stderr.on('data', data => {
    const text = String(data)
    if (text.trim()) message = text.trim().slice(-240)
  })
  processRef.once('exit', code => {
    processRef = null
    message = code === 0 ? 'llama.cpp stopped.' : `llama.cpp exited with code ${code ?? 'unknown'}.`
  })
  return status(llm)
}

export async function stop(settings?: LocalLlmSettings): Promise<LocalLlmStatus> {
  if (processRef && !processRef.killed) processRef.kill()
  processRef = null
  message = 'llama.cpp stopped.'
  return status(settings)
}

function normalized(settings?: LocalLlmSettings): LocalLlmSettings {
  return { mode: settings?.mode || 'manual', port: settings?.port || 8080, binaryPath: settings?.binaryPath, modelPath: settings?.modelPath }
}

function detectLlamaBinary(): string | undefined {
  const resourceDir = typeof process.resourcesPath === 'string' ? process.resourcesPath : ''
  const bundled = [
    join(resourceDir, 'llama', 'llama-server'),
    join(resourceDir, 'llama-server'),
    join(app.getAppPath(), 'llama', 'llama-server')
  ]
  for (const file of bundled) if (file && existsSync(file)) return file
  for (const name of ['llama-server', 'llama']) {
    const found = spawnSync('which', [name], { encoding: 'utf8' }).stdout.trim()
    if (found) return found
  }
  return undefined
}

function safeSize(file: string): number {
  try { return statSync(file).size } catch { return 0 }
}

function downloadFile(url: string, tmp: string, dest: string, onProgress: (pct?: number) => void, redirects = 0): Promise<void> {
  return new Promise((resolve, reject) => {
    const req = get(url, res => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode ?? 0) && res.headers.location && redirects < 5) {
        res.resume()
        downloadFile(new URL(res.headers.location, url).toString(), tmp, dest, onProgress, redirects + 1).then(resolve, reject)
        return
      }
      if ((res.statusCode ?? 500) >= 400) {
        res.resume()
        reject(new Error(`Download failed (${res.statusCode})`))
        return
      }
      const total = Number(res.headers['content-length'] ?? 0)
      let done = 0
      const out = createWriteStream(tmp)
      res.on('data', chunk => {
        done += chunk.length
        onProgress(total > 0 ? done / total : undefined)
      })
      res.pipe(out)
      out.on('finish', () => {
        out.close(() => {
          try {
            renameSync(tmp, dest)
            resolve()
          } catch (err) {
            reject(err)
          }
        })
      })
      out.on('error', err => {
        try { unlinkSync(tmp) } catch { /* ignore */ }
        reject(err)
      })
    })
    req.on('error', reject)
  })
}
