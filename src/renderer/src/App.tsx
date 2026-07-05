import { useCallback, useEffect, useState } from 'react'
import type { AppSettings, Persona } from '@common/types'
import { Sidebar } from './components/Sidebar'
import { ChatView } from './components/ChatView'
import { Onboarding } from './components/Onboarding'
import { SettingsModal } from './components/Settings'
import { MemoryPanel } from './components/MemoryPanel'

export default function App(): React.JSX.Element {
  const [settings, setSettings] = useState<AppSettings | null>(null)
  const [personas, setPersonas] = useState<Persona[]>([])
  const [activeId, setActiveId] = useState('')
  const [showSettings, setShowSettings] = useState(false)
  const [showMemory, setShowMemory] = useState(false)

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
    document.documentElement.dataset.theme = settings?.theme ?? 'dark'
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
              title: `About ${next.userName.trim() || 'them'}`,
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
        onOpenMemory={() => setShowMemory(true)}
      />
      {active && <ChatView key={active.id} persona={active} settings={settings} />}
      {showSettings && (
        <SettingsModal
          settings={settings}
          personas={personas}
          onClose={() => setShowSettings(false)}
          onSettingsSaved={saveSettings}
          onPersonasChanged={refreshPersonas}
        />
      )}
      {showMemory && <MemoryPanel onClose={() => setShowMemory(false)} />}
    </div>
  )
}
