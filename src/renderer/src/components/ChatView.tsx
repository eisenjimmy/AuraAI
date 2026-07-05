import { useEffect, useRef, useState, useCallback } from 'react'
import type { AppSettings, ChatMessage, Persona, StreamEvent } from '@common/types'
import { Avatar, UserAvatar } from './Avatar'
import { Markdown } from './Markdown'
import { SpeechQueue } from '../lib/voice'
import { activityIcon, SendIcon, SpeakerIcon, StopIcon, WarnIcon } from './Icons'

interface ChatViewProps {
  persona: Persona
  settings: AppSettings
}

const GROUP_WINDOW_MS = 7 * 60 * 1000

export function ChatView({ persona, settings }: ChatViewProps): React.JSX.Element {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [busy, setBusy] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  const speechRef = useRef<SpeechQueue | null>(null)
  const stickToBottom = useRef(true)

  if (!speechRef.current) speechRef.current = new SpeechQueue()
  speechRef.current.setVoice(persona.voice)

  // Load history on mount (the component remounts per persona via key).
  // A pending message is only "interrupted" if no generation is actually
  // running for this persona — main is the authority.
  useEffect(() => {
    let cancelled = false
    void Promise.all([window.aura.getChat(persona.id), window.aura.getActiveGenerations()]).then(
      ([msgs, active]) => {
        if (cancelled) return
        const generating = active.includes(persona.id)
        setBusy(generating)
        setMessages(
          msgs.map(m =>
            m.pending && !generating ? { ...m, pending: false, error: m.error ?? 'Interrupted' } : m
          )
        )
      }
    )
    return () => {
      cancelled = true
      speechRef.current?.stop()
    }
  }, [persona.id])

  // Turning voice off silences anything already queued.
  useEffect(() => {
    if (!settings.voiceEnabled) speechRef.current?.stop()
  }, [settings.voiceEnabled])

  // Stream events from the main process (scoped to this persona's chat).
  useEffect(() => {
    const off = window.aura.onStream((ev: StreamEvent) => {
      if (ev.personaId !== persona.id) return
      setMessages(prev => applyStreamEvent(prev, ev))
      if (ev.type === 'start') setBusy(true)
      if (ev.type === 'delta' && settings.voiceEnabled) speechRef.current?.push(ev.text)
      if (ev.type === 'done' || ev.type === 'error') {
        setBusy(false)
        if (settings.voiceEnabled) speechRef.current?.flush()
      }
    })
    return off
  }, [persona.id, settings.voiceEnabled])

  // Auto-scroll while following the bottom.
  useEffect(() => {
    const el = scrollRef.current
    if (el && stickToBottom.current) el.scrollTop = el.scrollHeight
  }, [messages])

  const onScroll = useCallback(() => {
    const el = scrollRef.current
    if (!el) return
    stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  }, [])

  const send = useCallback(
    (text: string) => {
      const trimmed = text.trim()
      if (!trimmed || busy) return
      stickToBottom.current = true
      speechRef.current?.stop()
      setBusy(true)
      // Optimistic echo; authoritative copies stream back from main.
      setMessages(prev => [
        ...prev,
        { id: `local-${Date.now()}`, role: 'user', content: trimmed, ts: Date.now() }
      ])
      void window.aura.sendMessage({ personaId: persona.id, text: trimmed }).catch(() => setBusy(false))
    },
    [busy, persona.id]
  )

  const stop = useCallback(() => {
    speechRef.current?.stop()
    void window.aura.stopGeneration(persona.id)
  }, [persona.id])

  const clear = useCallback(() => {
    if (!window.confirm(`Clear your conversation with ${persona.name}? Memories are kept.`)) return
    void window.aura.clearChat(persona.id).then(() => setMessages([]))
  }, [persona.id, persona.name])

  return (
    <div className="chat">
      <div className="chat-header">
        <Avatar persona={persona} size={28} />
        <div>
          <div className="title">{persona.name}</div>
          <div className="subtitle">{persona.tagline}</div>
        </div>
        <div className="spacer" />
        {settings.voiceEnabled && (
          <span className="icon-btn" title="Voice replies are on">
            <SpeakerIcon />
          </span>
        )}
        <button className="icon-btn" onClick={clear} disabled={busy} title={busy ? 'Wait for the reply to finish' : 'Clear conversation'}>
          Clear chat
        </button>
      </div>

      {messages.length === 0 ? (
        <div className="empty-chat">
          <div className="big-avatar">
            <Avatar persona={persona} size={80} />
          </div>
          <h2>{persona.name}</h2>
          <p>{persona.tagline}</p>
          <p>This is the very beginning of your conversation. Say hi!</p>
        </div>
      ) : (
        <div className="messages" ref={scrollRef} onScroll={onScroll}>
          {messages.map((m, i) => (
            <MessageRow
              key={m.id}
              message={m}
              prev={messages[i - 1]}
              persona={persona}
              userName={settings.userName}
            />
          ))}
        </div>
      )}

      <Composer personaName={persona.name} busy={busy} onSend={send} onStop={stop} />
    </div>
  )
}

function applyStreamEvent(prev: ChatMessage[], ev: StreamEvent): ChatMessage[] {
  switch (ev.type) {
    case 'start': {
      // Replace the optimistic local echo with nothing (the real user message
      // is already persisted); append the pending assistant message.
      return [
        ...prev,
        { id: ev.messageId, role: 'assistant', content: '', ts: Date.now(), pending: true, activity: [] }
      ]
    }
    case 'delta':
      return prev.map(m => (m.id === ev.messageId ? { ...m, content: m.content + ev.text } : m))
    case 'activity':
      return prev.map(m =>
        m.id === ev.messageId ? { ...m, activity: [...(m.activity ?? []), ev.event] } : m
      )
    case 'done':
      // ev.content is authoritative — heals deltas missed during a reload.
      return prev.map(m => (m.id === ev.messageId ? { ...m, pending: false, content: ev.content } : m))
    case 'error':
      return prev.map(m =>
        m.id === ev.messageId ? { ...m, pending: false, error: ev.message, content: ev.content } : m
      )
  }
}

interface MessageRowProps {
  message: ChatMessage
  prev?: ChatMessage
  persona: Persona
  userName: string
}

function MessageRow({ message, prev, persona, userName }: MessageRowProps): React.JSX.Element {
  const compact =
    prev !== undefined &&
    prev.role === message.role &&
    !prev.error &&
    message.ts - prev.ts < GROUP_WINDOW_MS

  const author = message.role === 'user' ? userName || 'You' : persona.name
  const time = new Date(message.ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })

  return (
    <div className={`msg-group ${compact ? 'compact' : ''}`}>
      <div className="msg-gutter">
        {!compact &&
          (message.role === 'user' ? (
            <UserAvatar name={userName} />
          ) : (
            <Avatar persona={persona} />
          ))}
      </div>
      <div className="msg-body">
        {!compact && (
          <div className="msg-header">
            <span className="msg-author" style={message.role === 'assistant' ? { color: persona.color } : undefined}>
              {author}
            </span>
            <span className="msg-time">{time}</span>
          </div>
        )}
        {message.activity && message.activity.length > 0 && (
          <div className="activity-row">
            {message.activity.map((a, i) => (
              <span key={i} className="activity-chip" title={a.detail}>
                {activityIcon(a.kind)} {a.label}
              </span>
            ))}
          </div>
        )}
        <div className="msg-content">
          {message.content ? (
            <>
              <Markdown text={message.content} />
              {message.pending && <span className="cursor" />}
            </>
          ) : message.pending ? (
            <span className="typing">
              <span /><span /><span />
            </span>
          ) : null}
        </div>
        {message.error && (
          <div className="msg-error">
            <WarnIcon /> {message.error}
          </div>
        )}
      </div>
    </div>
  )
}

interface ComposerProps {
  personaName: string
  busy: boolean
  onSend: (text: string) => void
  onStop: () => void
}

function Composer({ personaName, busy, onSend, onStop }: ComposerProps): React.JSX.Element {
  const [text, setText] = useState('')
  const ref = useRef<HTMLTextAreaElement>(null)

  const autosize = useCallback(() => {
    const el = ref.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, window.innerHeight * 0.4)}px`
  }, [])

  useEffect(autosize, [text, autosize])

  const submit = (): void => {
    if (!text.trim() || busy) return
    onSend(text)
    setText('')
  }

  return (
    <div className="composer">
      <div className="composer-box">
        <textarea
          ref={ref}
          rows={1}
          value={text}
          placeholder={`Message ${personaName}`}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              submit()
            }
          }}
        />
        {busy ? (
          <button className="stop-btn" onClick={onStop} title="Stop generating">
            <StopIcon />
          </button>
        ) : (
          <button className={`send-btn ${text.trim() ? 'ready' : ''}`} onClick={submit} title="Send">
            <SendIcon />
          </button>
        )}
      </div>
      <div className="composer-hint">Enter to send · Shift+Enter for a new line</div>
    </div>
  )
}
