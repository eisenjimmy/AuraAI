import { KokoroTTS } from 'kokoro-js'
import { env as transformersEnv, type RawAudio } from '@huggingface/transformers'
import type { GenerateOptions } from 'kokoro-js'
import type { VoiceSettings } from '@common/types'
import { IS_KOREAN_EDITION } from '@common/edition'

const MODEL_ID = 'onnx-community/Kokoro-82M-v1.0-ONNX'
const LOCAL_MODEL_BASE = 'aura-kokoro://models'
const HF_MODEL_BASE = `https://huggingface.co/${MODEL_ID}/resolve/main/`
const FLUSH_MIN = 35
const FLUSH_MAX = 220
type KokoroVoiceId = NonNullable<GenerateOptions['voice']>
const DEFAULT_VOICE: KokoroVoiceId = 'af_heart'

export interface KokoroVoiceOption {
  id: KokoroVoiceId
  label: string
  language: string
  gender: 'Female' | 'Male'
}

export const KOKORO_VOICES: KokoroVoiceOption[] = [
  { id: 'af_heart', label: 'Heart', language: 'American English', gender: 'Female' },
  { id: 'af_bella', label: 'Bella', language: 'American English', gender: 'Female' },
  { id: 'af_nicole', label: 'Nicole', language: 'American English', gender: 'Female' },
  { id: 'af_kore', label: 'Kore', language: 'American English', gender: 'Female' },
  { id: 'af_nova', label: 'Nova', language: 'American English', gender: 'Female' },
  { id: 'af_sarah', label: 'Sarah', language: 'American English', gender: 'Female' },
  { id: 'am_fenrir', label: 'Fenrir', language: 'American English', gender: 'Male' },
  { id: 'am_michael', label: 'Michael', language: 'American English', gender: 'Male' },
  { id: 'am_puck', label: 'Puck', language: 'American English', gender: 'Male' },
  { id: 'am_echo', label: 'Echo', language: 'American English', gender: 'Male' },
  { id: 'bf_emma', label: 'Emma', language: 'British English', gender: 'Female' },
  { id: 'bf_alice', label: 'Alice', language: 'British English', gender: 'Female' },
  { id: 'bm_fable', label: 'Fable', language: 'British English', gender: 'Male' },
  { id: 'bm_george', label: 'George', language: 'British English', gender: 'Male' },
  { id: 'bm_daniel', label: 'Daniel', language: 'British English', gender: 'Male' }
]

type KokoroStatus = 'idle' | 'loading' | 'speaking' | 'error'
type StatusCallback = (status: KokoroStatus, message?: string) => void
type LevelCallback = (level: number) => void

let modelPromise: Promise<KokoroTTS> | null = null
let runtimeConfigured = false

function configureKokoroRuntime(): void {
  if (runtimeConfigured) return
  runtimeConfigured = true

  transformersEnv.allowLocalModels = true
  transformersEnv.allowRemoteModels = false
  transformersEnv.localModelPath = LOCAL_MODEL_BASE
  transformersEnv.useBrowserCache = false

  const originalFetch = window.fetch.bind(window)
  window.fetch = (input: Parameters<typeof window.fetch>[0], init?: Parameters<typeof window.fetch>[1]): Promise<Response> => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    if (url.startsWith(`${HF_MODEL_BASE}voices/`)) {
      const voiceFile = url.slice(`${HF_MODEL_BASE}voices/`.length)
      return originalFetch(`${LOCAL_MODEL_BASE}/${MODEL_ID}/voices/${voiceFile}`, init)
    }
    return originalFetch(input, init)
  }
}

function loadKokoro(onStatus?: StatusCallback): Promise<KokoroTTS> {
  configureKokoroRuntime()
  if (!modelPromise) {
    onStatus?.('loading', 'Loading Kokoro voice model...')
    modelPromise = KokoroTTS.from_pretrained(MODEL_ID, {
      dtype: 'q8',
      device: 'wasm'
    }).catch(err => {
      modelPromise = null
      throw err
    })
  }
  return modelPromise
}

export function warmKokoro(onStatus?: StatusCallback): Promise<void> {
  return loadKokoro(onStatus).then(() => undefined)
}

export class SpeechQueue {
  private buffer = ''
  private voice: VoiceSettings = { voice: DEFAULT_VOICE, rate: 1, pitch: 1 }
  private active = false
  private currentAudio: HTMLAudioElement | null = null
  private currentUrl: string | null = null
  private chain: Promise<void> = Promise.resolve()
  private generation = 0
  private onStatus?: StatusCallback
  private onLevel?: LevelCallback
  private stopLevelMeter?: () => void
  private finishCurrentPlayback?: () => void

  constructor(onStatus?: StatusCallback, onLevel?: LevelCallback) {
    this.onStatus = onStatus
    this.onLevel = onLevel
  }

  setStatusCallback(onStatus?: StatusCallback): void {
    this.onStatus = onStatus
  }

  setLevelCallback(onLevel?: LevelCallback): void {
    this.onLevel = onLevel
  }

  setVoice(voice: VoiceSettings): void {
    this.voice = voice.voice ? voice : { ...voice, voice: DEFAULT_VOICE }
  }

  push(text: string): void {
    this.active = true
    this.buffer += text
    let idx = findFlushPoint(this.buffer)
    while (idx >= 0) {
      const segment = this.buffer.slice(0, idx + 1)
      this.buffer = this.buffer.slice(idx + 1)
      this.enqueue(segment)
      idx = findFlushPoint(this.buffer)
    }
  }

  flush(): void {
    if (this.buffer.trim()) this.enqueue(this.buffer)
    this.buffer = ''
    this.active = false
  }

  stop(): void {
    this.generation += 1
    this.buffer = ''
    this.active = false
    this.stopLevelMeter?.()
    this.stopLevelMeter = undefined
    this.finishCurrentPlayback?.()
    this.finishCurrentPlayback = undefined
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio.src = ''
      this.currentAudio = null
    }
    this.revokeCurrentUrl()
    this.onLevel?.(0)
    this.onStatus?.('idle')
  }

  get speaking(): boolean {
    return this.active || this.currentAudio !== null
  }

  private enqueue(text: string): void {
    const clean = normalizeForSpeech(text)
    if (!clean) return
    const token = this.generation
    const voice = normalizeVoiceId(this.voice.voice)
    const speed = clamp(this.voice.rate || 1, 0.5, 1.6)

    this.chain = this.chain
      .then(async () => {
        if (token !== this.generation) return
        this.onStatus?.('loading', 'Loading Kokoro voice model...')
        const tts = await loadKokoro(this.onStatus)
        if (token !== this.generation) return
        this.onStatus?.('speaking')
        const audio = await tts.generate(clean, { voice, speed })
        if (token !== this.generation) return
        await this.play(audio, token)
      })
      .catch(err => {
        console.error('Kokoro TTS failed', err)
        const raw = err instanceof Error ? err.message : String(err)
        const message = raw.toLowerCase().includes('failed to fetch')
          ? IS_KOREAN_EDITION
            ? '앱에 포함된 Kokoro 음성 모델을 불러올 수 없습니다. 아우라 AI를 다시 설치하거나 최신 릴리즈를 사용해 주세요.'
            : 'Kokoro voice model could not be loaded from the bundled app files. Reinstall Aura AI or try the latest release.'
          : raw
        this.onStatus?.('error', message)
      })
  }

  private async play(audio: RawAudio, token: number): Promise<void> {
    this.revokeCurrentUrl()
    const url = URL.createObjectURL(audio.toBlob())
    this.currentUrl = url
    const player = new Audio(url)
    this.currentAudio = player
    const stopMeter = this.monitorPlaybackLevel(player)
    this.stopLevelMeter = stopMeter

    await new Promise<void>((resolve, reject) => {
      this.finishCurrentPlayback = resolve
      player.onended = () => resolve()
      player.onerror = () => reject(new Error('Audio playback failed.'))
      void player.play().catch(reject)
    }).finally(() => {
      stopMeter()
      if (this.stopLevelMeter === stopMeter) this.stopLevelMeter = undefined
      this.finishCurrentPlayback = undefined
      if (this.currentAudio === player) this.currentAudio = null
      if (token === this.generation) this.onStatus?.('idle')
      this.onLevel?.(0)
      this.revokeCurrentUrl()
    })
  }

  private monitorPlaybackLevel(player: HTMLAudioElement): () => void {
    const AudioContextCtor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    if (!AudioContextCtor || !this.onLevel) return () => undefined

    const ctx = new AudioContextCtor()
    const analyser = ctx.createAnalyser()
    analyser.fftSize = 256
    analyser.smoothingTimeConstant = 0.72
    const source = ctx.createMediaElementSource(player)
    source.connect(analyser)
    analyser.connect(ctx.destination)

    const data = new Uint8Array(analyser.frequencyBinCount)
    let frame = 0
    const tick = (): void => {
      analyser.getByteTimeDomainData(data)
      let sum = 0
      for (const value of data) {
        const centered = (value - 128) / 128
        sum += centered * centered
      }
      const rms = Math.sqrt(sum / data.length)
      this.onLevel?.(clamp(rms * 3.2, 0, 1))
      frame = window.requestAnimationFrame(tick)
    }
    tick()

    return () => {
      if (frame) window.cancelAnimationFrame(frame)
      this.onLevel?.(0)
      void ctx.close().catch(() => undefined)
    }
  }

  private revokeCurrentUrl(): void {
    if (!this.currentUrl) return
    URL.revokeObjectURL(this.currentUrl)
    this.currentUrl = null
  }
}

function normalizeVoiceId(voice: string): KokoroVoiceId {
  const match = KOKORO_VOICES.find(v => v.id === voice)
  return match?.id ?? DEFAULT_VOICE
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value))
}

function findFlushPoint(buffer: string): number {
  if (buffer.length >= FLUSH_MAX) {
    const space = buffer.lastIndexOf(' ', FLUSH_MAX)
    return space > 0 ? space : FLUSH_MAX - 1
  }
  if (buffer.length < FLUSH_MIN) return -1
  for (let i = buffer.length - 1; i >= FLUSH_MIN - 1; i--) {
    if ('.!?;:'.includes(buffer[i]) && (i === buffer.length - 1 || /\s/.test(buffer[i + 1]))) {
      return i
    }
  }
  return -1
}

export function normalizeForSpeech(text: string): string {
  return text
    .replace(/```[\s\S]*?```/g, ' code block omitted. ')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/https?:\/\/\S+/g, ' a link ')
    .replace(/[*_#>|]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}
