import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, unlinkSync } from 'fs'
import { join } from 'path'
import { dataDir } from './store'
import type { ChatMessage } from '@common/types'

// One JSON file per persona, like a DM thread.

function chatsDir(): string {
  const dir = join(dataDir(), 'chats')
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  return dir
}

function chatFile(personaId: string): string {
  const safe = personaId.replace(/[^a-z0-9-]/gi, '_')
  return join(chatsDir(), `${safe}.json`)
}

export function loadChat(personaId: string): ChatMessage[] {
  const file = chatFile(personaId)
  try {
    if (!existsSync(file)) return []
    return JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    return []
  }
}

export function saveChat(personaId: string, messages: ChatMessage[]): void {
  const file = chatFile(personaId)
  const tmp = file + '.tmp'
  writeFileSync(tmp, JSON.stringify(messages, null, 2), 'utf8')
  renameSync(tmp, file)
}

export function appendMessage(personaId: string, message: ChatMessage): ChatMessage[] {
  const messages = loadChat(personaId)
  messages.push(message)
  saveChat(personaId, messages)
  return messages
}

export function updateMessage(personaId: string, message: ChatMessage): void {
  const messages = loadChat(personaId)
  const idx = messages.findIndex(m => m.id === message.id)
  if (idx < 0) return // chat was cleared mid-stream; don't resurrect the reply
  messages[idx] = message
  saveChat(personaId, messages)
}

export function clearChat(personaId: string): void {
  const file = chatFile(personaId)
  try { if (existsSync(file)) unlinkSync(file) } catch { /* ignore */ }
}
