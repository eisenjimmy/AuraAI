import type { Persona } from '@common/types'
import { Avatar } from './Avatar'
import { GearIcon, VaultIcon } from './Icons'

interface SidebarProps {
  personas: Persona[]
  activeId: string
  onSelect: (id: string) => void
  onOpenSettings: () => void
  onOpenMemory: () => void
}

export function Sidebar({ personas, activeId, onSelect, onOpenSettings, onOpenMemory }: SidebarProps): React.JSX.Element {
  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <div className="logo">A</div>
        Aura AI
      </div>
      <div className="sidebar-section">Friends</div>
      <div className="persona-list">
        {personas.map(p => (
          <button
            key={p.id}
            className={`persona-item ${p.id === activeId ? 'active' : ''}`}
            onClick={() => onSelect(p.id)}
          >
            <Avatar persona={p} size={34} />
            <div className="meta">
              <div className="name">{p.name}</div>
              <div className="tagline">{p.tagline}</div>
            </div>
          </button>
        ))}
      </div>
      <div className="sidebar-footer">
        <button onClick={onOpenMemory} title="Memory vault">
          <VaultIcon /> Memory
        </button>
        <button onClick={onOpenSettings} title="Settings">
          <GearIcon /> Settings
        </button>
      </div>
    </div>
  )
}
