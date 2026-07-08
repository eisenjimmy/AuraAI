import { useEffect, useRef, useState, useCallback } from 'react'
import type { AppSettings, ChatAttachment, ChatMessage, Persona, StreamEvent } from '@common/types'
import { Avatar, UserAvatar } from './Avatar'
import { Markdown } from './Markdown'
import { SpeechQueue } from '../lib/voice'
import { activityIcon, CloseIcon, ImageIcon, SendIcon, SpeakerIcon, StopIcon, WarnIcon } from './Icons'
import { t } from '../lib/i18n'

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
            m.pending && !generating ? { ...m, pending: false, error: m.error ?? t.common.interrupted } : m
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
    (text: string, attachments: ChatAttachment[]) => {
      const trimmed = text.trim()
      if ((!trimmed && attachments.length === 0) || busy) return
      stickToBottom.current = true
      speechRef.current?.stop()
      setBusy(true)
      // Optimistic echo; authoritative copies stream back from main.
      setMessages(prev => [
        ...prev,
        { id: `local-${Date.now()}`, role: 'user', content: trimmed, attachments, ts: Date.now() }
      ])
      void window.aura.sendMessage({ personaId: persona.id, text: trimmed, attachments }).catch(() => setBusy(false))
    },
    [busy, persona.id]
  )

  const stop = useCallback(() => {
    speechRef.current?.stop()
    void window.aura.stopGeneration(persona.id)
  }, [persona.id])

  const clear = useCallback(() => {
    if (!window.confirm(t.chat.clearConfirm(persona.name))) return
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
          <span className="icon-btn" title={t.chat.voiceOn}>
            <SpeakerIcon />
          </span>
        )}
        <button className="icon-btn" onClick={clear} disabled={busy} title={busy ? t.chat.waitToClear : t.chat.clearTitle}>
          {t.chat.clearButton}
        </button>
      </div>

      {messages.length === 0 ? (
        <div className="empty-chat">
          <div className="big-avatar">
            <Avatar persona={persona} size={80} />
          </div>
          <h2>{persona.name}</h2>
          <p>{persona.tagline}</p>
          <p>{t.chat.empty}</p>
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

  const author = message.role === 'user' ? userName || t.common.you : persona.name
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
          {message.attachments && message.attachments.length > 0 && (
            <div className="attachment-grid">
              {message.attachments.map(a => (
                <a key={a.id} href={a.url} target="_blank" rel="noreferrer" className="attachment-thumb" title={a.name}>
                  <img src={a.url} alt={a.name} />
                </a>
              ))}
            </div>
          )}
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
  onSend: (text: string, attachments: ChatAttachment[]) => void
  onStop: () => void
}

function Composer({ personaName, busy, onSend, onStop }: ComposerProps): React.JSX.Element {
  const [text, setText] = useState('')
  const [attachments, setAttachments] = useState<ChatAttachment[]>([])
  const ref = useRef<HTMLTextAreaElement>(null)

  const autosize = useCallback(() => {
    const el = ref.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, window.innerHeight * 0.4)}px`
  }, [])

  useEffect(autosize, [text, autosize])

  const submit = (): void => {
    if ((!text.trim() && attachments.length === 0) || busy) return
    onSend(text, attachments)
    setText('')
    setAttachments([])
  }

  const addImages = async (): Promise<void> => {
    if (busy) return
    const picked = await window.aura.pickChatImages()
    if (picked.length) setAttachments(prev => [...prev, ...picked])
  }

  const removeAttachment = (id: string): void => {
    setAttachments(prev => prev.filter(a => a.id !== id))
  }

  return (
    <div className="composer">
      <div className="composer-box">
        {attachments.length > 0 && (
          <div className="composer-attachments">
            {attachments.map(a => (
              <div key={a.id} className="composer-attachment" title={a.name}>
                <img src={a.url} alt={a.name} />
                <button onClick={() => removeAttachment(a.id)} title={t.chat.removeImage}>
                  <CloseIcon size={11} />
                </button>
              </div>
            ))}
          </div>
        )}
        <textarea
          ref={ref}
          rows={1}
          value={text}
          placeholder={t.chat.messagePlaceholder(personaName)}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              submit()
            }
          }}
        />
        <button className="attach-btn" onClick={() => void addImages()} disabled={busy} title={t.chat.addImages}>
          <ImageIcon />
        </button>
        {busy ? (
          <button className="stop-btn" onClick={onStop} title={t.chat.stop}>
            <StopIcon />
          </button>
        ) : (
          <button className={`send-btn ${text.trim() || attachments.length ? 'ready' : ''}`} onClick={submit} title={t.chat.send}>
            <SendIcon />
          </button>
        )}
      </div>
      <div className="composer-hint">{t.chat.hint}</div>
    </div>
  )
}
