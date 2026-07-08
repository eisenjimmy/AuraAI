import type { ChatProvider, ChatStreamOptions, ProviderContent, ProviderEvent, ProviderMessage, ToolCall } from './types'
import { IS_KOREAN_EDITION } from '@common/edition'

// One client for every OpenAI-compatible endpoint: Ollama (/v1), LM Studio,
// llama.cpp server, and api.openai.com itself. Streaming via SSE.

export class OpenAICompatProvider implements ChatProvider {
  embeddingId?: string

  constructor(
    private baseUrl: string,
    private apiKey?: string,
    private embeddingModel?: string
  ) {
    this.baseUrl = baseUrl.replace(/\/+$/, '')
    if (embeddingModel) this.embeddingId = `${this.baseUrl}#${embeddingModel}`
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { 'Content-Type': 'application/json' }
    if (this.apiKey) h['Authorization'] = `Bearer ${this.apiKey}`
    return h
  }

  async *streamChat(opts: ChatStreamOptions): AsyncGenerator<ProviderEvent> {
    const messages: Record<string, unknown>[] = [{ role: 'system', content: opts.system }]
    for (const m of opts.messages) {
      if (m.role === 'tool') {
        messages.push({ role: 'tool', tool_call_id: m.toolCallId, content: textContent(m.content) })
      } else if (m.role === 'assistant' && m.toolCalls?.length) {
        messages.push({
          role: 'assistant',
          content: textContent(m.content) || null,
          tool_calls: m.toolCalls.map(c => ({
            id: c.id,
            type: 'function',
            function: { name: c.name, arguments: c.args }
          }))
        })
      } else {
        messages.push({ role: m.role, content: openAIContent(m.content) })
      }
    }

    const body: Record<string, unknown> = {
      model: opts.model,
      messages,
      stream: true
    }
    // api.openai.com rejects max_tokens on newer models (gpt-5/o-series);
    // local OpenAI-compatible servers still expect max_tokens.
    if (this.baseUrl.startsWith('https://api.openai.com')) {
      body.max_completion_tokens = opts.maxTokens ?? 2048
    } else {
      body.max_tokens = opts.maxTokens ?? 2048
    }
    if (opts.tools?.length) {
      body.tools = opts.tools.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters }
      }))
    }

    const res = await fetch(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify(body),
      signal: opts.signal
    })
    if (!res.ok || !res.body) {
      throw new Error(`${IS_KOREAN_EDITION ? '채팅 요청 실패' : 'Chat request failed'} (${res.status}): ${(await res.text()).slice(0, 300)}`)
    }

    // Accumulate streamed tool calls by index.
    const toolAcc = new Map<number, { id: string; name: string; args: string }>()

    const handleLine = (line: string): { type: 'text'; text: string } | null => {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data:')) return null
      const payload = trimmed.slice(5).trim()
      if (payload === '[DONE]') return null
      let json: any
      try { json = JSON.parse(payload) } catch { return null }
      const delta = json.choices?.[0]?.delta
      if (!delta) return null
      if (Array.isArray(delta.tool_calls)) {
        for (const tc of delta.tool_calls) {
          const idx = tc.index ?? 0
          const acc = toolAcc.get(idx) ?? { id: '', name: '', args: '' }
          if (tc.id) acc.id = tc.id
          if (tc.function?.name) acc.name += tc.function.name
          if (tc.function?.arguments) acc.args += tc.function.arguments
          toolAcc.set(idx, acc)
        }
      }
      if (typeof delta.content === 'string' && delta.content.length) {
        return { type: 'text', text: delta.content }
      }
      return null
    }

    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        if (buffer.length > 4_000_000) throw new Error(IS_KOREAN_EDITION ? '스트리밍 응답이 버퍼 한도를 초과했습니다' : 'Streaming response exceeded buffer limit')
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        for (const line of lines) {
          const ev = handleLine(line)
          if (ev) yield ev
        }
      }
      // Flush the decoder and any final line without a trailing newline.
      buffer += decoder.decode()
      if (buffer.trim()) {
        const ev = handleLine(buffer)
        if (ev) yield ev
      }
    } finally {
      reader.releaseLock()
    }

    if (toolAcc.size > 0) {
      const calls: ToolCall[] = [...toolAcc.entries()]
        .sort((a, b) => a[0] - b[0])
        .map(([i, c]) => ({ id: c.id || `call_${i}`, name: c.name, args: c.args || '{}' }))
      yield { type: 'toolCalls', calls }
    }
    yield { type: 'done' }
  }

  async embed(text: string): Promise<number[] | null> {
    // OpenAI-style embeddings first; on Ollama fall back to /api/embeddings.
    const model = this.embeddingModel
    if (!model) return null
    try {
      const res = await fetch(`${this.baseUrl}/embeddings`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify({ model, input: text })
      })
      if (res.ok) {
        const json: any = await res.json()
        const vec = json.data?.[0]?.embedding
        if (Array.isArray(vec)) return vec
      }
    } catch { /* try Ollama native below */ }
    try {
      const ollamaRoot = this.baseUrl.replace(/\/v1$/, '')
      const res = await fetch(`${ollamaRoot}/api/embeddings`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model, prompt: text })
      })
      if (res.ok) {
        const json: any = await res.json()
        if (Array.isArray(json.embedding)) return json.embedding
      }
    } catch { /* embeddings are optional */ }
    return null
  }

  async listModels(): Promise<string[]> {
    const res = await fetch(`${this.baseUrl}/models`, { headers: this.headers() })
    if (!res.ok) throw new Error(`GET /models ${IS_KOREAN_EDITION ? '실패' : 'failed'} (${res.status})`)
    const json: any = await res.json()
    const ids = (json.data ?? []).map((m: any) => String(m.id))
    return ids.sort()
  }

  async test(): Promise<{ ok: boolean; message: string; models?: string[] }> {
    try {
      const models = await this.listModels()
      return {
        ok: true,
        message: IS_KOREAN_EDITION ? `연결됨. 사용 가능한 모델 ${models.length}개.` : `Connected. ${models.length} model(s) available.`,
        models
      }
    } catch (err) {
      return { ok: false, message: err instanceof Error ? err.message : String(err) }
    }
  }
}

function textContent(content: ProviderContent): string {
  if (typeof content === 'string') return content
  return content
    .filter(p => p.type === 'text')
    .map(p => p.text)
    .join('\n')
}

function openAIContent(content: ProviderContent): unknown {
  if (typeof content === 'string') return content
  return content.map(part => {
    if (part.type === 'text') return { type: 'text', text: part.text }
    return {
      type: 'image_url',
      image_url: { url: `data:${part.mimeType};base64,${part.data}` }
    }
  })
}
