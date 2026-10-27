import { describe, expect, it } from 'vitest'
import { buildTree, defaultExpiry, detectKind, expiryBadge, fiscalYearEnd, renewalExpiry, titleFromFileName, typesForFolder } from '../core/dms'
import type { DocType, Folder } from '../core/types'

const folder = (id: string, parent: string | null, origin: Folder['origin'], documents = 0, sort = 100): Folder => ({
  id, parent_id: parent, name: id, origin, catalog_code: origin === 'custom' ? null : id, profile_code: null, enabled: true,
  sort, created_by_me: false, documents,
})
const type = (id: string, folderId: string, extra: Partial<DocType> = {}): DocType => ({
  id, folder_id: folderId, code: id.toUpperCase(), name: id, origin: 'catalog', field_schema: [], has_expiry: false,
  expiry_default: 'none', review_months: null, default_classification: 'internal', active: true, documents: null, ...extra,
})

describe('fiscal year end (30 June)', () => {
  it('is this year until 30 June, next year after', () => {
    expect(fiscalYearEnd(new Date(2026, 9, 27))).toBe('2027-06-30')
    expect(fiscalYearEnd(new Date(2026, 5, 30))).toBe('2026-06-30')
    expect(fiscalYearEnd(new Date(2026, 0, 5))).toBe('2026-06-30')
  })
  it('prefills only fiscal-year types', () => {
    expect(defaultExpiry({ has_expiry: true, expiry_default: 'fiscal_year_end' }, new Date(2026, 9, 27))).toBe('2027-06-30')
    expect(defaultExpiry({ has_expiry: true, expiry_default: 'none' })).toBe('')
    expect(defaultExpiry(undefined)).toBe('')
  })
  it('a renewal runs to the 30 June after the current expiry', () => {
    const now = new Date(2027, 5, 1)
    expect(renewalExpiry({ expiry_default: 'fiscal_year_end' }, '2027-06-30', now)).toBe('2028-06-30')
    // Renewed late: from today, not from the old date.
    expect(renewalExpiry({ expiry_default: 'fiscal_year_end' }, '2025-06-30', new Date(2026, 9, 27))).toBe('2027-06-30')
    expect(renewalExpiry({ expiry_default: 'none' }, '2027-06-30', now)).toBe('')
  })
})

describe('file type is detected, never asked', () => {
  it('maps extensions to kind and MIME', () => {
    expect(detectKind({ name: 'Trade Licence.PDF', size: 10 })).toEqual({ kind: 'pdf', mime: 'application/pdf' })
    expect(detectKind({ name: 'scan.jpeg', size: 10 })).toEqual({ kind: 'jpg', mime: 'image/jpeg' })
  })
  it('refuses other types, empty and large files', () => {
    expect(detectKind({ name: 'a.exe', size: 10 })).toHaveProperty('problem')
    expect(detectKind({ name: 'a.pdf', size: 0 })).toHaveProperty('problem')
    expect(detectKind({ name: 'a.pdf', size: 26 * 1024 * 1024 })).toHaveProperty('problem')
  })
})

describe('expiry badge', () => {
  it('labels expired, due and active', () => {
    expect(expiryBadge('expired', -3)).toEqual({ label: 'Expired', tone: 'red' })
    expect(expiryBadge('due', 16)).toEqual({ label: '16 days left', tone: 'orange' })
    expect(expiryBadge('due', 0).label).toBe('Expires today')
    expect(expiryBadge('active', 200).tone).toBe('green')
    expect(expiryBadge(null, null).label).toBe('No expiry')
  })
})

describe('folder tree', () => {
  it('nests folders and sums documents of subfolders', () => {
    const tree = buildTree([folder('LIC', null, 'base', 2, 10), folder('team', null, 'custom', 1), folder('prices', 'team', 'custom', 3)])
    expect(tree.map((n) => n.id)).toEqual(['LIC', 'team'])
    expect(tree[1].total).toBe(4)
    expect(tree[1].children[0].depth).toBe(1)
  })
  it('a built-in folder offers its own types, a custom folder every type', () => {
    const folders = [folder('LIC', null, 'base'), folder('team', null, 'custom')]
    const types = [type('trd', 'LIC'), type('doc', 'GEN')]
    expect(typesForFolder(types, folders, 'LIC').map((t) => t.id)).toEqual(['trd'])
    expect(typesForFolder(types, folders, 'team')).toHaveLength(2)
    expect(typesForFolder(types, folders, null)).toHaveLength(2)
  })
})

it('turns a file name into a starting title', () => {
  expect(titleFromFileName('trade_licence  final2.pdf')).toBe('Trade licence final2')
})
