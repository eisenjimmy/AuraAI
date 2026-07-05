import React from 'react'

// Dependency-free mini-markdown for chat messages: fenced code blocks,
// inline code, bold, italic, links. Renders React elements (no innerHTML),
// so model output can never inject markup.

export function Markdown({ text }: { text: string }): React.JSX.Element {
  const blocks: React.ReactNode[] = []
  const parts = text.split(/```/)
  parts.forEach((part, i) => {
    if (i % 2 === 1) {
      // Code fence: first line may be a language tag.
      const nl = part.indexOf('\n')
      const code = nl >= 0 ? part.slice(nl + 1) : part
      blocks.push(
        <pre key={i}>
          <code>{code.replace(/\n$/, '')}</code>
        </pre>
      )
    } else if (part) {
      blocks.push(<span key={i}>{renderInline(part)}</span>)
    }
  })
  return <>{blocks}</>
}

// Order matters: code first, then [text](url) links, bold (non-greedy, may
// contain single *), italic, then bare URLs.
const INLINE_RE = /(`[^`\n]+`)|(\[[^\]\n]+\]\(https?:\/\/[^\s)]+\))|(\*\*[^\n]+?\*\*)|(\*[^*\n]+\*)|(_[^_\n]+_)|(https?:\/\/[^\s<>")\]]+)/g

function renderInline(text: string): React.ReactNode[] {
  const nodes: React.ReactNode[] = []
  let last = 0
  let key = 0
  for (const match of text.matchAll(INLINE_RE)) {
    const idx = match.index ?? 0
    if (idx > last) nodes.push(text.slice(last, idx))
    const token = match[0]
    if (token.startsWith('`')) {
      nodes.push(<code key={key++}>{token.slice(1, -1)}</code>)
    } else if (token.startsWith('[')) {
      const m = token.match(/^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/)
      if (m) {
        nodes.push(
          <a key={key++} href={m[2]} target="_blank" rel="noreferrer">
            {m[1]}
          </a>
        )
      } else {
        nodes.push(token)
      }
    } else if (token.startsWith('**')) {
      nodes.push(<strong key={key++}>{renderPlainEmphasis(token.slice(2, -2), key)}</strong>)
    } else if (token.startsWith('*') || token.startsWith('_')) {
      nodes.push(<em key={key++}>{token.slice(1, -1)}</em>)
    } else {
      nodes.push(
        <a key={key++} href={token} target="_blank" rel="noreferrer">
          {token}
        </a>
      )
    }
    last = idx + token.length
  }
  if (last < text.length) nodes.push(text.slice(last))
  return nodes
}

// Inside bold, render *nested emphasis* instead of leaking asterisks.
function renderPlainEmphasis(text: string, baseKey: number): React.ReactNode {
  const parts = text.split(/\*([^*]+)\*/)
  if (parts.length === 1) return text
  return parts.map((part, i) => (i % 2 === 1 ? <em key={`${baseKey}-${i}`}>{part}</em> : part))
}
