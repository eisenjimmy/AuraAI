import { randomUUID } from 'crypto'
import type { AppSettings, ChatMessage, Persona, StreamEvent, ActivityEvent, MemoryNote } from '@common/types'
import type { ChatProvider, ProviderMessage } from '../providers/types'
import { createProvider } from '../providers'
import { MemoryVault, defaultVaultPath } from '../memory/vault'
import { extractMemory } from '../memory/extractor'
import { webSearch, shouldSearch } from '../search/webSearch'
import { buildSystemPrompt } from './prompt'
import { runToolLoop } from './tools'
import { loadChat, appendMessage, updateMessage } from '../chats'

// The conversation pipeline. Default mode is deterministic host code
// (the original Jarvis design goal): recall memories, maybe search, build
// the prompt, stream the reply, then extract memories in the background.
// Tools mode (opt-in) hands those decisions to the model instead.

const HISTORY_MESSAGES = 30
const HISTORY_CHAR_BUDGET = 24_000

export class ChatPipeline {
  /** One in-flight generation per persona. */
  private active = new Map<string, AbortController>()

  constructor(
    private getSettings: () => AppSettings,
    private getPersona: (id: string) => Persona | undefined,
    private emit: (ev: StreamEvent) => void
  ) {}

  stop(personaId?: string): void {
    if (personaId) {
      this.active.get(personaId)?.abort()
      this.active.delete(personaId)
    } else {
      for (const controller of this.active.values()) controller.abort()
      this.active.clear()
    }
  }

  activePersonas(): string[] {
    return [...this.active.keys()]
  }

  private vault(settings: AppSettings): MemoryVault {
    return new MemoryVault(settings.memoryVaultPath || defaultVaultPath())
  }

  async send(personaId: string, text: string): Promise<void> {
    const settings = this.getSettings()
    const persona = this.getPersona(personaId)
    if (!persona) throw new Error(`Unknown persona: ${personaId}`)

    // One generation per persona: a new send cancels the previous one.
    this.active.get(personaId)?.abort()

    const userMsg: ChatMessage = {
      id: randomUUID(),
      role: 'user',
      content: text,
      ts: Date.now()
    }
    appendMessage(personaId, userMsg)

    const reply: ChatMessage = {
      id: randomUUID(),
      role: 'assistant',
      content: '',
      ts: Date.now(),
      personaId,
      activity: [],
      pending: true
    }
    appendMessage(personaId, reply)
    this.emit({ type: 'start', personaId, messageId: reply.id })

    const controller = new AbortController()
    this.active.set(personaId, controller)
    const signal = controller.signal
    const provider = createProvider(settings.provider)
    const vault = this.vault(settings)

    const pushActivity = (event: ActivityEvent): void => {
      reply.activity!.push(event)
      this.emit({ type: 'activity', personaId, messageId: reply.id, event })
    }

    try {
      // 1. Memory recall (deterministic, always on when enabled).
      let memories: MemoryNote[] = []
      if (settings.memoryEnabled) {
        memories = await vault.recall(text, 4, provider).catch(() => [])
        if (memories.length > 0) {
          pushActivity({
            kind: 'memory-recall',
            label: memories.length === 1 ? 'Remembered 1 thing' : `Remembered ${memories.length} things`,
            detail: memories.map(m => m.title).join(', ')
          })
        }
      }

      // 2. Web search (deterministic heuristic) - skipped in tools mode,
      // where the model calls web_search itself.
      let searchResults = null
      if (!settings.toolsMode && settings.webSearchEnabled && shouldSearch(text)) {
        pushActivity({ kind: 'search', label: 'Searching the web...' })
        searchResults = await webSearch(text, settings, 5).catch(() => null)
        if (searchResults && searchResults.length > 0) {
          pushActivity({
            kind: 'search',
            label: `Found ${searchResults.length} results`,
            detail: searchResults.map(r => r.title).join(' | ')
          })
        }
      }

      // 3. Build prompt + history.
      const system = buildSystemPrompt(persona, settings, memories, searchResults)
      const history = buildHistory(personaId, reply.id)

      // 4. Stream the reply.
      const onText = (chunk: string): void => {
        reply.content += chunk
        this.emit({ type: 'delta', personaId, messageId: reply.id, text: chunk })
      }

      if (settings.toolsMode) {
        await runToolLoop(
          {
            model: settings.provider.model,
            system,
            messages: history,
            maxTokens: 2048,
            signal
          },
          { settings, vault, personaId, provider, onActivity: pushActivity },
          onText
        )
      } else {
        for await (const ev of provider.streamChat({
          model: settings.provider.model,
          system,
          messages: history,
          maxTokens: 2048,
          signal
        })) {
          if (ev.type === 'text') onText(ev.text)
        }
      }

      reply.pending = false
      updateMessage(personaId, reply)
      this.emit({ type: 'done', personaId, messageId: reply.id, content: reply.content })

      // 5. Background memory extraction (fire and forget, never blocks chat).
      if (settings.memoryEnabled && !settings.toolsMode && reply.content) {
        void this.extractInBackground(provider, settings, vault, persona, personaId, text, reply)
      }
    } catch (err) {
      const aborted = signal.aborted
      reply.pending = false
      if (!aborted) {
        reply.error = humanizeProviderError(err, settings)
      }
      updateMessage(personaId, reply)
      if (aborted) {
        this.emit({ type: 'done', personaId, messageId: reply.id, content: reply.content })
      } else {
        this.emit({ type: 'error', personaId, messageId: reply.id, message: reply.error ?? 'Unknown error', content: reply.content })
      }
    } finally {
      if (this.active.get(personaId) === controller) this.active.delete(personaId)
    }
  }

  private async extractInBackground(
    provider: ChatProvider,
    settings: AppSettings,
    vault: MemoryVault,
    persona: Persona,
    personaId: string,
    userText: string,
    reply: ChatMessage
  ): Promise<void> {
    try {
      const result = await extractMemory(
        provider,
        settings.provider.model,
        vault,
        persona.name,
        personaId,
        userText,
        reply.content
      )
      if (result.saved && result.note) {
        const event: ActivityEvent = { kind: 'memory-save', label: `Remembered: ${result.note.title}` }
        reply.activity = [...(reply.activity ?? []), event]
        updateMessage(personaId, reply)
        this.emit({ type: 'activity', personaId, messageId: reply.id, event })
      }
    } catch { /* extraction must never break chat */ }
  }
}

function buildHistory(personaId: string, excludeMessageId: string): ProviderMessage[] {
  const all = loadChat(personaId).filter(m => m.id !== excludeMessageId && !m.error && m.content)
  const recent = all.slice(-HISTORY_MESSAGES)
  // Trim to a character budget, keeping the newest messages.
  let total = 0
  const kept: ProviderMessage[] = []
  for (let i = recent.length - 1; i >= 0; i--) {
    total += recent[i].content.length
    if (total > HISTORY_CHAR_BUDGET && kept.length > 0) break
    kept.unshift({ role: recent[i].role, content: recent[i].content })
  }
  // Anthropic (and some others) require the history to start with a user
  // turn — trimming can leave an assistant message first, so drop leaders.
  while (kept.length > 0 && kept[0].role !== 'user') kept.shift()
  return kept
}

function humanizeProviderError(err: unknown, settings: AppSettings): string {
  const raw = err instanceof Error ? err.message : String(err)
  const provider = settings.provider.provider
  const lower = raw.toLowerCase()
  if (lower.includes('fetch failed') || lower.includes('econnrefused') || lower.includes('enotfound') || lower.includes('network')) {
    if (provider === 'local') {
      return `Can't reach the local AI server at ${settings.provider.baseUrl || 'localhost'}. Is Ollama (or your server) running?`
    }
    return `Can't reach the ${provider} API. Check your internet connection.`
  }
  if (lower.includes('401') || lower.includes('403') || lower.includes('authentication') || lower.includes('invalid x-api-key') || lower.includes('api key')) {
    return `The ${provider} API rejected your key. Check it in Settings → AI Provider. (${raw.slice(0, 140)})`
  }
  if (lower.includes('404') && provider === 'local') {
    return `Model "${settings.provider.model}" not found on the local server. Pull it first (e.g. "ollama pull ${settings.provider.model}").`
  }
  if (lower.includes('429')) {
    return `Rate limited by the ${provider} API — give it a moment and try again.`
  }
  return raw.length > 300 ? raw.slice(0, 300) + '…' : raw
}
