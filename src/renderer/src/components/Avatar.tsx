import type { Persona } from '@common/types'
import { PersonIcon } from './Icons'
import { resolveAvatarSrc } from '../lib/avatarAssets'

export function Avatar({ persona, size = 40 }: { persona: Persona; size?: number }): React.JSX.Element {
  const src = resolveAvatarSrc(persona.avatar)
  const style: React.CSSProperties = {
    width: size,
    height: size,
    color: persona.color
  }
  return (
    <div className="avatar icon-avatar" style={style} aria-label={persona.name} title={persona.name}>
      {src ? (
        <img src={src} alt="" className="avatar-img" />
      ) : (
        <PersonIcon size={Math.max(16, Math.round(size * 0.52))} />
      )}
    </div>
  )
}

export function UserAvatar({ name, size = 40 }: { name: string; size?: number }): React.JSX.Element {
  return (
    <div
      className="avatar icon-avatar"
      style={{ width: size, height: size, color: '#9aa1ab' }}
      aria-label={name || 'You'}
      title={name || 'You'}
    >
      <PersonIcon size={Math.max(16, Math.round(size * 0.52))} />
    </div>
  )
}
