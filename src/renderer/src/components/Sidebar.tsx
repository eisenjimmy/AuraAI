import { useEffect, useState } from 'react'
import type { Persona } from '@common/types'
import { Avatar } from './Avatar'
import { GearIcon, VaultIcon } from './Icons'
import { t } from '../lib/i18n'

interface SidebarProps {
  personas: Persona[]
  activeId: string
  onSelect: (id: string) => void
  onOpenSettings: () => void
  onOpenMemory: () => void
  onOpenPersonaMemory: (persona: Persona) => void
  typingIds: Set<string>
  lastConversations: Record<string, number>
  speechLevels: Record<string, number>
}

export function Sidebar({
  personas,
  activeId,
  onSelect,
  onOpenSettings,
  onOpenMemory,
  onOpenPersonaMemory,
  typingIds,
  lastConversations,
  speechLevels
}: SidebarProps): React.JSX.Element {
  const [, setClock] = useState(0)

  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 60_000)
    return () => window.clearInterval(timer)
  }, [])

  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <div className="logo">A</div>
        {t.appName}
      </div>
      <div className="sidebar-section">{t.sidebar.friends}</div>
      <div className="persona-list">
        {personas.map(p => (
          <button
            key={p.id}
            className={`persona-item ${p.id === activeId ? 'active' : ''}`}
            onClick={() => onSelect(p.id)}
            onContextMenu={e => {
              e.preventDefault()
              onOpenPersonaMemory(p)
            }}
          >
            <Avatar persona={p} size={34} activityLevel={speechLevels[p.id] ?? 0} />
            <div className="meta">
              <div className="name">{p.name}</div>
              <div className="tagline">{typingIds.has(p.id) ? t.sidebar.typing : relativeTime(lastConversations[p.id]) || p.tagline}</div>
            </div>
          </button>
        ))}
      </div>
      <div className="sidebar-footer">
        <button onClick={onOpenMemory} title={t.sidebar.memoryTitle}>
          <VaultIcon /> {t.sidebar.globalMemory}
        </button>
        <button onClick={onOpenSettings} title={t.sidebar.settings}>
          <GearIcon /> {t.sidebar.settings}
        </button>
      </div>
    </div>
  )
}

function relativeTime(ts?: number): string {
  if (!ts) return ''
  const diff = Math.max(0, Date.now() - ts)
  const min = Math.floor(diff / 60_000)
  if (min < 1) return t.sidebar.justNow
  if (min < 60) return t.sidebar.minutesAgo(min)
  const hours = Math.floor(min / 60)
  if (hours < 24) return t.sidebar.hoursAgo(hours)
  const days = Math.floor(hours / 24)
  if (days < 7) return t.sidebar.daysAgo(days)
  return new Date(ts).toLocaleDateString()
}
