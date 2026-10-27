import { describe, expect, it } from 'vitest'
import { applyFormat, parseInline, parseRichText, plainText, safeHref } from '../markup'
import { attachmentProblem, safeFileName } from '../api'

describe('safe markdown', () => {
  it('parses bold, italic and links', () => {
    expect(parseInline('**Casual** leave is *ten* days, see [policy](https://hr.example.com/p)')).toEqual([
      { kind: 'text', text: 'Casual', bold: true },
      { kind: 'text', text: ' leave is ' },
      { kind: 'text', text: 'ten', italic: true },
      { kind: 'text', text: ' days, see ' },
      { kind: 'link', text: 'policy', href: 'https://hr.example.com/p' },
    ])
  })
  it('never makes script links', () => {
    expect(safeHref('javascript:alert(1)')).toBeNull()
    expect(parseInline('[click](javascript:alert(1))')).toEqual([{ kind: 'text', text: 'click' }, { kind: 'text', text: ')' }])
    expect(parseInline('[x](data:text/html,hi)')).toEqual([{ kind: 'text', text: 'x' }])
    expect(parseRichText('<script>alert(1)</script>')).toEqual([{ kind: 'paragraph', parts: [{ kind: 'text', text: '<script>alert(1)</script>' }] }])
  })
  it('builds headings, lists and paragraphs', () => {
    const blocks = parseRichText('## Rules\n- one\n- **two**\nafter\n\nnext para')
    expect(blocks.map((b) => b.kind)).toEqual(['heading', 'list', 'paragraph', 'paragraph'])
  })
  it('plain text drops the markup', () => {
    expect(plainText('## Title\n**Bold** and *it* [link](https://a.b)')).toBe('Title Bold and it link (https://a.b)')
  })
})

describe('toolbar', () => {
  it('wraps the selection in bold and selects the inner text', () => {
    const out = applyFormat('make this bold', { start: 5, end: 9 }, 'bold')
    expect(out.text).toBe('make **this** bold')
    expect(out.text.slice(out.sel.start, out.sel.end)).toBe('this')
  })
  it('turns the selected lines into a list once', () => {
    expect(applyFormat('a\nb', { start: 0, end: 3 }, 'list').text).toBe('- a\n- b')
    expect(applyFormat('- a', { start: 0, end: 3 }, 'list').text).toBe('- a')
  })
  it('inserts a link', () => {
    expect(applyFormat('see here', { start: 4, end: 8 }, 'link', 'https://x.y').text).toBe('see [here](https://x.y)')
  })
})

describe('files', () => {
  it('makes safe storage names', () => {
    expect(safeFileName('ছুটির নীতি (2027).PDF')).toBe('2027.pdf')
    expect(safeFileName('Leave Policy v2.pdf')).toBe('Leave-Policy-v2.pdf')
    expect(safeFileName('noext')).toBe('noext')
  })
  it('checks type and size', () => {
    expect(attachmentProblem(new File(['x'], 'a.exe', { type: 'application/x-msdownload' }), 10)).toMatch(/PDF/)
    expect(attachmentProblem(new File(['x'], 'a.pdf', { type: 'application/pdf' }), 10)).toBeNull()
  })
})
