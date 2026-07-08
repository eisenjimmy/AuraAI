// Provider-agnostic chat contract. Every provider (local OpenAI-compatible,
// Anthropic, OpenAI, Gemini) implements streamChat and yields the same events.

export interface ProviderMessage {
  role: 'user' | 'assistant' | 'tool'
  content: ProviderContent
  /** Set on assistant messages that requested tool calls. */
  toolCalls?: ToolCall[]
  /** Set on tool messages: which call this result answers. */
  toolCallId?: string
  /** Tool name (needed by Gemini function responses). */
  name?: string
}

export type ProviderContent = string | ProviderContentPart[]

export type ProviderContentPart =
  | { type: 'text'; text: string }
  | { type: 'image'; mimeType: string; data: string; name?: string }

export interface ToolCall {
  id: string
  name: string
  /** JSON-encoded arguments. */
  args: string
}

export interface ToolDefinition {
  name: string
  description: string
  /** JSON Schema for the input object. */
  parameters: Record<string, unknown>
}

export interface ChatStreamOptions {
  model: string
  system: string
  messages: ProviderMessage[]
  tools?: ToolDefinition[]
  maxTokens?: number
  signal?: AbortSignal
}

export type ProviderEvent =
  | { type: 'text'; text: string }
  | { type: 'toolCalls'; calls: ToolCall[] }
  | { type: 'done' }

export interface ChatProvider {
  streamChat(opts: ChatStreamOptions): AsyncGenerator<ProviderEvent>
  /** Optional: embed text for memory recall. Return null when unsupported. */
  embed?(text: string): Promise<number[] | null>
  /** Identity of the embedding space (provider:model). Vectors from different
      spaces are not comparable, so caches key on this. */
  embeddingId?: string
  /** Quick connectivity check; returns available models when possible. */
  test(): Promise<{ ok: boolean; message: string; models?: string[] }>
}
