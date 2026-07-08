import { IS_KOREAN_EDITION } from '@common/edition'
import { t } from './i18n'

const avatarUrls = {
  'nova': new URL('../assets/avatars/nova.png', import.meta.url).href,
  'sage': new URL('../assets/avatars/sage.png', import.meta.url).href,
  'rio': new URL('../assets/avatars/rio.png', import.meta.url).href,
  'luna': new URL('../assets/avatars/luna.png', import.meta.url).href,
  'max': new URL('../assets/avatars/max.png', import.meta.url).href,
  'gilleon': new URL('../assets/avatars/gilleon.png', import.meta.url).href,
  'neir': new URL('../assets/avatars/neir.png', import.meta.url).href,
  'nova-ko': new URL('../assets/avatars/nova-ko.png', import.meta.url).href,
  'sage-ko': new URL('../assets/avatars/sage-ko.png', import.meta.url).href,
  'rio-ko': new URL('../assets/avatars/rio-ko.png', import.meta.url).href,
  'luna-ko': new URL('../assets/avatars/luna-ko.png', import.meta.url).href,
  'max-ko': new URL('../assets/avatars/max-ko.png', import.meta.url).href,
  'gilleon-ko': new URL('../assets/avatars/gilleon-ko.png', import.meta.url).href,
  'neir-ko': new URL('../assets/avatars/neir-ko.png', import.meta.url).href,
  'korean-man': new URL('../assets/avatars/korean-man.png', import.meta.url).href,
  'korean-woman': new URL('../assets/avatars/korean-woman.png', import.meta.url).href,
  'european-man': new URL('../assets/avatars/european-man.png', import.meta.url).href,
  'european-woman': new URL('../assets/avatars/european-woman.png', import.meta.url).href,
  'south-asian-man': new URL('../assets/avatars/south-asian-man.png', import.meta.url).href,
  'latina-woman': new URL('../assets/avatars/latina-woman.png', import.meta.url).href,
  'middle-eastern-man': new URL('../assets/avatars/middle-eastern-man.png', import.meta.url).href,
  'black-woman': new URL('../assets/avatars/black-woman.png', import.meta.url).href,
  'silver-european-man': new URL('../assets/avatars/silver-european-man.png', import.meta.url).href,
  'mixed-race-woman': new URL('../assets/avatars/mixed-race-woman.png', import.meta.url).href
}

export interface AvatarChoice {
  id: string
  label: string
  src: string
  builtInDefault?: boolean
}

const englishDefaults: AvatarChoice[] = [
  { id: 'default:nova', label: t.avatars.choices['default:nova'], src: avatarUrls.nova, builtInDefault: true },
  { id: 'default:sage', label: t.avatars.choices['default:sage'], src: avatarUrls.sage, builtInDefault: true },
  { id: 'default:rio', label: t.avatars.choices['default:rio'], src: avatarUrls.rio, builtInDefault: true },
  { id: 'default:luna', label: t.avatars.choices['default:luna'], src: avatarUrls.luna, builtInDefault: true },
  { id: 'default:max', label: t.avatars.choices['default:max'], src: avatarUrls.max, builtInDefault: true },
  { id: 'default:gilleon', label: t.avatars.choices['default:gilleon'], src: avatarUrls.gilleon, builtInDefault: true },
  { id: 'default:neir', label: t.avatars.choices['default:neir'], src: avatarUrls.neir, builtInDefault: true }
]

const koreanDefaults: AvatarChoice[] = [
  { id: 'default:nova-ko', label: t.avatars.choices['default:nova'], src: avatarUrls['nova-ko'], builtInDefault: true },
  { id: 'default:sage-ko', label: t.avatars.choices['default:sage'], src: avatarUrls['sage-ko'], builtInDefault: true },
  { id: 'default:rio-ko', label: t.avatars.choices['default:rio'], src: avatarUrls['rio-ko'], builtInDefault: true },
  { id: 'default:luna-ko', label: t.avatars.choices['default:luna'], src: avatarUrls['luna-ko'], builtInDefault: true },
  { id: 'default:max-ko', label: t.avatars.choices['default:max'], src: avatarUrls['max-ko'], builtInDefault: true },
  { id: 'default:gilleon-ko', label: t.avatars.choices['default:gilleon'], src: avatarUrls['gilleon-ko'], builtInDefault: true },
  { id: 'default:neir-ko', label: t.avatars.choices['default:neir'], src: avatarUrls['neir-ko'], builtInDefault: true }
]

const extraChoices: AvatarChoice[] = [
  { id: 'choice:korean-man', label: t.avatars.choices['choice:korean-man'], src: avatarUrls['korean-man'] },
  { id: 'choice:korean-woman', label: t.avatars.choices['choice:korean-woman'], src: avatarUrls['korean-woman'] },
  { id: 'choice:european-man', label: t.avatars.choices['choice:european-man'], src: avatarUrls['european-man'] },
  { id: 'choice:european-woman', label: t.avatars.choices['choice:european-woman'], src: avatarUrls['european-woman'] },
  { id: 'choice:south-asian-man', label: t.avatars.choices['choice:south-asian-man'], src: avatarUrls['south-asian-man'] },
  { id: 'choice:latina-woman', label: t.avatars.choices['choice:latina-woman'], src: avatarUrls['latina-woman'] },
  { id: 'choice:middle-eastern-man', label: t.avatars.choices['choice:middle-eastern-man'], src: avatarUrls['middle-eastern-man'] },
  { id: 'choice:black-woman', label: t.avatars.choices['choice:black-woman'], src: avatarUrls['black-woman'] },
  { id: 'choice:silver-european-man', label: t.avatars.choices['choice:silver-european-man'], src: avatarUrls['silver-european-man'] },
  { id: 'choice:mixed-race-woman', label: t.avatars.choices['choice:mixed-race-woman'], src: avatarUrls['mixed-race-woman'] }
]

export const DEFAULT_AVATAR_CHOICES: AvatarChoice[] = [
  ...(IS_KOREAN_EDITION ? koreanDefaults : englishDefaults),
  ...extraChoices
]

const avatarLookup = new Map(DEFAULT_AVATAR_CHOICES.map(choice => [choice.id, choice.src]))

export function resolveAvatarSrc(value: string): string | undefined {
  if (!value) return undefined
  if (value.startsWith('aura-avatar://')) return value
  return avatarLookup.get(value)
}

export function defaultAvatarIdForPersona(personaId: string): string {
  return IS_KOREAN_EDITION ? `default:${personaId}-ko` : `default:${personaId}`
}
