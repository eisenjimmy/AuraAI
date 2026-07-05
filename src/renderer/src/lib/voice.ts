import type { VoiceSettings } from '@common/types'

// Per-persona text-to-speech via the OS speech engine (speechSynthesis —
// works on Windows and macOS with the voices installed on the machine).
//
// Ported pattern from the original Jarvis voice stack: sentences are
// flushed to the speech queue while tokens are still streaming (flush on
// sentence punctuation once ≥35 chars, or at ≥220 chars), so speech starts
// mid-generation instead of waiting for the full reply.

const FLUSH_MIN = 35
const FLUSH_MAX = 220

export class SpeechQueue {
  private buffer = ''
  private voice: VoiceSettings = { voice: '', rate: 1, pitch: 1 }
  private active = false

  setVoice(voice: VoiceSettings): void {
    this.voice = voice
  }

  /** Feed streaming text; speaks completed sentences as they form. */
  push(text: string): void {
    this.active = true
    this.buffer += text
    let idx = findFlushPoint(this.buffer)
    while (idx >= 0) {
      const segment = this.buffer.slice(0, idx + 1)
      this.buffer = this.buffer.slice(idx + 1)
      this.speak(segment)
      idx = findFlushPoint(this.buffer)
    }
  }

  /** Called when the stream ends: speak whatever is left. */
  flush(): void {
    if (this.buffer.trim()) this.speak(this.buffer)
    this.buffer = ''
    this.active = false
  }

  stop(): void {
    this.buffer = ''
    this.active = false
    window.speechSynthesis.cancel()
  }

  get speaking(): boolean {
    return this.active || window.speechSynthesis.speaking
  }

  private speak(text: string): void {
    const clean = normalizeForSpeech(text)
    if (!clean) return
    const utterance = new SpeechSynthesisUtterance(clean)
    utterance.rate = this.voice.rate
    utterance.pitch = this.voice.pitch
    if (this.voice.voice) {
      const match = listVoices().find(v => v.name === this.voice.voice)
      if (match) utterance.voice = match
      // No match (voice list not loaded yet, or an OS-specific name from
      // another machine): fall back to the system default rather than skip.
    }
    window.speechSynthesis.speak(utterance)
  }
}

function findFlushPoint(buffer: string): number {
  if (buffer.length >= FLUSH_MAX) {
    // Hard flush: break at the last space so we don't split a word.
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

// Strip markdown so the voice doesn't read syntax aloud
// (ported from the original NormalizeForSpeech).
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

// Voice lists load asynchronously on some platforms — keep a warm cache.
let cachedVoices: SpeechSynthesisVoice[] = []

function refreshVoices(): void {
  const voices = window.speechSynthesis.getVoices()
  if (voices.length > 0) cachedVoices = voices
}

if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
  refreshVoices()
  window.speechSynthesis.addEventListener('voiceschanged', refreshVoices)
}

export function listVoices(): SpeechSynthesisVoice[] {
  if (cachedVoices.length === 0) refreshVoices()
  return cachedVoices
}
