import type { ProviderConfig, ProviderPreset } from '@common/types'
import type { ChatProvider } from './types'
import { OpenAICompatProvider } from './openaiCompat'
import { AnthropicProvider, ANTHROPIC_MODELS } from './anthropic'
import { GeminiProvider, GEMINI_MODELS } from './gemini'
import { IS_KOREAN_EDITION } from '@common/edition'

export const OPENAI_MODELS = ['gpt-5.2', 'gpt-5-mini', 'gpt-4o', 'gpt-4o-mini']

export const PROVIDER_PRESETS: ProviderPreset[] = [
  {
    id: 'local',
    label: IS_KOREAN_EDITION ? '로컬 (llama.cpp)' : 'Local (llama.cpp)',
    description: IS_KOREAN_EDITION
      ? '무료와 프라이버시. Ollama, LM Studio, llama.cpp로 내 컴퓨터에서 실행합니다.'
      : 'Free & private. Runs on your machine via Ollama, LM Studio, or llama.cpp.',
    defaultModel: 'gemma-4-E4B-it-Q4_K_M',
    models: [],
    needsApiKey: false,
    defaultBaseUrl: 'http://127.0.0.1:8080/v1'
  },
  {
    id: 'anthropic',
    label: 'Claude (Anthropic)',
    description: IS_KOREAN_EDITION ? 'Anthropic API. 자연스러운 대화 품질이 강합니다.' : 'Anthropic API. Great conversational quality.',
    defaultModel: 'claude-opus-4-8',
    models: ANTHROPIC_MODELS,
    needsApiKey: true
  },
  {
    id: 'openai',
    label: 'ChatGPT (OpenAI)',
    description: IS_KOREAN_EDITION ? 'OpenAI API.' : 'OpenAI API.',
    defaultModel: 'gpt-4o',
    models: OPENAI_MODELS,
    needsApiKey: true
  },
  {
    id: 'gemini',
    label: 'Gemini (Google)',
    description: IS_KOREAN_EDITION ? 'Google AI Studio API. 무료 사용량이 넉넉합니다.' : 'Google AI Studio API. Generous free tier.',
    defaultModel: 'gemini-2.5-flash',
    models: GEMINI_MODELS,
    needsApiKey: true
  }
]

export function createProvider(config: ProviderConfig): ChatProvider {
  switch (config.provider) {
    case 'local':
      return new OpenAICompatProvider(
        config.baseUrl || 'http://127.0.0.1:8080/v1',
        undefined,
        localEmbeddingModel(config)
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

function localEmbeddingModel(config: ProviderConfig): string {
  const baseUrl = config.baseUrl || 'http://127.0.0.1:8080/v1'
  if (baseUrl.includes('127.0.0.1:8080') || baseUrl.includes('localhost:8080')) {
    return config.model || 'gemma4-v2'
  }
  return 'nomic-embed-text'
}
