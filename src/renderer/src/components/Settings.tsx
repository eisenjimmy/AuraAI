import { useEffect, useState } from 'react'
import type { AppSettings, Persona, ProviderId, ProviderPreset, VoiceSettings } from '@common/types'
import { Avatar } from './Avatar'
import { listVoices, normalizeForSpeech } from '../lib/voice'
import { CloseIcon, PlayIcon } from './Icons'

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
          <h2>Settings</h2>
          <button className="icon-btn" onClick={props.onClose}><CloseIcon /></button>
        </div>
        <div className="tabs">
          <button className={`tab ${tab === 'ai' ? 'active' : ''}`} onClick={() => setTab('ai')}>AI Provider</button>
          <button className={`tab ${tab === 'personas' ? 'active' : ''}`} onClick={() => setTab('personas')}>Personas</button>
          <button className={`tab ${tab === 'chat' ? 'active' : ''}`} onClick={() => setTab('chat')}>Chat & Features</button>
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
    setStatus({ ok: true, message: 'Saved.' })
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
          <div className="field">
            <label>Server URL</label>
            <input
              value={draft.provider.baseUrl ?? ''}
              onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, baseUrl: e.target.value } }))}
            />
            <div className="hint">Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp…</div>
          </div>
        )}
        {preset?.needsApiKey && (
          <div className="field">
            <label>API key</label>
            <input
              type="password"
              value={draft.provider.apiKey ?? ''}
              onChange={e => setDraft(d => ({ ...d, provider: { ...d.provider, apiKey: e.target.value } }))}
            />
          </div>
        )}
        <div className="field">
          <label>Model</label>
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
            {testing ? 'Testing…' : 'Test connection'}
          </button>
          <button className="btn primary" onClick={save}>Save</button>
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
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([])

  useEffect(() => {
    const load = (): void => setVoices(listVoices())
    load()
    window.speechSynthesis.addEventListener('voiceschanged', load)
    return () => window.speechSynthesis.removeEventListener('voiceschanged', load)
  }, [])

  // Refresh the draft only when the selection changes — a background personas
  // refetch (after save) must not clobber edits in progress.
  useEffect(() => {
    const p = personas.find(x => x.id === selectedId)
    if (p) setDraft({ ...p, voice: { ...p.voice } })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId])

  if (!draft) return <p>No personas.</p>

  const setVoice = (patch: Partial<VoiceSettings>): void =>
    setDraft(d => (d ? { ...d, voice: { ...d.voice, ...patch } } : d))

  const preview = (): void => {
    window.speechSynthesis.cancel()
    const u = new SpeechSynthesisUtterance(
      normalizeForSpeech(`Hey! I'm ${draft.name}. ${draft.tagline}`)
    )
    u.rate = draft.voice.rate
    u.pitch = draft.voice.pitch
    const v = voices.find(x => x.name === draft.voice.voice)
    if (v) u.voice = v
    window.speechSynthesis.speak(u)
  }

  const save = async (): Promise<void> => {
    await window.aura.savePersona(draft)
    onPersonasChanged()
  }

  const reset = async (): Promise<void> => {
    if (!window.confirm(`Reset ${draft.name} to the built-in default?`)) return
    const restored = await window.aura.resetPersona(draft.id)
    setDraft({ ...restored, voice: { ...restored.voice } })
    onPersonasChanged()
  }

  const pickAvatar = async (): Promise<void> => {
    const avatar = await window.aura.pickAvatar(draft.id)
    if (avatar) setDraft(d => (d ? { ...d, avatar } : d))
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
          <button className="btn" onClick={() => void pickAvatar()}>Upload profile image…</button>
          {draft.avatar && (
            <button className="btn ghost" onClick={() => setDraft(d => (d ? { ...d, avatar: '' } : d))}>
              Remove
            </button>
          )}
          <div className="hint" style={{ marginTop: 6 }}>
            PNG, JPG, GIF or WebP. Shown at 40px in chat, like a Discord avatar.
          </div>
        </div>
      </div>

      <div className="row">
        <div className="field">
          <label>Name</label>
          <input value={draft.name} onChange={e => setDraft(d => (d ? { ...d, name: e.target.value } : d))} />
        </div>
        <div className="field">
          <label>Accent color</label>
          <input
            type="color"
            value={draft.color}
            style={{ height: 42, padding: 4 }}
            onChange={e => setDraft(d => (d ? { ...d, color: e.target.value } : d))}
          />
        </div>
      </div>
      <div className="field">
        <label>Tagline</label>
        <input value={draft.tagline} onChange={e => setDraft(d => (d ? { ...d, tagline: e.target.value } : d))} />
      </div>
      <div className="field">
        <label>Personality (system prompt)</label>
        <textarea
          rows={8}
          value={draft.prompt}
          onChange={e => setDraft(d => (d ? { ...d, prompt: e.target.value } : d))}
        />
      </div>

      <div className="field">
        <label>Voice</label>
        <div className="voice-preview">
          <select
            style={{ flex: 1 }}
            value={draft.voice.voice}
            onChange={e => setVoice({ voice: e.target.value })}
          >
            <option value="">System default</option>
            {voices.map(v => (
              <option key={v.name} value={v.name}>
                {v.name} ({v.lang})
              </option>
            ))}
          </select>
          <button className="btn" onClick={preview} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <PlayIcon /> Preview
          </button>
        </div>
      </div>
      <div className="row">
        <div className="field">
          <label>Rate ({draft.voice.rate.toFixed(2)})</label>
          <input
            type="range"
            min={0.5}
            max={1.6}
            step={0.02}
            value={draft.voice.rate}
            onChange={e => setVoice({ rate: Number(e.target.value) })}
          />
        </div>
        <div className="field">
          <label>Pitch ({draft.voice.pitch.toFixed(2)})</label>
          <input
            type="range"
            min={0.5}
            max={1.6}
            step={0.02}
            value={draft.voice.pitch}
            onChange={e => setVoice({ pitch: Number(e.target.value) })}
          />
        </div>
      </div>

      <div className="row">
        <button className="btn primary" onClick={() => void save()}>Save persona</button>
        {draft.builtIn && (
          <button className="btn ghost" onClick={() => void reset()}>Reset to default</button>
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

  return (
    <>
      <div className="row" style={{ marginBottom: 4 }}>
        <div className="field">
          <label>Your name</label>
          <input value={draft.userName} onChange={e => update({ userName: e.target.value })} />
        </div>
        <div className="field">
          <label>Theme</label>
          <select value={draft.theme} onChange={e => update({ theme: e.target.value as 'dark' | 'light' })}>
            <option value="dark">Dark</option>
            <option value="light">Light</option>
          </select>
        </div>
      </div>
      <div className="field">
        <label>About you</label>
        <textarea rows={2} value={draft.userBio} onChange={e => update({ userBio: e.target.value })} />
      </div>

      <Toggle
        label="Voice replies"
        desc="Friends speak their replies out loud using each persona's voice."
        on={draft.voiceEnabled}
        onToggle={toggle('voiceEnabled')}
      />
      <Toggle
        label="Web search & current awareness"
        desc="When a question needs fresh information, Aura quietly searches the web and answers with today's context."
        on={draft.webSearchEnabled}
        onToggle={toggle('webSearchEnabled')}
      />
      <Toggle
        label="Long-term memory"
        desc="Friends remember durable facts about you between conversations. Stored as plain markdown you can open in Obsidian."
        on={draft.memoryEnabled}
        onToggle={toggle('memoryEnabled')}
      />
      <Toggle
        label="Tools mode (advanced)"
        desc="Lets the model decide when to search, read pages and save memories itself (agentic tool-calling, up to 4 rounds). Off = Aura's simpler, deterministic pipeline. Needs a model with solid tool-calling."
        on={draft.toolsMode}
        onToggle={toggle('toolsMode')}
      />

      <div style={{ marginTop: 16 }}>
        <div className="field">
          <label>Search provider</label>
          <select
            value={draft.searchProvider}
            onChange={e => update({ searchProvider: e.target.value as AppSettings['searchProvider'] })}
          >
            <option value="auto">Auto (use key if set, else DuckDuckGo)</option>
            <option value="duckduckgo">DuckDuckGo (no key)</option>
            <option value="brave">Brave Search API</option>
            <option value="tavily">Tavily</option>
          </select>
        </div>
        {(draft.searchProvider === 'brave' || draft.searchProvider === 'tavily' || draft.searchProvider === 'auto') && (
          <div className="field">
            <label>Search API key (optional)</label>
            <input
              type="password"
              placeholder="Improves search quality — brave.com/search/api or tavily.com"
              value={draft.searchApiKey ?? ''}
              onChange={e => update({ searchApiKey: e.target.value })}
            />
          </div>
        )}
      </div>
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
