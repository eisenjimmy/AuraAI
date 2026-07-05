import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, renameSync } from 'fs'
import { join } from 'path'
import type { AppSettings, Persona } from '@common/types'
import { DEFAULT_PERSONAS } from '@common/personas'

// Tiny JSON-file persistence. Everything Aura stores is a plain file the
// user can read: config.json, personas.json, chats/*.json and the markdown
// memory vault.

export function dataDir(): string {
  const dir = app.getPath('userData')
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  return dir
}

function readJson<T>(file: string, fallback: T): T {
  try {
    if (!existsSync(file)) return fallback
    return { ...fallback, ...JSON.parse(readFileSync(file, 'utf8')) }
  } catch {
    // Corrupt file: keep a copy so the user never loses data, then start fresh.
    try { copyFileSync(file, file + '.bak') } catch { /* ignore */ }
    return fallback
  }
}

function writeJson(file: string, value: unknown): void {
  const tmp = file + '.tmp'
  writeFileSync(tmp, JSON.stringify(value, null, 2), 'utf8')
  renameSync(tmp, file)
}

export const DEFAULT_SETTINGS: AppSettings = {
  onboarded: false,
  userName: '',
  userBio: '',
  provider: { provider: 'local', model: '', baseUrl: 'http://localhost:11434/v1' },
  activePersonaId: 'nova',
  theme: 'dark',
  voiceEnabled: false,
  webSearchEnabled: true,
  searchProvider: 'auto',
  memoryEnabled: true,
  toolsMode: false
}

export function loadSettings(): AppSettings {
  return readJson(join(dataDir(), 'config.json'), DEFAULT_SETTINGS)
}

export function saveSettings(settings: AppSettings): void {
  writeJson(join(dataDir(), 'config.json'), settings)
}

// Personas: built-ins merged with user edits stored in personas.json.
// Users can edit any field of a built-in (name, prompt, avatar, voice)
// and reset it back to the default.

interface PersonaOverrides {
  [id: string]: Partial<Persona>
}

function personasFile(): string {
  return join(dataDir(), 'personas.json')
}

export function loadPersonas(): Persona[] {
  const overrides = readJson<PersonaOverrides>(personasFile(), {})
  const merged = DEFAULT_PERSONAS.map(p => ({ ...p, ...(overrides[p.id] ?? {}), id: p.id, builtIn: true }))
  // Custom personas the user created from scratch.
  for (const [id, o] of Object.entries(overrides)) {
    if (!DEFAULT_PERSONAS.some(p => p.id === id) && o.name && o.prompt) {
      merged.push({
        id,
        name: o.name,
        tagline: o.tagline ?? '',
        color: o.color ?? '#7a8290',
        prompt: o.prompt,
        avatar: o.avatar ?? '',
        voice: o.voice ?? { voice: '', rate: 1, pitch: 1 },
        builtIn: false
      })
    }
  }
  return merged
}

export function savePersona(persona: Persona): void {
  const overrides = readJson<PersonaOverrides>(personasFile(), {})
  const base = DEFAULT_PERSONAS.find(p => p.id === persona.id)
  if (base) {
    // Store only the fields that differ from the built-in default.
    const diff: Partial<Persona> = {}
    for (const key of ['name', 'tagline', 'color', 'prompt', 'avatar', 'voice'] as const) {
      if (JSON.stringify(persona[key]) !== JSON.stringify(base[key])) {
        ;(diff as Record<string, unknown>)[key] = persona[key]
      }
    }
    if (Object.keys(diff).length === 0) delete overrides[persona.id]
    else overrides[persona.id] = diff
  } else {
    overrides[persona.id] = persona
  }
  writeJson(personasFile(), overrides)
}

export function resetPersona(id: string): Persona {
  const overrides = readJson<PersonaOverrides>(personasFile(), {})
  delete overrides[id]
  writeJson(personasFile(), overrides)
  const base = DEFAULT_PERSONAS.find(p => p.id === id)
  if (!base) throw new Error(`Unknown persona: ${id}`)
  return base
}
