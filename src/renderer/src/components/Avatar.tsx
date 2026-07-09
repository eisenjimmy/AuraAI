import type { Persona } from '@common/types'
import { PersonIcon } from './Icons'
import { resolveAvatarSrc } from '../lib/avatarAssets'

export function Avatar({ persona, size = 40, activityLevel = 0 }: { persona: Persona; size?: number; activityLevel?: number }): React.JSX.Element {
  const src = resolveAvatarSrc(persona.avatar)
  const level = Math.max(0, Math.min(1, activityLevel))
  const style: React.CSSProperties = {
    width: size,
    height: size,
    color: persona.color,
    '--avatar-level': level.toFixed(3),
    '--avatar-glow': `${5 + level * 18}px`,
    '--avatar-rise': `${level * -0.8}px`
  } as React.CSSProperties
  const className = `avatar icon-avatar ${activityLevel > 0.02 ? 'speaking' : ''}`
  return (
    <div className={className} style={style} aria-label={persona.name} title={persona.name}>
      {src ? (
        <img src={src} alt="" className="avatar-img" />
      ) : (
        <PersonIcon size={Math.max(16, Math.round(size * 0.52))} />
      )}
    </div>
  )
}

export function UserAvatar({ name, size = 40 }: { name: string; size?: number }): React.JSX.Element {
  const style: React.CSSProperties = {
    width: size,
    height: size,
    color: '#9aa1ab',
    '--avatar-level': '0',
    '--avatar-glow': '5px',
    '--avatar-rise': '0px'
  } as React.CSSProperties
  return (
    <div
      className="avatar icon-avatar"
      style={style}
      aria-label={name || 'You'}
      title={name || 'You'}
    >
      <PersonIcon size={Math.max(16, Math.round(size * 0.52))} />
    </div>
  )
}
