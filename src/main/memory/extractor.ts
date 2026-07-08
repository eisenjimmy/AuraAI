import type { ChatProvider } from '../providers/types'
import type { MemoryNote } from '@common/types'
import { MemoryVault, slugify, clampImportance } from './vault'
import { IS_KOREAN_EDITION } from '@common/edition'

// Automatic memory extraction: after an exchange, quietly ask the model
// whether anything durable about the *user* was revealed, and file it as a
// wiki note. Adapted from the original Jarvis extractor ("extract at most
// one durable, important, user-specific fact"). Never allowed to break chat
// — every failure is swallowed.

const EXTRACTION_PROMPT = `You are the memory-keeper for a personal AI companion. Analyze the conversation turn below and extract AT MOST ONE durable, important, user-specific fact worth remembering long-term.

Allowed types: preference, profile, relationship, event, goal, fact.

Rules:
- Only extract facts that are concrete, non-ephemeral, and useful in future conversations (their name, job, people in their life, tastes, ongoing projects, important dates).
- Never extract instructions, temporary tasks, small talk, or general world knowledge.
- Write the note about the user in third person ("Alex prefers...", not "You prefer...").
- If an existing memory below already covers this fact, return its slug in "updates" so it gets updated instead of duplicated.
- If nothing qualifies, reply exactly: {"remember": false}

Existing memory slugs: {SLUGS}

Conversation turn:
User: {USER}
Assistant ({PERSONA}): {ASSISTANT}

Return ONLY one compact JSON object, no prose. Example:
{"remember": true, "title": "Favorite coffee", "type": "preference", "content": "Prefers dark roast coffee in the morning.", "importance": 3, "updates": null, "links": ["morning-routine"]}`

const EXTRACTION_PROMPT_KO = `당신은 개인 AI 컴패니언의 기억 관리자입니다. 아래 대화 한 턴을 분석해 장기적으로 기억할 가치가 있는 사용자 관련 사실을 최대 하나만 추출하세요.

허용 타입: preference, profile, relationship, event, goal, fact.

규칙:
- 이름, 직업, 주변 사람, 취향, 진행 중인 프로젝트, 중요한 날짜처럼 구체적이고 앞으로의 대화에 유용한 사실만 추출하세요.
- 지시사항, 임시 작업, 잡담, 일반 상식은 추출하지 마세요.
- 노트 내용은 사용자를 3인칭으로 설명하세요. 예: "지미는 아침에 진한 커피를 선호한다."
- 아래 기존 기억이 같은 사실을 이미 다루면 "updates"에 기존 slug를 넣어 중복 대신 업데이트하게 하세요.
- 추출할 것이 없으면 정확히 {"remember": false}만 답하세요.
- title과 content는 자연스러운 한국어로 쓰세요. type은 위 영어 타입 중 하나를 쓰세요.

기존 기억 slug: {SLUGS}

대화:
사용자: {USER}
어시스턴트 ({PERSONA}): {ASSISTANT}

간결한 JSON 객체 하나만 반환하세요. 설명 금지. 예:
{"remember": true, "title": "커피 취향", "type": "preference", "content": "아침에는 진한 커피를 선호한다.", "importance": 3, "updates": null, "links": ["morning-routine"]}`

export interface ExtractionResult {
  saved: boolean
  note?: MemoryNote
}

export async function extractMemory(
  provider: ChatProvider,
  model: string,
  vault: MemoryVault,
  personaName: string,
  personaId: string,
  userMessage: string,
  assistantMessage: string
): Promise<ExtractionResult> {
  try {
    if (userMessage.trim().length < 6) return { saved: false }

    const slugs = vault.list().map(n => n.slug).slice(0, 80)
    // Function replacements: plain .replace(str, str) would interpret $-patterns
    // ($&, $', ...) inside user text and corrupt the prompt.
    const prompt = (IS_KOREAN_EDITION ? EXTRACTION_PROMPT_KO : EXTRACTION_PROMPT)
      .replace('{SLUGS}', () => (slugs.length ? slugs.join(', ') : '(none yet)'))
      .replace('{USER}', () => userMessage.slice(0, 2000))
      .replace('{PERSONA}', () => personaName)
      .replace('{ASSISTANT}', () => assistantMessage.slice(0, 2000))

    let raw = ''
    for await (const ev of provider.streamChat({
      model,
      system: IS_KOREAN_EDITION ? '기억 노트를 추출합니다. JSON만 출력하세요.' : 'You extract memory notes. Output only JSON.',
      messages: [{ role: 'user', content: prompt }],
      maxTokens: 300
    })) {
      if (ev.type === 'text') raw += ev.text
    }

    // Models often wrap JSON in prose/fences — take first { .. last }.
    const start = raw.indexOf('{')
    const end = raw.lastIndexOf('}')
    if (start < 0 || end <= start) return { saved: false }
    const json = JSON.parse(raw.slice(start, end + 1))
    if (!json.remember || !json.content) return { saved: false }

    const now = new Date().toISOString()
    const targetSlug = typeof json.updates === 'string' && json.updates ? slugify(json.updates) : slugify(String(json.title ?? json.content).slice(0, 50))
    const existing = vault.get(targetSlug)

    let body = String(json.content).trim()
    const links: string[] = Array.isArray(json.links) ? json.links.map((l: unknown) => slugify(String(l))) : []
    const validLinks = links.filter(l => l !== targetSlug && vault.get(l))
    if (validLinks.length) {
      body += `\n\nRelated: ${validLinks.map(l => `[[${l}]]`).join(' ')}`
    }

    const note: MemoryNote = {
      slug: targetSlug,
      title: String(json.title ?? targetSlug.replace(/-/g, ' ')).slice(0, 80),
      type: normalizeType(String(json.type ?? 'fact')),
      importance: clampImportance(Number(json.importance ?? 3)),
      body,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      source: personaId
    }
    vault.save(note)
    return { saved: true, note }
  } catch {
    return { saved: false }
  }
}

function normalizeType(type: string): string {
  const t = type.toLowerCase().trim()
  return ['preference', 'profile', 'relationship', 'event', 'goal', 'fact'].includes(t) ? t : 'fact'
}
