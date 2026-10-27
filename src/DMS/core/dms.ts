// Pure DMS helpers: file type detection, the 30 June default, expiry labels, the folder tree.
import type { Classification, DocType, ExpiryStatus, FileKind, Folder } from './types'

export const MAX_FILE_MB = 25

export const MIME: Record<FileKind, string> = {
  pdf: 'application/pdf',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  json: 'application/json',
  jpg: 'image/jpeg',
  png: 'image/png',
}

const EXT: Record<string, FileKind> = { pdf: 'pdf', docx: 'docx', xlsx: 'xlsx', json: 'json', jpg: 'jpg', jpeg: 'jpg', png: 'png' }

/** The system detects the type from the file; the user is never asked. */
export function detectKind(file: { name: string; size: number }): { kind: FileKind; mime: string } | { problem: string } {
  const ext = file.name.toLowerCase().split('.').pop() ?? ''
  const kind = EXT[ext]
  if (!kind) return { problem: 'Use a PDF, Word (DOCX), Excel (XLSX), JSON, JPG or PNG file' }
  if (file.size === 0) return { problem: 'The file is empty' }
  if (file.size > MAX_FILE_MB * 1024 * 1024) return { problem: `The file must be under ${MAX_FILE_MB} MB` }
  return { kind, mime: MIME[kind] }
}

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

/** 30 June on or after the date: the end of the Bangladesh fiscal year (same rule as the database). */
export function fiscalYearEnd(from: Date = new Date()): string {
  const y = from.getMonth() > 5 ? from.getFullYear() + 1 : from.getFullYear()
  return `${y}-06-30`
}

/** Expiry prefilled on upload: 30 June for fiscal-year types, empty otherwise. */
export function defaultExpiry(type: Pick<DocType, 'has_expiry' | 'expiry_default'> | undefined, from: Date = new Date()): string {
  return type?.has_expiry && type.expiry_default === 'fiscal_year_end' ? fiscalYearEnd(from) : ''
}

/** A renewal of a fiscal-year licence runs to the next 30 June after the current expiry. */
export function renewalExpiry(type: Pick<DocType, 'expiry_default'> | undefined, currentExpiry: string | null, from: Date = new Date()): string {
  if (type?.expiry_default !== 'fiscal_year_end') return ''
  const base = currentExpiry ? new Date(`${currentExpiry}T00:00:00`) : from
  const start = base > from ? base : from
  const next = new Date(start)
  next.setDate(next.getDate() + 1)
  return fiscalYearEnd(next)
}

export const addDays = (days: number, from: Date = new Date()) => {
  const d = new Date(from)
  d.setDate(d.getDate() + days)
  return iso(d)
}

export function expiryBadge(status: ExpiryStatus | null, daysLeft: number | null): { label: string; tone: 'red' | 'orange' | 'green' | 'slate' } {
  if (!status) return { label: 'No expiry', tone: 'slate' }
  if (status === 'expired') return { label: 'Expired', tone: 'red' }
  if (status === 'due') return { label: daysLeft === 0 ? 'Expires today' : `${daysLeft} day${daysLeft === 1 ? '' : 's'} left`, tone: 'orange' }
  return { label: 'Active', tone: 'green' }
}

export const CLASSIFICATION: Record<Classification, { label: string; hint: string }> = {
  public: { label: 'Public', hint: 'Anyone in the company; may be shared outside' },
  internal: { label: 'Internal', hint: 'Everyone in the company (or the departments you choose)' },
  confidential: { label: 'Confidential', hint: 'Managers and HR of the department only' },
  restricted: { label: 'Restricted', hint: 'Only the roles you choose' },
}

/** Assistant topics a document type can feed (confidential topics never: such documents are not sent). */
export const AI_TOPICS: { key: string; label: string }[] = [
  { key: 'kb.company_policy', label: 'Company policy' },
  { key: 'kb.hr_rules', label: 'HR rules' },
  { key: 'kb.circulars', label: 'Circulars' },
  { key: 'kb.labour_law', label: 'Labour law' },
  { key: 'kb.pay_policy', label: 'Pay policy' },
  { key: 'kb.tax_pf_gratuity', label: 'Tax, PF, gratuity' },
  { key: 'kb.manager_guide', label: 'Manager guide' },
]

export interface FolderNode extends Folder {
  children: FolderNode[]
  /** Documents in this folder and every folder below it. */
  total: number
  depth: number
}

export function buildTree(folders: Folder[]): FolderNode[] {
  const nodes = new Map<string, FolderNode>(folders.map((f) => [f.id, { ...f, children: [], total: f.documents, depth: 0 }]))
  const roots: FolderNode[] = []
  for (const n of nodes.values()) {
    const parent = n.parent_id ? nodes.get(n.parent_id) : undefined
    if (parent) parent.children.push(n)
    else roots.push(n)
  }
  const order = (a: FolderNode, b: FolderNode) => a.sort - b.sort || a.name.localeCompare(b.name)
  const walk = (list: FolderNode[], depth: number): number => {
    list.sort(order)
    let sum = 0
    for (const n of list) {
      n.depth = depth
      n.total = n.documents + walk(n.children, depth + 1)
      sum += n.total
    }
    return sum
  }
  walk(roots, 0)
  return roots
}

/** Types offered when uploading into a folder: a built-in folder offers its own types;
 *  a custom folder, or no folder, offers every type. */
export function typesForFolder(types: DocType[], folders: Folder[], folderId: string | null): DocType[] {
  const folder = folders.find((f) => f.id === folderId)
  if (!folder || folder.origin === 'custom') return types
  const own = types.filter((t) => t.folder_id === folder.id)
  return own.length > 0 ? own : types
}

/** "trade licence final2.pdf" → "Trade licence final2": a starting title the user can change. */
export function titleFromFileName(name: string): string {
  const base = name.replace(/\.[^.]+$/, '').replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim()
  return base ? base.charAt(0).toUpperCase() + base.slice(1) : ''
}

export const formatSize = (bytes: number) =>
  bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`
