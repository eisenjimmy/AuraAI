import { useEffect, useState } from 'react'
import type { AppSettings, LocalLlmSettings, LocalLlmStatus } from '@common/types'
import { t } from '../lib/i18n'

interface LocalLlmSetupProps {
  draft: AppSettings
  onDraftChange: (next: AppSettings) => void
  onSave?: (next: AppSettings) => void
}

export function LocalLlmSetup({ draft, onDraftChange, onSave }: LocalLlmSetupProps): React.JSX.Element {
  const [status, setStatus] = useState<LocalLlmStatus | null>(null)
  const [busy, setBusy] = useState(false)
  const local = normalize(draft.localLlm)

  const update = (patch: Partial<LocalLlmSettings>, persist = false): AppSettings => {
    const nextLocal = { ...local, ...patch }
    const next = {
      ...draft,
      localLlm: nextLocal,
      provider: {
        ...draft.provider,
        provider: 'local' as const,
        baseUrl: `http://127.0.0.1:${nextLocal.port || 8080}/v1`,
        model: modelId(nextLocal.modelPath) || draft.provider.model || 'gemma-4-E4B-it-Q4_K_M'
      }
    }
    onDraftChange(next)
    if (persist) onSave?.(next)
    return next
  }

  useEffect(() => {
    void window.aura.getLocalLlmStatus().then(setStatus)
    const off = window.aura.onLocalLlmStatus(setStatus)
    return off
  }, [])

  const chooseBinary = async (): Promise<void> => {
    const binaryPath = await window.aura.chooseLocalLlmBinary()
    if (binaryPath) update({ binaryPath }, true)
  }

  const chooseModel = async (): Promise<void> => {
    const modelPath = await window.aura.chooseLocalLlmModel()
    if (modelPath) update({ modelPath }, true)
  }

  const download = async (): Promise<void> => {
    setBusy(true)
    const next = update({ mode: 'managed' }, true)
    try {
      setStatus(await window.aura.downloadRecommendedLocalModel())
      onSave?.(next)
    } finally {
      setBusy(false)
    }
  }

  const start = async (): Promise<void> => {
    setBusy(true)
    const next = update({ mode: 'managed' }, true)
    try {
      setStatus(await window.aura.startLocalLlm(next.localLlm))
    } finally {
      setBusy(false)
    }
  }

  const stop = async (): Promise<void> => {
    setBusy(true)
    try {
      setStatus(await window.aura.stopLocalLlm())
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="local-llm-panel">
      <div className="setup-choice">
        <button
          className={`setup-card ${local.mode === 'managed' ? 'selected' : ''}`}
          onClick={() => update({ mode: 'managed' }, true)}
        >
          <span>{t.localLlm.beginnerTitle}</span>
          <small>{t.localLlm.beginnerDesc}</small>
        </button>
        <button
          className={`setup-card ${local.mode === 'manual' ? 'selected' : ''}`}
          onClick={() => update({ mode: 'manual' }, true)}
        >
          <span>{t.localLlm.manualTitle}</span>
          <small>{t.localLlm.manualDesc}</small>
        </button>
      </div>

      {local.mode === 'managed' && (
        <>
          <p className="hint">{t.localLlm.recommendation(status?.recommendedModel ?? 'Gemma 4 E4B', status?.recommendedHf ?? 'unsloth/gemma-4-E4B-it-GGUF')}</p>
          <div className="row">
            <button className="btn" onClick={() => void download()} disabled={busy || status?.downloading}>
              {status?.downloading ? t.localLlm.downloading(percent(status.downloadProgress)) : t.localLlm.download}
            </button>
            {status?.running ? (
              <button className="btn" onClick={() => void stop()} disabled={busy}>{t.localLlm.stop}</button>
            ) : (
              <button className="btn primary" onClick={() => void start()} disabled={busy}>{t.localLlm.start}</button>
            )}
          </div>
          <div className="field compact">
            <label>{t.localLlm.llamaBinary}</label>
            <div className="path-row">
              <input value={local.binaryPath || status?.binaryPath || ''} onChange={e => update({ binaryPath: e.target.value })} />
              <button className="btn" onClick={() => void chooseBinary()}>{t.common.choose}</button>
            </div>
            <div className="hint">{status?.binaryFound ? t.localLlm.binaryFound : t.localLlm.binaryMissing}</div>
          </div>
          <div className="field compact">
            <label>{t.localLlm.modelFile}</label>
            <div className="path-row">
              <input value={local.modelPath || status?.modelPath || ''} onChange={e => update({ modelPath: e.target.value })} />
              <button className="btn" onClick={() => void chooseModel()}>{t.common.choose}</button>
            </div>
            <div className="hint">{status?.modelExists ? t.localLlm.modelReady(bytes(status.modelBytes)) : t.localLlm.modelMissing}</div>
          </div>
          <div className="field compact">
            <label>{t.localLlm.port}</label>
            <input type="number" min={1024} max={65535} value={local.port} onChange={e => update({ port: Number(e.target.value) || 8080 })} />
          </div>
          {status?.downloadMessage && <div className={`status ${status.running || status.modelExists ? 'ok' : 'err'}`}>{status.downloadMessage}</div>}
        </>
      )}
    </div>
  )
}

function normalize(settings?: LocalLlmSettings): LocalLlmSettings {
  return { mode: settings?.mode || 'manual', port: settings?.port || 8080, binaryPath: settings?.binaryPath, modelPath: settings?.modelPath }
}

function modelId(path?: string): string {
  if (!path) return ''
  const file = path.split(/[\\/]/).pop() ?? ''
  return file.replace(/\.gguf$/i, '')
}

function percent(value?: number): string {
  return value === undefined ? '' : ` ${Math.round(value * 100)}%`
}

function bytes(value: number): string {
  if (value > 1024 ** 3) return `${(value / 1024 ** 3).toFixed(1)} GB`
  if (value > 1024 ** 2) return `${Math.round(value / 1024 ** 2)} MB`
  return `${value} B`
}
