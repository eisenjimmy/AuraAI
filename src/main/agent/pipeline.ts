import { randomUUID } from 'crypto'
import { readFileSync } from 'fs'
import type { AppSettings, ChatMessage, Persona, StreamEvent, ActivityEvent, MemoryNote } from '@common/types'
import type { ChatProvider, ProviderContentPart, ProviderMessage } from '../providers/types'
import { createProvider } from '../providers'
import { MemoryVault, defaultVaultPath, personaVaultPath } from '../memory/vault'
import { extractMemory } from '../memory/extractor'
import { webSearch, shouldSearch } from '../search/webSearch'
import { buildSystemPrompt } from './prompt'
import { runToolLoop } from './tools'
import { loadChat, appendMessage, updateMessage } from '../chats'
import { IS_KOREAN_EDITION } from '@common/edition'

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

  private globalVault(settings: AppSettings): MemoryVault {
    return new MemoryVault(settings.memoryVaultPath || defaultVaultPath())
  }

  private personaVault(settings: AppSettings, personaId: string): MemoryVault {
    const base = settings.memoryVaultPath || defaultVaultPath()
    return new MemoryVault(personaVaultPath(personaId, base))
  }

  async send(personaId: string, text: string, attachments = [] as ChatMessage['attachments']): Promise<void> {
    const settings = this.getSettings()
    const persona = this.getPersona(personaId)
    if (!persona) throw new Error(`Unknown persona: ${personaId}`)

    // One generation per persona: a new send cancels the previous one.
    this.active.get(personaId)?.abort()

    const userMsg: ChatMessage = {
      id: randomUUID(),
      role: 'user',
      content: text,
      attachments,
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
    const globalVault = this.globalVault(settings)
    const personaVault = this.personaVault(settings, personaId)

    const pushActivity = (event: ActivityEvent): void => {
      reply.activity!.push(event)
      this.emit({ type: 'activity', personaId, messageId: reply.id, event })
    }

    try {
      // 1. Memory recall (deterministic, always on when enabled).
      let memories: MemoryNote[] = []
      if (settings.memoryEnabled) {
        const [globalMemories, personaMemories] = await Promise.all([
          globalVault.recall(text, 3, provider).then(notes => notes.filter(isSharedMemory)).catch(() => []),
          personaVault.recall(text, 4, provider).catch(() => [])
        ])
        memories = [...personaMemories, ...globalMemories].slice(0, 5)
        if (memories.length > 0) {
          pushActivity({
            kind: 'memory-recall',
            label: IS_KOREAN_EDITION
              ? `기억 ${memories.length}개를 떠올림`
              : memories.length === 1 ? 'Remembered 1 thing' : `Remembered ${memories.length} things`,
            detail: memories.map(m => m.title).join(', ')
          })
        }
      }

      // 2. Web search (deterministic heuristic) - skipped in tools mode,
      // where the model calls web_search itself.
      let searchResults = null
      if (!settings.toolsMode && settings.webSearchEnabled && shouldSearch(text)) {
        pushActivity({ kind: 'search', label: IS_KOREAN_EDITION ? '웹 검색 중...' : 'Searching the web...' })
        searchResults = await webSearch(text, settings, 5).catch(() => null)
        if (searchResults && searchResults.length > 0) {
          pushActivity({
            kind: 'search',
            label: IS_KOREAN_EDITION ? `검색 결과 ${searchResults.length}개 발견` : `Found ${searchResults.length} results`,
            detail: searchResults.map(r => r.title).join(' | ')
          })
        }
      }

      // 3. Build prompt + history.
      const system = buildSystemPrompt(persona, settings, memories, searchResults)
      const history = buildHistory(personaId, reply.id, userMsg.id)

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
          { settings, vault: personaVault, globalVault, personaId, provider, onActivity: pushActivity },
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
        void this.extractInBackground(provider, settings, personaVault, persona, personaId, text, reply)
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
        this.emit({ type: 'error', personaId, messageId: reply.id, message: reply.error ?? (IS_KOREAN_EDITION ? '알 수 없는 오류' : 'Unknown error'), content: reply.content })
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
        const event: ActivityEvent = {
          kind: 'memory-save',
          label: IS_KOREAN_EDITION ? `기억함: ${result.note.title}` : `Remembered: ${result.note.title}`
        }
        reply.activity = [...(reply.activity ?? []), event]
        updateMessage(personaId, reply)
        this.emit({ type: 'activity', personaId, messageId: reply.id, event })
      }
    } catch { /* extraction must never break chat */ }
  }
}

function isSharedMemory(note: MemoryNote): boolean {
  return !note.source || note.source === 'global' || note.source === 'onboarding'
}

function buildHistory(personaId: string, excludeMessageId: string, imageMessageId: string): ProviderMessage[] {
  const all = loadChat(personaId).filter(m => m.id !== excludeMessageId && !m.error && (m.content || m.attachments?.length))
  const recent = all.slice(-HISTORY_MESSAGES)
  // Trim to a character budget, keeping the newest messages.
  let total = 0
  const kept: ProviderMessage[] = []
  for (let i = recent.length - 1; i >= 0; i--) {
    total += recent[i].content.length + ((recent[i].attachments?.length ?? 0) * 120)
    if (total > HISTORY_CHAR_BUDGET && kept.length > 0) break
    kept.unshift({
      role: recent[i].role,
      content: messageContent(recent[i], recent[i].id === imageMessageId)
    })
  }
  // Anthropic (and some others) require the history to start with a user
  // turn — trimming can leave an assistant message first, so drop leaders.
  while (kept.length > 0 && kept[0].role !== 'user') kept.shift()
  return kept
}

function messageContent(message: ChatMessage, includeImageBytes: boolean): string | ProviderContentPart[] {
  const attachments = message.attachments ?? []
  if (attachments.length === 0) return message.content
  if (!includeImageBytes) {
    const names = attachments.map(a => a.name).join(', ')
    return IS_KOREAN_EDITION
      ? `${message.content}\n\n[첨부 이미지: ${names}]`.trim()
      : `${message.content}\n\n[Attached image${attachments.length === 1 ? '' : 's'}: ${names}]`.trim()
  }

  const parts: ProviderContentPart[] = []
  if (message.content.trim()) parts.push({ type: 'text', text: message.content })
  for (const attachment of attachments) {
    try {
      parts.push({
        type: 'image',
        mimeType: attachment.mimeType,
        data: readFileSync(attachment.path).toString('base64'),
        name: attachment.name
      })
    } catch {
      parts.push({ type: 'text', text: IS_KOREAN_EDITION ? `[이미지를 불러올 수 없음: ${attachment.name}]` : `[Image unavailable: ${attachment.name}]` })
    }
  }
  return parts
}

function humanizeProviderError(err: unknown, settings: AppSettings): string {
  const raw = err instanceof Error ? err.message : String(err)
  const provider = settings.provider.provider
  const lower = raw.toLowerCase()
  if (lower.includes('fetch failed') || lower.includes('econnrefused') || lower.includes('enotfound') || lower.includes('network')) {
    if (provider === 'local') {
      return IS_KOREAN_EDITION
        ? `로컬 AI 서버(${settings.provider.baseUrl || 'localhost'})에 연결할 수 없습니다. Ollama 또는 사용 중인 서버가 실행 중인가요?`
        : `Can't reach the local AI server at ${settings.provider.baseUrl || 'localhost'}. Is Ollama (or your server) running?`
    }
    return IS_KOREAN_EDITION
      ? `${provider} API에 연결할 수 없습니다. 인터넷 연결을 확인하세요.`
      : `Can't reach the ${provider} API. Check your internet connection.`
  }
  if (lower.includes('401') || lower.includes('403') || lower.includes('authentication') || lower.includes('invalid x-api-key') || lower.includes('api key')) {
    return IS_KOREAN_EDITION
      ? `${provider} API가 키를 거부했습니다. 설정 → AI 제공자에서 확인하세요. (${raw.slice(0, 140)})`
      : `The ${provider} API rejected your key. Check it in Settings → AI Provider. (${raw.slice(0, 140)})`
  }
  if (lower.includes('404') && provider === 'local') {
    return IS_KOREAN_EDITION
      ? `로컬 서버에서 "${settings.provider.model}" 모델을 찾을 수 없습니다. 먼저 모델을 받아오세요. 예: "ollama pull ${settings.provider.model}"`
      : `Model "${settings.provider.model}" not found on the local server. Pull it first (e.g. "ollama pull ${settings.provider.model}").`
  }
  if (lower.includes('429')) {
    return IS_KOREAN_EDITION
      ? `${provider} API 사용량 제한에 걸렸습니다. 잠시 후 다시 시도하세요.`
      : `Rate limited by the ${provider} API — give it a moment and try again.`
  }
  return raw.length > 300 ? raw.slice(0, 300) + '…' : raw
}
