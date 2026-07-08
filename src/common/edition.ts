export type AuraEdition = 'en' | 'ko'

declare const __AURA_EDITION__: AuraEdition | undefined

export const AURA_EDITION: AuraEdition =
  typeof __AURA_EDITION__ !== 'undefined' && __AURA_EDITION__ === 'ko' ? 'ko' : 'en'

export const IS_KOREAN_EDITION = AURA_EDITION === 'ko'

export const APP_NAME = IS_KOREAN_EDITION ? '아우라 AI' : 'Aura AI'
export const APP_PRODUCT_NAME = IS_KOREAN_EDITION ? 'Aura AI Korean' : 'Aura AI'
