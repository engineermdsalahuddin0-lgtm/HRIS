// Resource checks before upload, and the preview's stand-in for backend processing:
// JSON is really parsed in the browser (one passage per record); PDF / DOCX get page and
// chunk estimates until the backend extracts their text.
import { MAX_RESOURCE_MB, RESOURCE_TYPES } from './catalog'
import type { Passage, Resource, ResourceKind } from './types'

export function kindOf(fileName: string): ResourceKind | null {
  const ext = fileName.toLowerCase().split('.').pop() ?? ''
  for (const [kind, t] of Object.entries(RESOURCE_TYPES)) {
    if ((t.extensions as readonly string[]).includes(ext)) return kind as ResourceKind
  }
  return null
}

/** Plain-language reason a file is refused, or null when it may be uploaded. */
export function uploadProblem(file: { name: string; size: number }, existing: Resource[]): string | null {
  const kind = kindOf(file.name)
  if (!kind) {
    return file.name.toLowerCase().endsWith('.doc')
      ? 'Old .doc files are not supported. Open it in Word and save as .docx or PDF.'
      : 'Only PDF, DOCX and JSON files can be uploaded.'
  }
  if (file.size === 0) return 'The file is empty.'
  if (file.size > MAX_RESOURCE_MB * 1024 * 1024) return `The file is larger than ${MAX_RESOURCE_MB} MB.`
  if (existing.some((r) => r.status !== 'archived' && r.name.toLowerCase() === file.name.toLowerCase())) {
    return 'A resource with this name already exists. Upload it as a new version from its row instead.'
  }
  return null
}

/** Rough tokens: about 4 characters per token for English, fewer for Bangla; enough for estimates. */
export const tokensOf = (text: string) => Math.max(1, Math.ceil(text.length / 4))

/** Chunks a text of this many tokens produces with the given size and overlap (percent). */
export function chunkCount(tokens: number, chunkSize: number, overlapPercent: number): number {
  if (tokens <= chunkSize) return 1
  const step = Math.max(1, Math.round(chunkSize * (1 - overlapPercent / 100)))
  return 1 + Math.ceil((tokens - chunkSize) / step)
}

/** PDF / DOCX estimate: about 45 KB and 450 tokens per page. */
export function estimateDocument(sizeBytes: number, chunkSize: number, overlapPercent: number) {
  const pages = Math.max(1, Math.round(sizeBytes / (45 * 1024)))
  return { units: pages, chunks: chunkCount(pages * 450, chunkSize, overlapPercent) }
}

const isPlain = (v: unknown) => v === null || ['string', 'number', 'boolean'].includes(typeof v)

/** Flattens one record into "key.path: value" lines, the form the backend embeds. */
export function flattenRecord(value: unknown, path = ''): string[] {
  if (isPlain(value)) return [`${path || 'value'}: ${String(value)}`]
  if (Array.isArray(value)) {
    if (value.every(isPlain)) return [`${path || 'value'}: ${value.join(', ')}`]
    return value.flatMap((v, i) => flattenRecord(v, `${path}[${i}]`))
  }
  return Object.entries(value as Record<string, unknown>).flatMap(([k, v]) => flattenRecord(v, path ? `${path}.${k}` : k))
}

const titleOf = (record: unknown, fallback: string) => {
  if (record && typeof record === 'object' && !Array.isArray(record)) {
    const r = record as Record<string, unknown>
    for (const k of ['title', 'name', 'heading', 'subject']) if (typeof r[k] === 'string') return r[k] as string
  }
  return fallback
}

/** One passage per record: array items, or the top-level keys of an object. */
export function parseJsonResource(text: string): { passages: Passage[] } | { error: string } {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    return { error: 'This is not valid JSON. Check the file in a JSON validator.' }
  }
  const records: [string, unknown][] = Array.isArray(data)
    ? data.map((v, i) => [`$[${i}]`, v])
    : data && typeof data === 'object'
      ? Object.entries(data as Record<string, unknown>).map(([k, v]) => [`$.${k}`, v])
      : [['$', data]]
  const passages = records
    .map(([path, value]) => ({ location: path, section: titleOf(value, path), text: flattenRecord(value).join('\n') }))
    .filter((p) => p.text.trim().length > 0)
  if (passages.length === 0) return { error: 'The JSON file has no records.' }
  return { passages }
}

/** Words that suggest personal data; the upload asks for confirmation before going on. */
const SENSITIVE_KEYS = /\b(nid|national_id|salary|gross|basic|bank|account_no|account_number|bkash|nagad|phone|mobile|dob|date_of_birth)\b/i
export function looksPersonal(passages: Passage[]): boolean {
  return passages.length > 3 && passages.filter((p) => SENSITIVE_KEYS.test(p.text)).length / passages.length > 0.5
}

export const formatSize = (bytes: number) =>
  bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`
