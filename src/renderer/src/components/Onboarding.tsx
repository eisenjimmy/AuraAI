import { useEffect, useState } from 'react'
import type { AppSettings, Persona, ProviderId, ProviderPreset } from '@common/types'
import { Avatar } from './Avatar'
import { t } from '../lib/i18n'

// First-run wizard: Welcome → AI provider → Your name → Pick a friend → Go.

interface OnboardingProps {
  settings: AppSettings
  personas: Persona[]
  onComplete: (settings: AppSettings) => void
}

const TOTAL_STEPS = 4

export function Onboarding({ settings, personas, onComplete }: OnboardingProps): React.JSX.Element {
  const [step, setStep] = useState(0)
  const [presets, setPresets] = useState<ProviderPreset[]>([])
  const [draft, setDraft] = useState<AppSettings>({ ...settings })
  const [testStatus, setTestStatus] = useState<{ ok: boolean; message: string } | null>(null)
  const [testing, setTesting] = useState(false)
  const [localModels, setLocalModels] = useState<string[]>([])

  useEffect(() => {
    void window.auraPresets.getProviderPresets().then(setPresets)
  }, [])

  const preset = presets.find(p => p.id === draft.provider.provider)

  const fetchLocalModels = (baseUrl: string): void => {
    void window.aura.listLocalModels(baseUrl).then(models => {
      setLocalModels(models)
      // Guard: the user may have switched provider while this was in flight.
      setDraft(d =>
        d.provider.provider === 'local' && models.length > 0 && !models.includes(d.provider.model)
          ? { ...d, provider: { ...d.provider, model: models[0] } }
          : d
      )
    })
  }

  // The wizard starts on Local — detect installed OpenAI-compatible models right away.
  useEffect(() => {
    if (draft.provider.provider === 'local' && draft.provider.baseUrl) {
      fetchLocalModels(draft.provider.baseUrl)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const chooseProvider = (id: ProviderId): void => {
    if (id === draft.provider.provider) return // re-click keeps the typed key/model
    const p = presets.find(x => x.id === id)
    if (!p) return
    setTestStatus(null)
    setDraft(d => ({
      ...d,
      provider: {
        provider: id,
        model: p.defaultModel,
        apiKey: '',
        baseUrl: p.defaultBaseUrl
      }
    }))
    if (id === 'local' && p.defaultBaseUrl) fetchLocalModels(p.defaultBaseUrl)
  }

  const testConnection = async (): Promise<void> => {
    setTesting(true)
    setTestStatus(null)
    const result = await window.aura.testProvider(draft.provider)
    setTestStatus(result)
    if (result.ok && result.models?.length && draft.provider.provider === 'local') {
      setLocalModels(result.models)
      if (!result.models.includes(draft.provider.model)) {
        setDraft(d => ({ ...d, provider: { ...d.provider, model: result.models![0] } }))
      }
    }
    setTesting(false)
  }

  const finish = (): void => {
    onComplete({ ...draft, onboarded: true })
  }

  const canLeaveProviderStep =
    draft.provider.model.trim().length > 0 &&
    (!preset?.needsApiKey || (draft.provider.apiKey ?? '').trim().length > 0)

  return (
    <div className="onboarding">
      <div className="panel">
        <div className="steps">
          {Array.from({ length: TOTAL_STEPS }, (_, i) => (
            <div key={i} className={`step-dot ${i <= step ? 'done' : ''}`} />
          ))}
        </div>

        {step === 0 && (
          <>
            <h1>{t.onboarding.welcomeTitle}</h1>
            <p className="lede">
              {t.onboarding.welcomeLead1}
            </p>
            <p className="lede">{t.onboarding.welcomeLead2}</p>
            <div className="modal-footer" style={{ border: 'none', padding: '8px 0 0' }}>
              <button className="btn primary" onClick={() => setStep(1)}>
                {t.onboarding.getStarted}
              </button>
            </div>
          </>
        )}

        {step === 1 && (
          <>
            <h1>{t.onboarding.providerTitle}</h1>
            <p className="lede">
              {t.onboarding.providerLead}
            </p>
            <div className="provider-cards">
              {presets.map(p => (
                <button
                  key={p.id}
                  className={`provider-card ${draft.provider.provider === p.id ? 'selected' : ''}`}
                  onClick={() => chooseProvider(p.id)}
                >
                  <div className="p-name">{p.label}</div>
                  <div className="p-desc">{p.description}</div>
                </button>
              ))}
            </div>

            <div style={{ marginTop: 18 }}>
              {preset?.id === 'local' && (
                <div className="field">
                  <label>{t.onboarding.serverUrl}</label>
                  <input
                    value={draft.provider.baseUrl ?? ''}
                    onChange={e => {
                      setTestStatus(null)
                      setDraft(d => ({ ...d, provider: { ...d.provider, baseUrl: e.target.value } }))
                    }}
                    onBlur={e => fetchLocalModels(e.target.value)}
                  />
                  <div className="hint">
                    {t.onboarding.jarvisHint}<code>npm run llm:gemma4-v2</code>
                  </div>
                </div>
              )}
              {preset?.needsApiKey && (
                <div className="field">
                  <label>{t.onboarding.apiKey}</label>
                  <input
                    type="password"
                    placeholder={
                      preset.id === 'anthropic'
                        ? 'sk-ant-…  (console.anthropic.com)'
                        : preset.id === 'openai'
                          ? 'sk-…  (platform.openai.com)'
                          : 'AI…  (aistudio.google.com)'
                    }
                    value={draft.provider.apiKey ?? ''}
                    onChange={e => {
                      setTestStatus(null)
                      setDraft(d => ({ ...d, provider: { ...d.provider, apiKey: e.target.value } }))
                    }}
                  />
                </div>
              )}
              <div className="field">
                <label>{t.onboarding.model}</label>
                {draft.provider.provider === 'local' && localModels.length > 0 ? (
                  <select
                    value={draft.provider.model}
                    onChange={e =>
                      setDraft(d => ({ ...d, provider: { ...d.provider, model: e.target.value } }))
                    }
                  >
                    {localModels.map(m => (
                      <option key={m} value={m}>{m}</option>
                    ))}
                  </select>
                ) : preset && preset.models.length > 0 ? (
                  <select
                    value={draft.provider.model}
                    onChange={e =>
                      setDraft(d => ({ ...d, provider: { ...d.provider, model: e.target.value } }))
                    }
                  >
                    {preset.models.map(m => (
                      <option key={m} value={m}>{m}</option>
                    ))}
                  </select>
                ) : (
                  <input
                    value={draft.provider.model}
                    placeholder={t.onboarding.modelPlaceholder}
                    onChange={e =>
                      setDraft(d => ({ ...d, provider: { ...d.provider, model: e.target.value } }))
                    }
                  />
                )}
              </div>
              <button className="btn" onClick={() => void testConnection()} disabled={testing}>
                {testing ? t.common.testing : t.common.testConnection}
              </button>
              {testStatus && (
                <div className={`status ${testStatus.ok ? 'ok' : 'err'}`}>{testStatus.message}</div>
              )}
            </div>

            <div className="modal-footer" style={{ border: 'none', padding: '16px 0 0' }}>
              <button className="btn ghost" onClick={() => setStep(0)}>{t.common.back}</button>
              <button className="btn primary" disabled={!canLeaveProviderStep} onClick={() => setStep(2)}>
                {t.common.continue}
              </button>
            </div>
          </>
        )}

        {step === 2 && (
          <>
            <h1>{t.onboarding.aboutTitle}</h1>
            <p className="lede">
              {t.onboarding.aboutLead}
            </p>
            <div className="field">
              <label>{t.onboarding.yourName}</label>
              <input
                value={draft.userName}
                placeholder={t.onboarding.namePlaceholder}
                onChange={e => setDraft(d => ({ ...d, userName: e.target.value }))}
              />
            </div>
            <div className="field">
              <label>{t.onboarding.bioLabel}</label>
              <textarea
                rows={3}
                value={draft.userBio}
                placeholder={t.onboarding.bioPlaceholder}
                onChange={e => setDraft(d => ({ ...d, userBio: e.target.value }))}
              />
            </div>
            <div className="modal-footer" style={{ border: 'none', padding: '8px 0 0' }}>
              <button className="btn ghost" onClick={() => setStep(1)}>{t.common.back}</button>
              <button className="btn primary" disabled={!draft.userName.trim()} onClick={() => setStep(3)}>
                {t.common.continue}
              </button>
            </div>
          </>
        )}

        {step === 3 && (
          <>
            <h1>{t.onboarding.personaTitle}</h1>
            <p className="lede">{t.onboarding.personaLead}</p>
            <div className="persona-cards">
              {personas.map(p => (
                <button
                  key={p.id}
                  className={`persona-card ${draft.activePersonaId === p.id ? 'selected' : ''}`}
                  onClick={() => setDraft(d => ({ ...d, activePersonaId: p.id }))}
                >
                  <Avatar persona={p} size={48} />
                  <div className="p-name">{p.name}</div>
                  <div className="p-tag">{p.tagline}</div>
                </button>
              ))}
            </div>
            <div className="modal-footer" style={{ border: 'none', padding: '16px 0 0' }}>
              <button className="btn ghost" onClick={() => setStep(2)}>{t.common.back}</button>
              <button className="btn primary" onClick={finish}>
                {t.onboarding.startChatting}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
