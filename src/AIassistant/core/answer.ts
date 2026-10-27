// The preview's stand-in for the backend answer: keyword retrieval over the passages the role
// may read, then a short answer with [n] citations. The real backend swaps in embeddings and
// the company's model, but keeps the same rules: allowed passages only, refuse personal data,
// say "I don't know" rather than guess.
import { canReadResource } from './access'
import type { Answer, AssistantSetup, Citation, Passage, Resource, RoleKey, RoleMessages, UpdateItem } from './types'

const STOP = new Set([
  'a', 'an', 'the', 'is', 'are', 'am', 'do', 'does', 'i', 'me', 'my', 'we', 'our', 'you', 'your', 'how', 'what', 'when',
  'where', 'which', 'who', 'can', 'get', 'of', 'to', 'in', 'on', 'for', 'and', 'or', 'it', 'be', 'per', 'any', 'about',
  'there', 'with', 'this', 'that', 'much', 'many', 'please', 'tell', 'rule', 'rules',
  'কী', 'কি', 'কত', 'কয়টা', 'কয়টায়', 'আমি', 'আমার', 'আমাদের', 'এর', 'ও', 'এবং', 'হয়', 'হবে', 'নিয়ম',
])

export function terms(text: string): string[] {
  const words = text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []
  return [...new Set(words.filter((w) => w.length > 1 && !STOP.has(w)))]
}

/** Same word, or with a short ending (leave / leaves, approve / approved), but not "members" for "membership". */
const sameWord = (a: string, b: string) => {
  const [short, long] = a.length <= b.length ? [a, b] : [b, a]
  return long.startsWith(short) && long.length - short.length <= 2 && short.length >= 3
}

/** Share of the question's terms found in the passage, 0–1. */
export function matchScore(questionTerms: string[], passage: Passage): number {
  if (questionTerms.length === 0) return 0
  const hay = terms(`${passage.section} ${passage.text}`)
  const hits = questionTerms.filter((q) => hay.some((h) => h === q || sameWord(h, q))).length
  return hits / questionTerms.length
}

interface Hit { resource: Resource; passage: Passage; score: number }

function search(question: string, resources: Resource[], minScore: number, topK: number): Hit[] {
  const q = terms(question)
  return resources
    .flatMap((resource) => resource.passages.map((passage) => ({ resource, passage, score: matchScore(q, passage) })))
    .filter((h) => h.score > 0 && h.score >= minScore)
    .sort((a, b) => b.score - a.score)
    .slice(0, topK)
}

// Questions about records: the assistant never looks them up, it sends people to the page.
const PERSONAL = [
  { re: /(salary|pay|gross|basic|বেতন).*(of|for)\s+[A-Z]|\b[A-Z][a-z]+'s\s+(salary|pay|phone|nid|address)/, page: 'Employees' },
  { re: /\b(nid|national id|phone number|mobile number|address|bank account)\b.*\b(of|for)\b/i, page: 'Employees' },
  { re: /\b(my|amar|আমার)\b.*\b(salary|net pay|gross|বেতন)\b/i, page: 'My payslips' },
  { re: /\b(absent|late)\b.*\b(days|times)\b|কত দিন (অনুপস্থিত|লেট)/i, page: 'My attendance' },
]
const UPDATES = /\b(update|updates|today|waiting|pending|new)\b|আজ|আপডেট/i

export const hasBangla = (text: string) => /[ঀ-৿]/.test(text)

const firstSentences = (text: string, count: number) =>
  text.replace(/\s+/g, ' ').split(/(?<=[.।!?])\s+/).slice(0, count).join(' ')

export function answerQuestion(
  question: string,
  ctx: { setup: AssistantSetup; role: RoleKey; allowed: Set<string>; updates: UpdateItem[]; messages: RoleMessages },
): Answer {
  const { setup, role, allowed, updates, messages } = ctx
  const bangla = setup.languageMode === 'bn' || (setup.languageMode === 'follow' && hasBangla(question))

  const personal = PERSONAL.find((p) => p.re.test(question))
  if (personal) {
    return {
      kind: 'personal_data', citations: [], usedTopics: [],
      text: bangla
        ? `আমি কর্মীদের রেকর্ড দেখতে পারি না। এই তথ্যের জন্য "${personal.page}" পেজ দেখুন।`
        : `I can't see employee records, so I can't look that up. You can find it on the "${personal.page}" page.`,
    }
  }

  const readable = setup.resources.filter((r) => canReadResource(r, role, allowed))
  const hits = search(question, readable, setup.hyper.minScore, setup.hyper.topK)

  if (hits.length === 0 && UPDATES.test(question) && updates.length > 0) {
    return {
      kind: 'updates', citations: [], usedTopics: [...new Set(updates.map((u) => u.topicKey))],
      text: (bangla ? 'আপনার আজকের আপডেট:\n' : 'Here are your updates:\n') + updates.map((u) => `• ${u.title} — ${u.detail}`).join('\n'),
    }
  }

  if (hits.length === 0) {
    // Is the answer in a resource this role may not read? Then say "not allowed", never the content.
    const hidden = setup.resources.filter((r) => r.status === 'ready' && !readable.includes(r))
    if (search(question, hidden, setup.hyper.minScore, 1).length > 0) {
      return { kind: 'not_allowed', text: messages.notAllowed, citations: [], usedTopics: [] }
    }
    return {
      kind: 'dont_know', citations: [], usedTopics: [],
      text: bangla
        ? 'কোম্পানির নথিতে এর উত্তর পাইনি। HR-কে জিজ্ঞেস করুন।'
        : "I couldn't find this in the company documents, so I don't know. Please ask HR.",
    }
  }

  const used = setup.hyper.answerStyle === 'short' ? hits.slice(0, 2) : hits.slice(0, 4)
  const citations: Citation[] = used.map((h, i) => ({
    n: i + 1, resourceId: h.resource.id, resourceName: h.resource.name,
    location: h.passage.location, section: h.passage.section, text: h.passage.text,
  }))
  const sentences = setup.hyper.answerStyle === 'short' ? 1 : 3
  const body = used.map((h, i) => `${firstSentences(h.passage.text, sentences)} [${i + 1}]`).join('\n\n')
  return {
    kind: 'answer', citations, usedTopics: [...new Set(used.map((h) => h.resource.topicKey))],
    text: (bangla ? 'নথি অনুযায়ী:\n' : '') + body,
  }
}

/** Where a citation points: "p.4" for documents, the JSON path for JSON. */
export const locationLabel = (location: string) => (location.startsWith('$') ? location : `p.${location}`)
