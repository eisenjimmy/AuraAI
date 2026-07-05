import type { AppSettings } from '@common/types'

// Web search with a provider ladder (ported from the original Jarvis design):
// keyed APIs first (Brave / Tavily) when the user added a key, then a
// credential-free DuckDuckGo HTML fallback so search works out of the box.

export interface SearchResult {
  title: string
  url: string
  snippet: string
}

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

export async function webSearch(query: string, settings: AppSettings, max = 5): Promise<SearchResult[]> {
  const provider = settings.searchProvider
  const key = settings.searchApiKey?.trim()

  const attempts: Array<() => Promise<SearchResult[]>> = []
  if (key && (provider === 'brave' || provider === 'auto')) attempts.push(() => brave(query, key, max))
  if (key && (provider === 'tavily' || provider === 'auto')) attempts.push(() => tavily(query, key, max))
  if (provider === 'duckduckgo' || provider === 'auto' || !key) attempts.push(() => duckduckgo(query, max))

  for (const attempt of attempts) {
    try {
      const results = await attempt()
      if (results.length > 0) return results.slice(0, max)
    } catch { /* fall through to the next provider */ }
  }
  return []
}

async function brave(query: string, key: string, max: number): Promise<SearchResult[]> {
  const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=${max}`
  const res = await fetch(url, {
    headers: { Accept: 'application/json', 'X-Subscription-Token': key },
    signal: AbortSignal.timeout(8000)
  })
  if (!res.ok) throw new Error(`brave ${res.status}`)
  const json: any = await res.json()
  return (json.web?.results ?? []).map((r: any) => ({
    title: stripTags(String(r.title ?? '')),
    url: String(r.url ?? ''),
    snippet: stripTags(String(r.description ?? ''))
  }))
}

async function tavily(query: string, key: string, max: number): Promise<SearchResult[]> {
  const res = await fetch('https://api.tavily.com/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify({ query, max_results: max }),
    signal: AbortSignal.timeout(8000)
  })
  if (!res.ok) throw new Error(`tavily ${res.status}`)
  const json: any = await res.json()
  return (json.results ?? []).map((r: any) => ({
    title: String(r.title ?? ''),
    url: String(r.url ?? ''),
    snippet: String(r.content ?? '').slice(0, 300)
  }))
}

async function duckduckgo(query: string, max: number): Promise<SearchResult[]> {
  const res = await fetch(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
    signal: AbortSignal.timeout(8000)
  })
  if (!res.ok) throw new Error(`duckduckgo ${res.status}`)
  const html = await res.text()

  const results: SearchResult[] = []
  const linkRe = /<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g
  const snippetRe = /<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>|<td[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/td>/g

  const snippets: string[] = []
  let sm: RegExpExecArray | null
  while ((sm = snippetRe.exec(html)) !== null) snippets.push(stripTags(sm[1] ?? sm[2] ?? ''))

  // Snippets are positional per anchor, so track the anchor index separately —
  // skipped anchors (ads) must still consume their snippet slot.
  let anchorIndex = -1
  let m: RegExpExecArray | null
  while ((m = linkRe.exec(html)) !== null && results.length < max) {
    anchorIndex++
    const url = decodeDuckUrl(m[1])
    if (!url.startsWith('http')) continue
    if (/duckduckgo\.com\/y\.js|ad_provider=|ad_domain=/.test(m[1] + url)) continue
    results.push({
      title: stripTags(m[2]),
      url,
      snippet: snippets[anchorIndex] ?? ''
    })
  }
  return results
}

function decodeDuckUrl(href: string): string {
  // DuckDuckGo wraps results as //duckduckgo.com/l/?uddg=<encoded>&rut=...
  const match = href.match(/[?&]uddg=([^&]+)/)
  if (match) {
    try { return decodeURIComponent(match[1]) } catch { /* fall through */ }
  }
  return href.startsWith('//') ? `https:${href}` : href
}

function stripTags(html: string): string {
  return html
    .replace(/<[^>]*>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * Refuse URLs that point at private or local network space. The model can be
 * steered by web content (prompt injection), so read_webpage must never reach
 * internal services (routers, cloud metadata, localhost admin panels).
 */
export function assertPublicHttpUrl(raw: string): URL {
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    throw new Error('Invalid URL')
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('Only http(s) URLs can be fetched')
  }
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '')
  const blockedHost =
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.internal') ||
    host === '::1' ||
    host.startsWith('fe80:') ||
    host.startsWith('fc') ||
    host.startsWith('fd')
  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  const blockedIp =
    ipv4 !== null &&
    (ipv4[1] === '0' ||
      ipv4[1] === '10' ||
      ipv4[1] === '127' ||
      (ipv4[1] === '169' && ipv4[2] === '254') ||
      (ipv4[1] === '172' && Number(ipv4[2]) >= 16 && Number(ipv4[2]) <= 31) ||
      (ipv4[1] === '192' && ipv4[2] === '168'))
  if (blockedHost || blockedIp) {
    throw new Error('Refusing to fetch private/local network addresses')
  }
  return url
}

/** Fetch a page and return readable text (rough but dependency-free). */
export async function fetchPageText(url: string, maxChars = 4000): Promise<string> {
  assertPublicHttpUrl(url)
  const res = await fetch(url, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
    signal: AbortSignal.timeout(10000),
    redirect: 'follow'
  })
  if (!res.ok) throw new Error(`fetch ${res.status}`)
  if (res.url && res.url !== url) assertPublicHttpUrl(res.url) // redirect target too
  // Read at most ~600KB — plenty for article text, bounded for everything else.
  let html = ''
  const reader = res.body?.getReader()
  if (reader) {
    const decoder = new TextDecoder()
    while (html.length < 600_000) {
      const { done, value } = await reader.read()
      if (done) break
      html += decoder.decode(value, { stream: true })
    }
    void reader.cancel().catch(() => undefined)
  }
  const body = html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<nav[\s\S]*?<\/nav>/gi, ' ')
    .replace(/<footer[\s\S]*?<\/footer>/gi, ' ')
  return stripTags(body).slice(0, maxChars)
}

// Heuristic: does this message need fresh information from the web?
// Deterministic (no extra LLM round-trip), mirroring the original app's
// deterministic intent routing.
const SEARCH_TRIGGERS = /\b(today|tonight|tomorrow|yesterday|this (week|month|year|weekend)|latest|current(ly)?|right now|recent(ly)?|news|headline|score|weather|forecast|stock|price of|how much (is|does|are)|release(d| date)?|20(2[4-9]|3\d)|who won|what happened|is .{1,40} (open|out|live|dead|alive)|search (for|up)|look (it |this )?up|google)\b/i

export function shouldSearch(message: string): boolean {
  if (message.length < 8) return false
  return SEARCH_TRIGGERS.test(message)
}
