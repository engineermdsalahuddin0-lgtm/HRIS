// The small Markdown subset job posts use: "## " / "### " headings, "- " lists,
// paragraphs and **bold**. Parsed into blocks and rendered as React elements
// (never as HTML), so text typed by HR or applicants cannot inject markup.

export type InlinePart = { text: string; bold: boolean }
export type Block =
  | { kind: 'heading'; level: 2 | 3; parts: InlinePart[] }
  | { kind: 'list'; items: InlinePart[][] }
  | { kind: 'paragraph'; parts: InlinePart[] }

export function parseInline(text: string): InlinePart[] {
  const parts: InlinePart[] = []
  text.split(/(\*\*[^*]+\*\*)/).forEach((piece) => {
    if (!piece) return
    const bold = piece.length > 4 && piece.startsWith('**') && piece.endsWith('**')
    parts.push({ text: bold ? piece.slice(2, -2) : piece, bold })
  })
  return parts
}

export function parseMarkdown(source: string): Block[] {
  const blocks: Block[] = []
  let paragraph: string[] = []
  let list: InlinePart[][] | null = null
  const flush = () => {
    if (paragraph.length) blocks.push({ kind: 'paragraph', parts: parseInline(paragraph.join(' ')) })
    if (list) blocks.push({ kind: 'list', items: list })
    paragraph = []
    list = null
  }
  for (const raw of source.split(/\r?\n/)) {
    const line = raw.trim()
    const heading = line.match(/^(#{1,3})\s+(.*)$/)
    const item = line.match(/^[-*•]\s+(.*)$/)
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

/** First lines of a section as plain text (used for the poster's requirement bullets). */
export function sectionItems(source: string, heading: string, max = 4): string[] {
  const blocks = parseMarkdown(source)
  const at = blocks.findIndex((b) => b.kind === 'heading' && b.parts.map((p) => p.text).join('').toLowerCase() === heading.toLowerCase())
  if (at < 0) return []
  const next = blocks[at + 1]
  if (!next || next.kind !== 'list') return []
  return next.items.slice(0, max).map((parts) => parts.map((p) => p.text).join(''))
}
