import { describe, expect, it } from 'vitest'
import { chunkCount, estimateDocument, flattenRecord, kindOf, looksPersonal, parseJsonResource, uploadProblem } from '../core/resources'
import { SAMPLE_RESOURCES } from '../data/sampleData'

describe('upload checks', () => {
  it('accepts PDF, DOCX and JSON only', () => {
    expect(kindOf('Leave Policy.PDF')).toBe('pdf')
    expect(kindOf('rules.docx')).toBe('docx')
    expect(kindOf('holidays.json')).toBe('json')
    expect(kindOf('sheet.xlsx')).toBeNull()
  })
  it('explains why a file is refused', () => {
    expect(uploadProblem({ name: 'old.doc', size: 10 }, [])).toMatch(/save as \.docx/)
    expect(uploadProblem({ name: 'big.pdf', size: 21 * 1024 * 1024 }, [])).toMatch(/20 MB/)
    expect(uploadProblem({ name: 'empty.pdf', size: 0 }, [])).toMatch(/empty/)
    expect(uploadProblem({ name: 'leave policy 2026.pdf', size: 10 }, SAMPLE_RESOURCES)).toMatch(/already exists/)
    expect(uploadProblem({ name: 'new.pdf', size: 10 }, SAMPLE_RESOURCES)).toBeNull()
  })
})

describe('chunk estimates', () => {
  it('400-token chunks with 15% overlap step 340 tokens', () => {
    // 4500 tokens: first chunk 400, then ceil((4500 - 400) / 340) = 13 more → 14
    expect(chunkCount(4500, 400, 15)).toBe(14)
    expect(chunkCount(300, 400, 15)).toBe(1)
  })
  it('PDF pages from size (45 KB per page)', () => {
    expect(estimateDocument(450 * 1024, 400, 15).units).toBe(10)
  })
})

describe('JSON resources', () => {
  it('one passage per array item, titled by its name/title field', () => {
    const r = parseJsonResource(JSON.stringify([{ title: 'Victory Day', date: '2026-12-16' }, { name: 'Picnic', tags: ['a', 'b'] }]))
    expect('passages' in r && r.passages.map((p) => [p.location, p.section])).toEqual([['$[0]', 'Victory Day'], ['$[1]', 'Picnic']])
    expect('passages' in r && r.passages[1].text).toBe('name: Picnic\ntags: a, b')
  })
  it('object top-level keys become records; nested paths are flattened', () => {
    expect(flattenRecord({ leave: { casual: 10, sick: { days: 14 } } })).toEqual(['leave.casual: 10', 'leave.sick.days: 14'])
    const r = parseJsonResource('{"dress":{"rule":"uniform"},"hours":"9-6"}')
    expect('passages' in r && r.passages.map((p) => p.location)).toEqual(['$.dress', '$.hours'])
  })
  it('broken or empty JSON fails with a plain message', () => {
    expect(parseJsonResource('{oops')).toEqual({ error: expect.stringMatching(/not valid JSON/) })
    expect(parseJsonResource('[]')).toEqual({ error: 'The JSON file has no records.' })
  })
  it('flags files that look like employee data', () => {
    const rows = Array.from({ length: 5 }, (_, i) => ({ name: `E${i}`, salary: 30000, nid: '123' }))
    const r = parseJsonResource(JSON.stringify(rows))
    expect('passages' in r && looksPersonal(r.passages)).toBe(true)
    expect(looksPersonal(SAMPLE_RESOURCES[0].passages)).toBe(false)
  })
})
