// The safe markdown used by notices and tickets: "## " / "### " headings, "- " lists,
// paragraphs, **bold**, *italic* and [text](https://link). Parsed into blocks and rendered
// as React elements (never as HTML), so typed text cannot inject markup or scripts.

export type Inline =
  | { kind: 'text'; text: string; bold?: boolean; italic?: boolean }
  | { kind: 'link'; text: string; href: string }

export type RichBlock =
  | { kind: 'heading'; level: 2 | 3; parts: Inline[] }
  | { kind: 'list'; items: Inline[][] }
  | { kind: 'paragraph'; parts: Inline[] }

/** Only web and mail links; anything else (javascript:, data:) stays plain text. */
export function safeHref(href: string): string | null {
  const h = href.trim()
  return /^(https?:\/\/|mailto:)[^\s]+$/i.test(h) ? h : null
}

const TOKEN = /(\[[^\]]+\]\([^)\s]+\)|\*\*[^*]+\*\*|\*[^*\s][^*]*\*)/

export function parseInline(text: string): Inline[] {
  const parts: Inline[] = []
  for (const piece of text.split(TOKEN)) {
    if (!piece) continue
    const link = piece.match(/^\[([^\]]+)\]\(([^)\s]+)\)$/)
    if (link) {
      const href = safeHref(link[2])
      parts.push(href ? { kind: 'link', text: link[1], href } : { kind: 'text', text: link[1] })
    } else if (piece.length > 4 && piece.startsWith('**') && piece.endsWith('**')) {
      parts.push({ kind: 'text', text: piece.slice(2, -2), bold: true })
    } else if (piece.length > 2 && piece.startsWith('*') && piece.endsWith('*')) {
      parts.push({ kind: 'text', text: piece.slice(1, -1), italic: true })
    } else {
      parts.push({ kind: 'text', text: piece })
    }
  }
  return parts
}

export function parseRichText(source: string): RichBlock[] {
  const blocks: RichBlock[] = []
  let paragraph: string[] = []
  let list: Inline[][] | null = null
  const flush = () => {
    if (paragraph.length) blocks.push({ kind: 'paragraph', parts: parseInline(paragraph.join(' ')) })
    if (list) blocks.push({ kind: 'list', items: list })
    paragraph = []
    list = null
  }
  for (const raw of source.split(/\r?\n/)) {
    const line = raw.trim()
    const heading = line.match(/^(#{2,3})\s+(.*)$/)
    const item = line.match(/^[-•]\s+(.*)$/)
    if (!line) {
      flush()
    } else if (heading) {
      flush()
      blocks.push({ kind: 'heading', level: heading[1].length === 3 ? 3 : 2, parts: parseInline(heading[2]) })
    } else if (item) {
      if (paragraph.length) flush()
      list = list ?? []
      list.push(parseInline(item[1]))
    } else {
      if (list) flush()
      paragraph.push(line)
    }
  }
  flush()
  return blocks
}

/** Plain text for previews and emails: markup removed, links as "text (url)". */
export function plainText(source: string): string {
  return source
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '$1 ($2)')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*\s][^*]*)\*/g, '$1')
    .replace(/^#{2,3}\s+/gm, '')
    .replace(/\s+/g, ' ')
    .trim()
}

export interface Selection { start: number; end: number }

/**
 * Applies a toolbar action to the text and returns the new text and cursor range.
 * Wraps the selection (bold, italic, link) or prefixes the selected lines (list, heading).
 */
export function applyFormat(text: string, sel: Selection, action: 'bold' | 'italic' | 'list' | 'heading' | 'link', url = 'https://'):
  { text: string; sel: Selection } {
  const before = text.slice(0, sel.start)
  const chosen = text.slice(sel.start, sel.end)
  const after = text.slice(sel.end)
  if (action === 'bold' || action === 'italic') {
    const mark = action === 'bold' ? '**' : '*'
    const inner = chosen || (action === 'bold' ? 'bold text' : 'italic text')
    return { text: before + mark + inner + mark + after, sel: { start: sel.start + mark.length, end: sel.start + mark.length + inner.length } }
  }
  if (action === 'link') {
    const label = chosen || 'link text'
    const out = `[${label}](${url})`
    return { text: before + out + after, sel: { start: sel.start + label.length + 3, end: sel.start + out.length - 1 } }
  }
  const lineStart = before.lastIndexOf('\n') + 1
  const block = text.slice(lineStart, sel.end)
  const prefix = action === 'list' ? '- ' : '## '
  const changed = block.split('\n').map((l) => (l.startsWith(prefix) ? l : prefix + l)).join('\n')
  return { text: text.slice(0, lineStart) + changed + after, sel: { start: lineStart, end: lineStart + changed.length } }
}
