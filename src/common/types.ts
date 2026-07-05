// Shared types between the Electron main process and the renderer.

// ---------- Providers ----------

export type ProviderId = 'local' | 'anthropic' | 'openai' | 'gemini'

export interface ProviderConfig {
  /** Which provider backs the chat. */
  provider: ProviderId
  /** Model id, e.g. "llama3.2", "claude-opus-4-8", "gpt-4o", "gemini-2.0-flash" */
  model: string
  /** API key for cloud providers (unused for local). */
  apiKey?: string
  /** Base URL for the local OpenAI-compatible server (Ollama, LM Studio, llama.cpp). */
  baseUrl?: string
}

export interface ProviderPreset {
  id: ProviderId
  label: string
  description: string
  defaultModel: string
  models: string[]
  needsApiKey: boolean
  defaultBaseUrl?: string
}

// ---------- Personas ----------

export interface VoiceSettings {
  /** Name of the speechSynthesis voice; empty = system default. */
  voice: string
  rate: number
  pitch: number
}

export interface Persona {
  id: string
  name: string
  tagline: string
  /** Accent color used for the avatar ring and name. */
  color: string
  /** Full personality prompt (the "person"). */
  prompt: string
  /** Path to a user-uploaded avatar image; empty = blank placeholder with initial. */
  avatar: string
  voice: VoiceSettings
  /** Built-in personas can be edited but not deleted. */
  builtIn: boolean
}

// ---------- Chat ----------

export type Role = 'user' | 'assistant'

export interface ChatMessage {
  id: string
  role: Role
  content: string
  /** Unix ms. */
  ts: number
  /** Persona that authored an assistant message. */
  personaId?: string
  /** Activity that happened while producing this message (search, memory...). */
  activity?: ActivityEvent[]
  /** True while streaming. */
  pending?: boolean
  error?: string
}

export interface ActivityEvent {
  kind: 'search' | 'memory-recall' | 'memory-save' | 'fetch' | 'tool'
  label: string
  detail?: string
}

// ---------- Memory (Obsidian-style vault) ----------

export interface MemoryNote {
  /** Kebab-case slug; also the filename ("favorite-food.md"). */
  slug: string
  title: string
  /** user | fact | preference | event | relationship */
  type: string
  importance: number
  /** Body markdown (may contain [[wikilinks]]). */
  body: string
  createdAt: string
  updatedAt: string
  /** Persona that learned this memory. */
  source?: string
}

// ---------- Settings ----------

export interface AppSettings {
  onboarded: boolean
  userName: string
  /** Free-form "about me" the user gave during onboarding. */
  userBio: string
  provider: ProviderConfig
  /** Persona id that opens on launch. */
  activePersonaId: string
  theme: 'dark' | 'light'
  /** Text-to-speech for assistant replies. */
  voiceEnabled: boolean
  /** Web search + current awareness. */
  webSearchEnabled: boolean
  /** Optional Brave/Tavily key for higher-quality search. */
  searchApiKey?: string
  searchProvider: 'auto' | 'duckduckgo' | 'brave' | 'tavily'
  /** Automatic memory extraction after conversations. */
  memoryEnabled: boolean
  /** Folder holding the markdown memory vault; empty = default app folder. */
  memoryVaultPath?: string
  /** Advanced: model-driven tool loop. Off by default. */
  toolsMode: boolean
}

// ---------- IPC payloads ----------

export interface SendMessageRequest {
  personaId: string
  text: string
}

export type StreamEvent =
  | { type: 'start'; personaId: string; messageId: string }
  | { type: 'delta'; personaId: string; messageId: string; text: string }
  | { type: 'activity'; personaId: string; messageId: string; event: ActivityEvent }
  /** done/error carry the authoritative final content so the renderer can
      heal any divergence (e.g. it reloaded mid-stream and missed deltas). */
  | { type: 'done'; personaId: string; messageId: string; content: string }
  | { type: 'error'; personaId: string; messageId: string; message: string; content: string }

export interface TestProviderResult {
  ok: boolean
  message: string
  models?: string[]
}

// ---------- The bridge exposed by the preload script ----------

export interface AuraApi {
  getSettings(): Promise<AppSettings>
  saveSettings(settings: AppSettings): Promise<void>
  getPersonas(): Promise<Persona[]>
  savePersona(persona: Persona): Promise<void>
  resetPersona(id: string): Promise<Persona>
  pickAvatar(personaId: string): Promise<string | null>

  getChat(personaId: string): Promise<ChatMessage[]>
  clearChat(personaId: string): Promise<void>
  sendMessage(req: SendMessageRequest): Promise<void>
  stopGeneration(personaId?: string): Promise<void>
  /** Persona ids that currently have a generation in flight. */
  getActiveGenerations(): Promise<string[]>
  onStream(cb: (ev: StreamEvent) => void): () => void

  listMemories(): Promise<MemoryNote[]>
  deleteMemory(slug: string): Promise<void>
  saveMemory(note: MemoryNote): Promise<void>
  openMemoryVault(): Promise<void>

  testProvider(config: ProviderConfig): Promise<TestProviderResult>
  listLocalModels(baseUrl: string): Promise<string[]>
}
