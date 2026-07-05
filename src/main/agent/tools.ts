import type { AppSettings, ActivityEvent } from '@common/types'
import type { ChatProvider, ChatStreamOptions, ProviderMessage, ToolDefinition, ToolCall } from '../providers/types'
import { MemoryVault, clampImportance, slugify } from '../memory/vault'
import { webSearch, fetchPageText } from '../search/webSearch'

// Optional "Tools mode" (Settings → Advanced, OFF by default): a small,
// honed agentic loop where the model itself decides when to search the web,
// read a page, or save a memory — instead of the deterministic pipeline.
// Capped at MAX_TURNS tool rounds so it can never spin.

const MAX_TURNS = 4

/** Tools honor the same feature toggles as the deterministic pipeline. */
export function toolDefinitions(settings: AppSettings): ToolDefinition[] {
  const defs: ToolDefinition[] = []
  if (settings.webSearchEnabled) defs.push(...WEB_TOOLS)
  if (settings.memoryEnabled) defs.push(...MEMORY_TOOLS)
  return defs
}

const WEB_TOOLS: ToolDefinition[] = [
    {
      name: 'web_search',
      description: 'Search the public web. Call this when the answer depends on current or factual information you are not sure about (news, prices, weather, releases, sports, anything after your training data).',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'The search query.' }
        },
        required: ['query']
      }
    },
    {
      name: 'read_webpage',
      description: 'Fetch a web page and return its readable text. Use after web_search when a snippet is not enough.',
      parameters: {
        type: 'object',
        properties: {
          url: { type: 'string', description: 'Full http(s) URL to read.' }
        },
        required: ['url']
      }
    }
]

const MEMORY_TOOLS: ToolDefinition[] = [
    {
      name: 'save_memory',
      description: 'Save one durable fact about the user to long-term memory (preferences, people in their life, ongoing projects, important dates). Only for things worth remembering weeks from now.',
      parameters: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Short note title, e.g. "Favorite coffee".' },
          content: { type: 'string', description: 'The fact, written in third person.' },
          type: { type: 'string', description: 'preference | profile | relationship | event | goal | fact' },
          importance: { type: 'integer', description: '1-5, default 3.' }
        },
        required: ['title', 'content']
      }
    },
    {
      name: 'recall_memories',
      description: 'Search your long-term memory about the user for notes relevant to a topic.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Topic to look up.' }
        },
        required: ['query']
      }
    }
]

export interface ToolContext {
  settings: AppSettings
  vault: MemoryVault
  personaId: string
  provider: ChatProvider
  onActivity: (event: ActivityEvent) => void
}

async function executeTool(call: ToolCall, ctx: ToolContext): Promise<string> {
  let args: Record<string, unknown> = {}
  try { args = JSON.parse(call.args) } catch { /* keep {} */ }

  switch (call.name) {
    case 'web_search': {
      const query = String(args.query ?? '')
      ctx.onActivity({ kind: 'search', label: `Searched: ${query}` })
      const results = await webSearch(query, ctx.settings, 5)
      if (results.length === 0) return JSON.stringify({ results: [], note: 'No results found.' })
      return JSON.stringify({ retrievedAt: new Date().toISOString(), results })
    }
    case 'read_webpage': {
      const url = String(args.url ?? '')
      ctx.onActivity({ kind: 'fetch', label: `Read: ${shortUrl(url)}` })
      try {
        return JSON.stringify({ url, text: await fetchPageText(url) })
      } catch (err) {
        return JSON.stringify({ url, error: err instanceof Error ? err.message : 'fetch failed' })
      }
    }
    case 'save_memory': {
      const title = String(args.title ?? '').slice(0, 80)
      const content = String(args.content ?? '')
      if (!title || !content) return JSON.stringify({ saved: false, error: 'title and content required' })
      const now = new Date().toISOString()
      const slug = slugify(title)
      const existing = ctx.vault.get(slug)
      ctx.vault.save({
        slug,
        title,
        type: String(args.type ?? 'fact'),
        importance: clampImportance(Number(args.importance ?? 3)),
        body: content,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        source: ctx.personaId
      })
      ctx.onActivity({ kind: 'memory-save', label: `Remembered: ${title}` })
      return JSON.stringify({ saved: true, slug })
    }
    case 'recall_memories': {
      const query = String(args.query ?? '')
      ctx.onActivity({ kind: 'memory-recall', label: `Recalled memories: ${query}` })
      const notes = await ctx.vault.recall(query, 5, ctx.provider)
      return JSON.stringify({
        memories: notes.map(n => ({ slug: n.slug, title: n.title, type: n.type, content: n.body }))
      })
    }
    default:
      return JSON.stringify({ error: `Unknown tool: ${call.name}` })
  }
}

/**
 * Run the model-driven tool loop. Streams text via onText; executes tool
 * calls between rounds. Returns the final assistant text.
 */
export async function runToolLoop(
  base: Omit<ChatStreamOptions, 'tools'>,
  ctx: ToolContext,
  onText: (text: string) => void
): Promise<string> {
  const tools = toolDefinitions(ctx.settings)
  const messages: ProviderMessage[] = [...base.messages]
  let finalText = ''

  if (tools.length === 0) {
    // All tool-backed features are toggled off: plain streaming chat.
    for await (const ev of ctx.provider.streamChat({ ...base, messages })) {
      if (ev.type === 'text') {
        finalText += ev.text
        onText(ev.text)
      }
    }
    return finalText
  }

  for (let turn = 0; turn <= MAX_TURNS; turn++) {
    let roundText = ''
    let calls: ToolCall[] = []
    const lastRound = turn === MAX_TURNS

    // Tools stay declared on every round (providers reject histories that
    // contain tool_use blocks without a tools param); on the last round any
    // further calls are simply not executed.
    for await (const ev of ctx.provider.streamChat({ ...base, messages, tools })) {
      if (ev.type === 'text') {
        roundText += ev.text
        onText(ev.text)
      } else if (ev.type === 'toolCalls') {
        calls = ev.calls
      }
    }
    finalText += roundText

    if (calls.length === 0 || lastRound) break

    messages.push({ role: 'assistant', content: roundText, toolCalls: calls })
    for (const call of calls) {
      const result = await executeTool(call, ctx)
      messages.push({ role: 'tool', content: result, toolCallId: call.id, name: call.name })
    }
    if (roundText) {
      finalText += '\n\n'
      onText('\n\n')
    }
  }

  return finalText
}

function shortUrl(url: string): string {
  try { return new URL(url).hostname } catch { return url.slice(0, 40) }
}
