import { useEffect, useState } from 'react'
import type { MemoryNote, Persona } from '@common/types'
import { CloseIcon } from './Icons'
import { t } from '../lib/i18n'

// Browser for the markdown memory vault: view, search, delete, and a
// button that opens the folder itself (it's just Obsidian-style markdown).

export function MemoryPanel({ persona, onClose }: { persona?: Persona; onClose: () => void }): React.JSX.Element {
  const [notes, setNotes] = useState<MemoryNote[]>([])
  const [filter, setFilter] = useState('')

  const refresh = (): void => {
    void window.aura.listMemories(persona?.id).then(setNotes)
  }

  useEffect(refresh, [persona?.id])

  const remove = async (slug: string): Promise<void> => {
    await window.aura.deleteMemory(slug, persona?.id)
    refresh()
  }

  const visible = notes.filter(n => {
    const q = filter.toLowerCase()
    return !q || n.title.toLowerCase().includes(q) || n.body.toLowerCase().includes(q) || n.type.includes(q)
  })

  return (
    <div className="modal-overlay" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-header">
          <h2>{persona ? t.memory.personaTitle(persona.name) : t.memory.globalTitle}</h2>
          <button className="icon-btn" onClick={onClose}><CloseIcon /></button>
        </div>
        <div className="modal-body">
          <div className="row" style={{ marginBottom: 14 }}>
            <input
              placeholder={t.memory.search}
              value={filter}
              onChange={e => setFilter(e.target.value)}
            />
            <button className="btn" style={{ flex: '0 0 auto' }} onClick={() => void window.aura.openMemoryVault(persona?.id)}>
              {t.memory.openFolder}
            </button>
          </div>
          <p className="hint" style={{ fontSize: 12.5, color: 'var(--text-faint)', marginBottom: 12 }}>
            {persona ? t.memory.personaHint(persona.name) : t.memory.globalHint}
          </p>
          {visible.length === 0 && (
            <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>
              {notes.length === 0
                ? t.memory.empty
                : t.memory.noMatch}
            </p>
          )}
          {visible.map(n => (
            <div key={n.slug} className="memory-item">
              <div className="m-head">
                <span className="m-title">{n.title}</span>
                <span className="m-type">{n.type}</span>
                <button className="m-del" onClick={() => void remove(n.slug)}>{t.common.delete}</button>
              </div>
              <div className="m-body">{n.body}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
