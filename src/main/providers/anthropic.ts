import type { ChatProvider, ChatStreamOptions, ProviderContent, ProviderEvent, ToolCall } from './types'
import { IS_KOREAN_EDITION } from '@common/edition'

// Anthropic Messages API via direct REST/SSE. Keeping this provider SDK-free
// avoids packaging npm SDK source files into the Electron main process.

export const ANTHROPIC_MODELS = [
  'claude-opus-4-8',
  'claude-sonnet-5',
  'claude-haiku-4-5'
]

const BASE_URL = 'https://api.anthropic.com/v1'
const API_VERSION = '2023-06-01'

type AnthropicBlock = Record<string, unknown>

export class AnthropicProvider implements ChatProvider {
  constructor(private apiKey: string) {}

  async *streamChat(opts: ChatStreamOptions): AsyncGenerator<ProviderEvent> {
    const messages: AnthropicBlock[] = []
    for (const m of opts.messages) {
      if (m.role === 'tool') {
        const block = {
          type: 'tool_result',
          tool_use_id: m.toolCallId ?? '',
          content: textContent(m.content)
        }
        const last = messages[messages.length - 1]
        const lastContent = last?.content
        if (
          last?.role === 'user' &&
          Array.isArray(lastContent) &&
          lastContent.every(b => isTypedBlock(b, 'tool_result'))
        ) {
          lastContent.push(block)
        } else {
          messages.push({ role: 'user', content: [block] })
        }
      } else if (m.role === 'assistant' && m.toolCalls?.length) {
        const blocks: AnthropicBlock[] = []
        const text = textContent(m.content)
        if (text) blocks.push({ type: 'text', text })
        for (const c of m.toolCalls) {
          let input: unknown = {}
          try { input = JSON.parse(c.args) } catch { /* keep empty input */ }
          blocks.push({ type: 'tool_use', id: c.id, name: c.name, input })
        }
        messages.push({ role: 'assistant', content: blocks })
      } else {
        messages.push({ role: m.role, content: anthropicContent(m.content) })
      }
    }

    const body: AnthropicBlock = {
      model: opts.model,
      max_tokens: opts.maxTokens ?? 2048,
      system: opts.system,
      messages,
      stream: true
    }
    if (opts.tools?.length) {
      body.tools = opts.tools.map(t => ({
        name: t.name,
        description: t.description,
        input_schema: t.parameters
      }))
    }

    const res = await fetch(`${BASE_URL}/messages`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify(body),
      signal: opts.signal
    })
    if (!res.ok || !res.body) {
      throw new Error(`${IS_KOREAN_EDITION ? 'Anthropic 요청 실패' : 'Anthropic request failed'} (${res.status}): ${(await res.text()).slice(0, 300)}`)
    }

    const toolAcc = new Map<number, { id: string; name: string; args: string }>()
    const handleLine = (line: string): { type: 'text'; text: string } | null => {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data:')) return null
      let json: any
      try { json = JSON.parse(trimmed.slice(5).trim()) } catch { return null }

      if (json.type === 'content_block_start' && json.content_block?.type === 'tool_use') {
        const index = Number(json.index ?? toolAcc.size)
        toolAcc.set(index, {
          id: String(json.content_block.id ?? `call_${index}`),
          name: String(json.content_block.name ?? ''),
          args: ''
        })
        return null
      }

      if (json.type !== 'content_block_delta') return null
      const delta = json.delta
      if (delta?.type === 'text_delta' && typeof delta.text === 'string' && delta.text.length) {
        return { type: 'text', text: delta.text }
      }
      if (delta?.type === 'input_json_delta' && typeof delta.partial_json === 'string') {
        const index = Number(json.index ?? 0)
        const acc = toolAcc.get(index) ?? { id: `call_${index}`, name: '', args: '' }
        acc.args += delta.partial_json
        toolAcc.set(index, acc)
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

  async test(): Promise<{ ok: boolean; message: string; models?: string[] }> {
    try {
      const res = await fetch(`${BASE_URL}/messages`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify({
          model: 'claude-haiku-4-5',
          max_tokens: 8,
          messages: [{ role: 'user', content: 'ping' }]
        })
      })
      if (!res.ok) return { ok: false, message: `Anthropic API ${IS_KOREAN_EDITION ? '응답 오류' : 'returned'} ${res.status}: ${(await res.text()).slice(0, 200)}` }
      const json: any = await res.json()
      return {
        ok: true,
        message: IS_KOREAN_EDITION ? `연결됨 (${json.model ?? 'Anthropic'}).` : `Connected (${json.model ?? 'Anthropic'}).`,
        models: ANTHROPIC_MODELS
      }
    } catch (err) {
      return { ok: false, message: err instanceof Error ? err.message : String(err) }
    }
  }

  private headers(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'x-api-key': this.apiKey,
      'anthropic-version': API_VERSION
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

function anthropicContent(content: ProviderContent): string | AnthropicBlock[] {
  if (typeof content === 'string') return content
  return content.map(part => {
    if (part.type === 'text') return { type: 'text', text: part.text }
    return {
      type: 'image',
      source: {
        type: 'base64',
        media_type: part.mimeType,
        data: part.data
      }
    }
  })
}

function isTypedBlock(value: unknown, type: string): value is AnthropicBlock {
  return !!value && typeof value === 'object' && (value as AnthropicBlock).type === type
}
