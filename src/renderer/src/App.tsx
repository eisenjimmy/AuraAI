import { useCallback, useEffect, useState } from 'react'
import type { AppSettings, ChatMessage, Persona, StreamEvent } from '@common/types'
import { Sidebar } from './components/Sidebar'
import { ChatView } from './components/ChatView'
import { Onboarding } from './components/Onboarding'
import { SettingsModal } from './components/Settings'
import { MemoryPanel } from './components/MemoryPanel'
import { t } from './lib/i18n'
import { AURA_EDITION } from '@common/edition'

export default function App(): React.JSX.Element {
  const [settings, setSettings] = useState<AppSettings | null>(null)
  const [personas, setPersonas] = useState<Persona[]>([])
  const [activeId, setActiveId] = useState('')
  const [showSettings, setShowSettings] = useState(false)
  const [memoryPersona, setMemoryPersona] = useState<Persona | null | undefined>(undefined)
  const [typingIds, setTypingIds] = useState<Set<string>>(() => new Set())
  const [lastConversations, setLastConversations] = useState<Record<string, number>>({})
  const [speechLevels, setSpeechLevels] = useState<Record<string, number>>({})

  const refreshPersonas = useCallback(() => {
    void window.aura.getPersonas().then(setPersonas)
  }, [])

  useEffect(() => {
    void Promise.all([window.aura.getSettings(), window.aura.getPersonas()]).then(
      ([s, p]) => {
        setSettings(s)
        setPersonas(p)
        setActiveId(s.activePersonaId || p[0]?.id || '')
      }
    )
  }, [])

  useEffect(() => {
    const ids = personas.map(p => p.id)
    if (ids.length === 0) return
    let cancelled = false
    void Promise.all([
      window.aura.getActiveGenerations(),
      Promise.all(ids.map(async id => [id, latestMessageTime(await window.aura.getChat(id))] as const))
    ]).then(([active, rows]) => {
      if (cancelled) return
      setTypingIds(new Set(active))
      setLastConversations(Object.fromEntries(rows.filter(([, ts]) => ts > 0)))
    })
    return () => {
      cancelled = true
    }
  }, [personas])

  useEffect(() => {
    const off = window.aura.onStream((ev: StreamEvent) => {
      setLastConversations(prev => ({ ...prev, [ev.personaId]: Date.now() }))
      if (ev.type === 'start') {
        setTypingIds(prev => new Set(prev).add(ev.personaId))
      } else if (ev.type === 'done' || ev.type === 'error') {
        setTypingIds(prev => {
          const next = new Set(prev)
          next.delete(ev.personaId)
          return next
        })
      }
    })
    return off
  }, [])

  useEffect(() => {
    document.documentElement.dataset.theme = settings?.theme ?? 'dark'
    document.documentElement.lang = AURA_EDITION === 'ko' ? 'ko' : 'en'
    document.title = t.appName
  }, [settings?.theme])

  const saveSettings = useCallback((next: AppSettings) => {
    setSettings(next)
    void window.aura.saveSettings(next)
  }, [])

  const selectPersona = useCallback(
    (id: string) => {
      setActiveId(id)
      if (settings) saveSettings({ ...settings, activePersonaId: id })
    },
    [settings, saveSettings]
  )

  const setPersonaSpeechLevel = useCallback((personaId: string, level: number) => {
    setSpeechLevels(prev => {
      const current = prev[personaId] ?? 0
      if (Math.abs(current - level) < 0.04) return prev
      return { ...prev, [personaId]: level }
    })
  }, [])

  if (!settings) return <div className="app" />

  if (!settings.onboarded) {
    return (
      <Onboarding
        settings={settings}
        personas={personas}
        onComplete={next => {
          saveSettings(next)
          setActiveId(next.activePersonaId)
          // Make "this seeds their memory" literally true.
          if (next.userBio.trim()) {
            const now = new Date().toISOString()
            void window.aura.saveMemory({
              slug: 'about-' + (next.userName.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'me'),
              title: t.memory.aboutTitle(next.userName.trim()),
              type: 'profile',
              importance: 5,
              body: next.userBio.trim(),
              createdAt: now,
              updatedAt: now,
              source: 'onboarding'
            })
          }
        }}
      />
    )
  }

  const active = personas.find(p => p.id === activeId) ?? personas[0]

  return (
    <div className="app">
      <Sidebar
        personas={personas}
        activeId={active?.id ?? ''}
        onSelect={selectPersona}
        onOpenSettings={() => setShowSettings(true)}
        onOpenMemory={() => setMemoryPersona(null)}
        typingIds={typingIds}
        lastConversations={lastConversations}
        speechLevels={speechLevels}
      />
      {active && (
        <ChatView
          key={active.id}
          persona={active}
          settings={settings}
          speechLevel={speechLevels[active.id] ?? 0}
          onSpeechLevel={setPersonaSpeechLevel}
          onOpenPersonaMemory={() => setMemoryPersona(active)}
        />
      )}
      {showSettings && (
        <SettingsModal
          settings={settings}
          personas={personas}
          onClose={() => setShowSettings(false)}
          onSettingsSaved={saveSettings}
          onPersonasChanged={refreshPersonas}
        />
      )}
      {memoryPersona !== undefined && <MemoryPanel persona={memoryPersona ?? undefined} onClose={() => setMemoryPersona(undefined)} />}
    </div>
  )
}

function latestMessageTime(messages: ChatMessage[]): number {
  return messages.reduce((max, message) => Math.max(max, message.ts), 0)
}
