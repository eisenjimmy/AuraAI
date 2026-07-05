import type { Persona } from '@common/types'

// Persona avatar: shows the uploaded image, or a blank colored circle with
// the persona's initial until the user adds one (profile images are left
// intentionally blank in the presets).

export function Avatar({ persona, size = 40 }: { persona: Persona; size?: number }): React.JSX.Element {
  const style: React.CSSProperties = {
    width: size,
    height: size,
    fontSize: size * 0.42
  }
  if (persona.avatar) {
    return (
      <div className="avatar" style={style}>
        <img src={persona.avatar} alt={persona.name} draggable={false} />
      </div>
    )
  }
  return (
    <div className="avatar" style={{ ...style, background: persona.color }}>
      {persona.name.charAt(0).toUpperCase()}
    </div>
  )
}

export function UserAvatar({ name, size = 40 }: { name: string; size?: number }): React.JSX.Element {
  return (
    <div
      className="avatar"
      style={{ width: size, height: size, fontSize: size * 0.42, background: '#6d6f78' }}
    >
      {(name || 'You').charAt(0).toUpperCase()}
    </div>
  )
}
