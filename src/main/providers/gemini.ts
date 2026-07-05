import type { ChatProvider, ChatStreamOptions, ProviderEvent, ToolCall } from './types'

// Google Gemini via the REST generateContent API (SSE streaming).

export const GEMINI_MODELS = [
  'gemini-2.5-pro',
  'gemini-2.5-flash',
  'gemini-2.0-flash'
]

const BASE = 'https://generativelanguage.googleapis.com/v1beta'

export class GeminiProvider implements ChatProvider {
  embeddingId = 'gemini#text-embedding-004'

  constructor(private apiKey: string) {}

  async *streamChat(opts: ChatStreamOptions): AsyncGenerator<ProviderEvent> {
    const contents: Record<string, unknown>[] = []
    for (const m of opts.messages) {
      if (m.role === 'tool') {
        let response: unknown
        try { response = JSON.parse(m.content) } catch { response = { result: m.content } }
        contents.push({
          role: 'user',
          parts: [{ functionResponse: { name: m.name ?? 'tool', response } }]
        })
      } else if (m.role === 'assistant' && m.toolCalls?.length) {
        const parts: Record<string, unknown>[] = []
        if (m.content) parts.push({ text: m.content })
        for (const c of m.toolCalls) {
          let args: unknown = {}
          try { args = JSON.parse(c.args) } catch { /* keep {} */ }
          parts.push({ functionCall: { name: c.name, args } })
        }
        contents.push({ role: 'model', parts })
      } else {
        contents.push({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })
      }
    }

    const body: Record<string, unknown> = {
      systemInstruction: { parts: [{ text: opts.system }] },
      contents,
      generationConfig: { maxOutputTokens: opts.maxTokens ?? 2048 }
    }
    if (opts.tools?.length) {
      body.tools = [
        {
          functionDeclarations: opts.tools.map(t => ({
            name: t.name,
            description: t.description,
            parameters: t.parameters
          }))
        }
      ]
    }

    const url = `${BASE}/models/${encodeURIComponent(opts.model)}:streamGenerateContent?alt=sse`
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
      body: JSON.stringify(body),
      signal: opts.signal
    })
    if (!res.ok || !res.body) {
      throw new Error(`Gemini request failed (${res.status}): ${(await res.text()).slice(0, 300)}`)
    }

    const calls: ToolCall[] = []
    const textFromLine = (line: string): string | null => {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data:')) return null
      let json: any
      try { json = JSON.parse(trimmed.slice(5).trim()) } catch { return null }
      const parts = json.candidates?.[0]?.content?.parts
      if (!Array.isArray(parts)) return null
      let text = ''
      for (const part of parts) {
        if (typeof part.text === 'string') text += part.text
        if (part.functionCall) {
          calls.push({
            id: `call_${calls.length}_${Date.now()}`,
            name: String(part.functionCall.name ?? ''),
            args: JSON.stringify(part.functionCall.args ?? {})
          })
        }
      }
      return text.length ? text : null
    }

    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        if (buffer.length > 4_000_000) throw new Error('Streaming response exceeded buffer limit')
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        for (const line of lines) {
          const text = textFromLine(line)
          if (text) yield { type: 'text', text }
        }
      }
      buffer += decoder.decode()
      if (buffer.trim()) {
        const text = textFromLine(buffer)
        if (text) yield { type: 'text', text }
      }
    } finally {
      reader.releaseLock()
    }

    if (calls.length > 0) yield { type: 'toolCalls', calls }
    yield { type: 'done' }
  }

  async embed(text: string): Promise<number[] | null> {
    try {
      const res = await fetch(`${BASE}/models/text-embedding-004:embedContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify({ content: { parts: [{ text }] } })
      })
      if (!res.ok) return null
      const json: any = await res.json()
      return Array.isArray(json.embedding?.values) ? json.embedding.values : null
    } catch {
      return null
    }
  }

  async test(): Promise<{ ok: boolean; message: string; models?: string[] }> {
    try {
      const res = await fetch(`${BASE}/models?pageSize=50`, {
        headers: { 'x-goog-api-key': this.apiKey }
      })
      if (!res.ok) return { ok: false, message: `Gemini API returned ${res.status}` }
      const json: any = await res.json()
      const models = (json.models ?? [])
        .map((m: any) => String(m.name).replace(/^models\//, ''))
        .filter((n: string) => n.startsWith('gemini'))
      return { ok: true, message: 'Connected.', models: models.length ? models : GEMINI_MODELS }
    } catch (err) {
      return { ok: false, message: err instanceof Error ? err.message : String(err) }
    }
  }
}
