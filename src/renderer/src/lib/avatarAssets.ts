const avatarUrls = {
  'nova': new URL('../assets/avatars/nova.png', import.meta.url).href,
  'sage': new URL('../assets/avatars/sage.png', import.meta.url).href,
  'rio': new URL('../assets/avatars/rio.png', import.meta.url).href,
  'luna': new URL('../assets/avatars/luna.png', import.meta.url).href,
  'max': new URL('../assets/avatars/max.png', import.meta.url).href,
  'gilleon': new URL('../assets/avatars/gilleon.png', import.meta.url).href,
  'neir': new URL('../assets/avatars/neir.png', import.meta.url).href,
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

export const DEFAULT_AVATAR_CHOICES: AvatarChoice[] = [
  { id: 'default:nova', label: 'Nova original', src: avatarUrls.nova, builtInDefault: true },
  { id: 'default:sage', label: 'Sage original', src: avatarUrls.sage, builtInDefault: true },
  { id: 'default:rio', label: 'Rio original', src: avatarUrls.rio, builtInDefault: true },
  { id: 'default:luna', label: 'Luna original', src: avatarUrls.luna, builtInDefault: true },
  { id: 'default:max', label: 'Max original', src: avatarUrls.max, builtInDefault: true },
  { id: 'default:gilleon', label: 'Gilleon original', src: avatarUrls.gilleon, builtInDefault: true },
  { id: 'default:neir', label: 'Neir original', src: avatarUrls.neir, builtInDefault: true },
  { id: 'choice:korean-man', label: 'Korean man', src: avatarUrls['korean-man'] },
  { id: 'choice:korean-woman', label: 'Korean woman', src: avatarUrls['korean-woman'] },
  { id: 'choice:european-man', label: 'European man', src: avatarUrls['european-man'] },
  { id: 'choice:european-woman', label: 'European woman', src: avatarUrls['european-woman'] },
  { id: 'choice:south-asian-man', label: 'South Asian man', src: avatarUrls['south-asian-man'] },
  { id: 'choice:latina-woman', label: 'Latina woman', src: avatarUrls['latina-woman'] },
  { id: 'choice:middle-eastern-man', label: 'Middle Eastern man', src: avatarUrls['middle-eastern-man'] },
  { id: 'choice:black-woman', label: 'Black woman', src: avatarUrls['black-woman'] },
  { id: 'choice:silver-european-man', label: 'Silver-haired man', src: avatarUrls['silver-european-man'] },
  { id: 'choice:mixed-race-woman', label: 'Mixed-race woman', src: avatarUrls['mixed-race-woman'] }
]

const avatarLookup = new Map(DEFAULT_AVATAR_CHOICES.map(choice => [choice.id, choice.src]))

export function resolveAvatarSrc(value: string): string | undefined {
  if (!value) return undefined
  if (value.startsWith('aura-avatar://')) return value
  return avatarLookup.get(value)
}
