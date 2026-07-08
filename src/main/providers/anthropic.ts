import Anthropic from '@anthropic-ai/sdk'
import type { ChatProvider, ChatStreamOptions, ProviderContent, ProviderEvent, ToolCall } from './types'

// Anthropic provider using the official SDK with streaming.
// Note: newer Claude models reject sampling params (temperature/top_p),
// so we simply never send them.

export const ANTHROPIC_MODELS = [
  'claude-opus-4-8',
  'claude-sonnet-5',
  'claude-haiku-4-5'
]

export class AnthropicProvider implements ChatProvider {
  private client: Anthropic

  constructor(apiKey: string) {
    this.client = new Anthropic({ apiKey })
  }

  async *streamChat(opts: ChatStreamOptions): AsyncGenerator<ProviderEvent> {
    type Param = Anthropic.MessageParam
    const messages: Param[] = []
    for (const m of opts.messages) {
      if (m.role === 'tool') {
        // Parallel tool results must land in ONE user message.
        const block: Anthropic.ToolResultBlockParam = {
          type: 'tool_result',
          tool_use_id: m.toolCallId ?? '',
          content: textContent(m.content)
        }
        const last = messages[messages.length - 1]
        if (last?.role === 'user' && Array.isArray(last.content) && last.content.every(b => b.type === 'tool_result')) {
          ;(last.content as Anthropic.ToolResultBlockParam[]).push(block)
        } else {
          messages.push({ role: 'user', content: [block] })
        }
      } else if (m.role === 'assistant' && m.toolCalls?.length) {
        const blocks: Anthropic.ContentBlockParam[] = []
        const text = textContent(m.content)
        if (text) blocks.push({ type: 'text', text })
        for (const c of m.toolCalls) {
          let input: unknown = {}
          try { input = JSON.parse(c.args) } catch { /* keep {} */ }
          blocks.push({ type: 'tool_use', id: c.id, name: c.name, input })
        }
        messages.push({ role: 'assistant', content: blocks })
      } else {
        messages.push({ role: m.role, content: anthropicContent(m.content) })
      }
    }

    const stream = this.client.messages.stream(
      {
        model: opts.model,
        max_tokens: opts.maxTokens ?? 2048,
        system: opts.system,
        messages,
        ...(opts.tools?.length
          ? {
              tools: opts.tools.map(t => ({
                name: t.name,
                description: t.description,
                input_schema: t.parameters as Anthropic.Tool.InputSchema
              }))
            }
          : {})
      },
      { signal: opts.signal }
    )

    for await (const event of stream) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        yield { type: 'text', text: event.delta.text }
      }
    }

    const final = await stream.finalMessage()
    const toolUses = final.content.filter(
      (b): b is Anthropic.ToolUseBlock => b.type === 'tool_use'
    )
    if (toolUses.length > 0) {
      const calls: ToolCall[] = toolUses.map(t => ({
        id: t.id,
        name: t.name,
        args: JSON.stringify(t.input ?? {})
      }))
      yield { type: 'toolCalls', calls }
    }
    yield { type: 'done' }
  }

  async test(): Promise<{ ok: boolean; message: string; models?: string[] }> {
    try {
      const res = await this.client.messages.create({
        model: 'claude-haiku-4-5',
        max_tokens: 8,
        messages: [{ role: 'user', content: 'ping' }]
      })
      return {
        ok: true,
        message: `Connected (${res.model}).`,
        models: ANTHROPIC_MODELS
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

function anthropicContent(content: ProviderContent): string | Anthropic.ContentBlockParam[] {
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
    } as Anthropic.ContentBlockParam
  })
}
