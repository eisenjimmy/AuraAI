import type { ProviderConfig, ProviderPreset } from '@common/types'
import type { ChatProvider } from './types'
import { OpenAICompatProvider } from './openaiCompat'
import { AnthropicProvider, ANTHROPIC_MODELS } from './anthropic'
import { GeminiProvider, GEMINI_MODELS } from './gemini'

export const OPENAI_MODELS = ['gpt-5.2', 'gpt-5-mini', 'gpt-4o', 'gpt-4o-mini']

export const PROVIDER_PRESETS: ProviderPreset[] = [
  {
    id: 'local',
    label: 'Local (Ollama)',
    description: 'Free & private. Runs on your machine via Ollama, LM Studio, or llama.cpp.',
    defaultModel: 'llama3.2',
    models: [],
    needsApiKey: false,
    defaultBaseUrl: 'http://localhost:11434/v1'
  },
  {
    id: 'anthropic',
    label: 'Claude (Anthropic)',
    description: 'Anthropic API. Great conversational quality.',
    defaultModel: 'claude-opus-4-8',
    models: ANTHROPIC_MODELS,
    needsApiKey: true
  },
  {
    id: 'openai',
    label: 'ChatGPT (OpenAI)',
    description: 'OpenAI API.',
    defaultModel: 'gpt-4o',
    models: OPENAI_MODELS,
    needsApiKey: true
  },
  {
    id: 'gemini',
    label: 'Gemini (Google)',
    description: 'Google AI Studio API. Generous free tier.',
    defaultModel: 'gemini-2.5-flash',
    models: GEMINI_MODELS,
    needsApiKey: true
  }
]

export function createProvider(config: ProviderConfig): ChatProvider {
  switch (config.provider) {
    case 'local':
      return new OpenAICompatProvider(
        config.baseUrl || 'http://localhost:11434/v1',
        undefined,
        'nomic-embed-text'
      )
    case 'openai':
      return new OpenAICompatProvider(
        'https://api.openai.com/v1',
        config.apiKey,
        'text-embedding-3-small'
      )
    case 'anthropic':
      return new AnthropicProvider(config.apiKey ?? '')
    case 'gemini':
      return new GeminiProvider(config.apiKey ?? '')
  }
}
