import type { AuraApi, ProviderPreset } from '@common/types'

declare global {
  interface Window {
    aura: AuraApi
    auraPresets: {
      getProviderPresets(): Promise<ProviderPreset[]>
    }
  }
}

export {}
