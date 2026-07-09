import { useEffect, useRef, useState } from 'react'
import type { AppSettings, Persona, ProviderId, ProviderPreset, VoiceSettings } from '@common/types'
import { Avatar, UserAvatar } from './Avatar'
import { KOKORO_VOICES, SpeechQueue, normalizeForSpeech } from '../lib/voice'
import { DEFAULT_AVATAR_CHOICES, defaultAvatarIdForPersona } from '../lib/avatarAssets'
import { CloseIcon, PlayIcon } from './Icons'
import { t } from '../lib/i18n'
import { LocalLlmSetup } from './LocalLlmSetup'

interface SettingsProps {
  settings: AppSettings
  personas: Persona[]
  onClose: () => void
  onSettingsSaved: (s: AppSettings) => void
  onPersonasChanged: () => void
}

type Tab = 'ai' | 'personas' | 'chat'

export function SettingsModal(props: SettingsProps): React.JSX.Element {
  const [tab, setTab] = useState<Tab>('ai')
  return (
    <div className="modal-overlay" onMouseDown={e => e.target === e.currentTarget && props.onClose()}>
      <div className="modal">
        <div className="modal-header">
          <h2>{t.settings.title}</h2>
          <button className="icon-btn" onClick={props.onClose}><CloseIcon /></button>
        </div>
        <div className="tabs">
          <button className={`tab ${tab === 'ai' ? 'active' : ''}`} onClick={() => setTab('ai')}>{t.settings.aiProvider}</button>
          <button className={`tab ${tab === 'personas' ? 'active' : ''}`} onClick={() => setTab('personas')}>{t.settings.personas}</button>
          <button className={`tab ${tab === 'chat' ? 'active' : ''}`} onClick={() => setTab('chat')}>{t.settings.chatFeatures}</button>
        </div>
        <div className="modal-body">
          {tab === 'ai' && <ProviderTab {...props} />}
          {tab === 'personas' && <PersonasTab {...props} />}
          {tab === 'chat' && <ChatTab {...props} />}
        </div>
      </div>
    </div>
  )
}

// ---------- AI provider ----------

function ProviderTab({ settings, onSettingsSaved }: SettingsProps): React.JSX.Element {
  const [presets, setPresets] = useState<ProviderPreset[]>([])
  const [draft, setDraft] = useState(settings)
  const [status, setStatus] = useState<{ ok: boolean; message: string } | null>(null)
  const [testing, setTesting] = useState(false)
  const [localModels, setLocalModels] = useState<string[]>([])

  useEffect(() => {
    void window.auraPresets.getProviderPresets().then(setPresets)
    if (settings.provider.provider === 'local' && settings.provider.baseUrl) {
      void window.aura.listLocalModels(settings.provider.baseUrl).then(setLocalModels)
    }
  }, [settings.provider.provider, settings.provider.baseUrl])

  const preset = presets.find(p => p.id === draft.provider.provider)

  const choose = (id: ProviderId): void => {
    if (id === draft.provider.provider) return // re-click must not reset anything
    const p = presets.find(x => x.id === id)
    if (!p) return
    setStatus(null)
    setDraft(d => ({
      ...d,
      provider:
        id === settings.provider.provider
          ? { ...settings.provider } // returning to the saved provider restores it fully
          : { provider: id, model: p.defaultModel, apiKey: '', baseUrl: p.defaultBaseUrl }
    }))
  }

  const test = async (): Promise<void> => {
    setTesting(true)
    setStatus(null)
    const result = await window.aura.testProvider(draft.provider)
    setStatus(result)
    if (result.ok && result.models?.length && draft.provider.provider === 'local') {
      setLocalModels(result.models)
    }
    setTesting(false)
  }

  const save = (): void => {
    onSettingsSaved(draft)
    setStatus({ ok: true, message: t.common.saved })
  }

  const modelOptions =
    draft.provider.provider === 'local' ? localModels : preset?.models ?? []

  return (
    <>
      <div className="provider-cards">
        {presets.map(p => (
          <button
            key={p.id}
            className={`provider-card ${draft.provider.provider === p.id ? 'selected' : ''}`}
            onClick={() => choose(p.id)}
          >
            <div className="p-name">{p.label}</div>
            <div className="p-desc">{p.description}</div>
          </button>
        ))}
      </div>
      <div style={{ marginTop: 16 }}>
        {preset?.id === 'local' && (
          <>
            <LocalLlmSetup draft={draft} onDraftChange={setDraft} onSave={onSettingsSaved} />
            {draft.localLlm?.mode !== 'managed' && (
              <div className="field">
                <label>{t.settings.serverUrl}</label>
                <input
                  value={draft.provider.baseUrl ?? ''}
                  onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, baseUrl: e.target.value } }))}
                />
                <div className="hint">{t.settings.serverHint}</div>
              </div>
            )}
          </>
        )}
        {preset?.needsApiKey && (
          <div className="field">
            <label>{t.settings.apiKey}</label>
            <input
              type="password"
              value={draft.provider.apiKey ?? ''}
              onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, apiKey: e.target.value } }))}
            />
          </div>
        )}
        <div className="field">
          <label>{t.settings.model}</label>
          {modelOptions.length > 0 ? (
            <select
              value={draft.provider.model}
              onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, model: e.target.value } }))}
            >
              {!modelOptions.includes(draft.provider.model) && draft.provider.model && (
                <option value={draft.provider.model}>{draft.provider.model}</option>
              )}
              {modelOptions.map(m => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          ) : (
            <input
              value={draft.provider.model}
              onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, model: e.target.value } }))}
            />
          )}
        </div>
        <div className="row">
          <button className="btn" onClick={() => void test()} disabled={testing}>
            {testing ? t.common.testing : t.common.testConnection}
          </button>
          <button className="btn primary" onClick={save}>{t.common.save}</button>
        </div>
        {status && <div className={`status ${status.ok ? 'ok' : 'err'}`}>{status.message}</div>}
      </div>
    </>
  )
}

// ---------- personas ----------

function PersonasTab({ personas, onPersonasChanged }: SettingsProps): React.JSX.Element {
  const [selectedId, setSelectedId] = useState(personas[0]?.id ?? '')
  const persona = personas.find(p => p.id === selectedId) ?? personas[0]
  const [draft, setDraft] = useState<Persona | null>(persona ?? null)
  const [voiceStatus, setVoiceStatus] = useState('')
  const previewSpeech = useRef<SpeechQueue | null>(null)

  useEffect(() => {
    previewSpeech.current = new SpeechQueue((status, message) => {
      if (status === 'loading') setVoiceStatus(t.settings.loadingVoice)
      else if (status === 'speaking') setVoiceStatus(t.settings.playingPreview)
      else if (status === 'error') setVoiceStatus(message ?? t.settings.voiceFailed)
      else setVoiceStatus('')
    })
    return () => previewSpeech.current?.stop()
  }, [])

  // Refresh the draft only when the selection changes — a background personas
  // refetch (after save) must not clobber edits in progress.
  useEffect(() => {
    const p = personas.find(x => x.id === selectedId)
    if (p) setDraft({ ...p, voice: { ...p.voice } })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId])

  if (!draft) return <p>{t.settings.noPersonas}</p>

  const setVoice = (patch: Partial<VoiceSettings>): void =>
    setDraft(d => (d ? { ...d, voice: { ...d.voice, ...patch } } : d))

  const preview = (): void => {
    const q = previewSpeech.current
    if (!q) return
    q.stop()
    q.setVoice({ ...draft.voice, voice: draft.voice.voice || 'af_heart' })
    q.push(normalizeForSpeech(t.settings.previewText(draft.name, draft.tagline)))
    q.flush()
  }

  const chooseAvatar = (avatar: string): void =>
    setDraft(d => (d ? { ...d, avatar } : d))

  const uploadAvatar = async (): Promise<void> => {
    const avatar = await window.aura.pickAvatar(draft.id)
    if (avatar) chooseAvatar(avatar)
  }

  const save = async (): Promise<void> => {
    await window.aura.savePersona(draft)
    onPersonasChanged()
  }

  const reset = async (): Promise<void> => {
    if (!window.confirm(t.settings.resetConfirm(draft.name))) return
    const restored = await window.aura.resetPersona(draft.id)
    setDraft({ ...restored, voice: { ...restored.voice } })
    onPersonasChanged()
  }

  return (
    <>
      <div className="persona-cards" style={{ marginBottom: 18 }}>
        {personas.map(p => (
          <button
            key={p.id}
            className={`persona-card ${p.id === selectedId ? 'selected' : ''}`}
            onClick={() => setSelectedId(p.id)}
          >
            <Avatar persona={p} size={44} />
            <div className="p-name">{p.name}</div>
          </button>
        ))}
      </div>

      <div className="row" style={{ alignItems: 'center', marginBottom: 16 }}>
        <div style={{ flex: '0 0 auto' }}>
          <Avatar persona={draft} size={72} />
        </div>
        <div>
          <div className="p-name">{draft.name}</div>
          <div className="hint" style={{ marginTop: 6 }}>
            {t.settings.defaultsHint}
          </div>
        </div>
      </div>

      <div className="field">
        <label>{t.settings.profileImage}</label>
        <div className="avatar-choice-grid">
          {DEFAULT_AVATAR_CHOICES.map(choice => (
            <button
              key={choice.id}
              className={`avatar-choice ${draft.avatar === choice.id ? 'selected' : ''}`}
              onClick={() => chooseAvatar(choice.id)}
              title={choice.label}
            >
              <img src={choice.src} alt="" />
              <span>{choice.id === defaultAvatarIdForPersona(draft.id) ? t.settings.original : choice.label}</span>
            </button>
          ))}
        </div>
        <div className="row" style={{ marginTop: 8 }}>
          {draft.builtIn && (
            <button className="btn ghost" onClick={() => chooseAvatar(defaultAvatarIdForPersona(draft.id))}>
              {t.settings.useOriginal}
            </button>
          )}
          <button className="btn" onClick={() => void uploadAvatar()}>
            {t.settings.uploadImage}
          </button>
        </div>
      </div>

      <div className="row">
        <div className="field">
          <label>{t.settings.name}</label>
          <input value={draft.name} onChange={e => setDraft(d => (d ? { ...d, name: e.target.value } : d))} />
        </div>
        <div className="field">
          <label>{t.settings.accentColor}</label>
          <input
            type="color"
            value={draft.color}
            style={{ height: 42, padding: 4 }}
            onChange={e => setDraft(d => (d ? { ...d, color: e.target.value } : d))}
          />
        </div>
      </div>
      <div className="field">
        <label>{t.settings.tagline}</label>
        <input value={draft.tagline} onChange={e => setDraft(d => (d ? { ...d, tagline: e.target.value } : d))} />
      </div>
      <div className="field">
        <label>{t.settings.prompt}</label>
        <textarea
          rows={8}
          value={draft.prompt}
          onChange={e => setDraft(d => (d ? { ...d, prompt: e.target.value } : d))}
        />
      </div>

      <div className="field">
        <label>{t.settings.kokoroVoice}</label>
        <div className="voice-preview">
          <select
            style={{ flex: 1 }}
            value={draft.voice.voice || 'af_heart'}
            onChange={e => setVoice({ voice: e.target.value })}
          >
            {KOKORO_VOICES.map(v => (
              <option key={v.id} value={v.id}>
                {v.label} ({t.settings.voiceGender[v.gender]}, {(t.settings.voiceLanguage as Record<string, string>)[v.language] ?? v.language})
              </option>
            ))}
          </select>
          <button className="btn" onClick={preview} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <PlayIcon /> {t.settings.preview}
          </button>
        </div>
        {voiceStatus && <div className="hint" style={{ marginTop: 6 }}>{voiceStatus}</div>}
      </div>
      <div className="field">
        <label>{t.settings.speed(draft.voice.rate.toFixed(2))}</label>
        <input
          type="range"
          min={0.5}
          max={1.6}
          step={0.02}
          value={draft.voice.rate}
          onChange={e => setVoice({ rate: Number(e.target.value) })}
        />
      </div>

      <div className="row">
        <button className="btn primary" onClick={() => void save()}>{t.settings.savePersona}</button>
        {draft.builtIn && (
          <button className="btn ghost" onClick={() => void reset()}>{t.settings.resetPersona}</button>
        )}
      </div>
    </>
  )
}

// ---------- chat & features ----------

function ChatTab({ settings, onSettingsSaved }: SettingsProps): React.JSX.Element {
  const [draft, setDraft] = useState(settings)

  // Side effects stay outside the setState updater (StrictMode double-invokes updaters).
  const update = (patch: Partial<AppSettings>): void => {
    const next = { ...draft, ...patch }
    setDraft(next)
    onSettingsSaved(next)
  }

  const toggle = (key: 'voiceEnabled' | 'webSearchEnabled' | 'memoryEnabled' | 'toolsMode') => (): void => {
    update({ [key]: !draft[key] })
  }

  const chooseImageFolder = async (): Promise<void> => {
    const folder = await window.aura.chooseImageStorageFolder()
    if (folder) update({ imageStoragePath: folder })
  }

  const chooseUserAvatar = async (): Promise<void> => {
    const avatar = await window.aura.pickAvatar('user')
    if (avatar) update({ userAvatar: avatar })
  }

  return (
    <>
      <div className="field">
        <label>{t.settings.userProfilePhoto}</label>
        <div className="profile-photo-row">
          <UserAvatar name={draft.userName} avatar={draft.userAvatar} size={54} />
          <div className="profile-photo-meta">
            <div className="hint">{t.settings.userProfilePhotoHint}</div>
            <div className="row compact">
              <button className="btn" onClick={() => void chooseUserAvatar()}>{t.settings.uploadImage}</button>
              {draft.userAvatar && (
                <button className="btn ghost" onClick={() => update({ userAvatar: '' })}>
                  {t.settings.removeImage}
                </button>
              )}
            </div>
          </div>
        </div>
      </div>
      <div className="row" style={{ marginBottom: 4 }}>
        <div className="field">
          <label>{t.settings.yourName}</label>
          <input value={draft.userName} onChange={e => update({ userName: e.target.value })} />
        </div>
        <div className="field">
          <label>{t.settings.theme}</label>
          <select value={draft.theme} onChange={e => update({ theme: e.target.value as 'dark' | 'light' })}>
            <option value="dark">{t.common.dark}</option>
            <option value="light">{t.common.light}</option>
          </select>
        </div>
      </div>
      <div className="field">
        <label>{t.settings.aboutYou}</label>
        <textarea rows={2} value={draft.userBio} onChange={e => update({ userBio: e.target.value })} />
      </div>

      <div className="field">
        <label>{t.settings.imageFolder}</label>
        <div className="path-row">
          <input value={draft.imageStoragePath ?? ''} onChange={e => update({ imageStoragePath: e.target.value })} />
          <button className="btn" onClick={() => void chooseImageFolder()}>{t.common.choose}</button>
        </div>
        <div className="hint">{t.settings.imageFolderHint}</div>
      </div>

      <Toggle
        label={t.settings.voiceReplies}
        desc={t.settings.voiceRepliesDesc}
        on={draft.voiceEnabled}
        onToggle={toggle('voiceEnabled')}
      />
      <Toggle
        label={t.settings.webSearch}
        desc={t.settings.webSearchDesc}
        on={draft.webSearchEnabled}
        onToggle={toggle('webSearchEnabled')}
      />
      <Toggle
        label={t.settings.memory}
        desc={t.settings.memoryDesc}
        on={draft.memoryEnabled}
        onToggle={toggle('memoryEnabled')}
      />
      <Toggle
        label={t.settings.toolsMode}
        desc={t.settings.toolsModeDesc}
        on={draft.toolsMode}
        onToggle={toggle('toolsMode')}
      />

    </>
  )
}

function Toggle({ label, desc, on, onToggle }: { label: string; desc: string; on: boolean; onToggle: () => void }): React.JSX.Element {
  return (
    <div className="toggle-row">
      <div>
        <div className="label">{label}</div>
        <div className="desc">{desc}</div>
      </div>
      <button className={`switch ${on ? 'on' : ''}`} onClick={onToggle} aria-pressed={on} />
    </div>
  )
}
