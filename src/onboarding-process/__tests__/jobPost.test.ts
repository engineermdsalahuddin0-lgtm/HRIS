import { describe, expect, it } from 'vitest'
import {
  addDays, cvError, daysLeft, deadlineText, parseApplicantRows, salaryError, salaryText, slugify, weightsError,
} from '@/onboarding-process/core/jobPost'
import { parseMarkdown, sectionItems } from '@/onboarding-process/core/markdown'
import { posterContent, wrapText } from '@/onboarding-process/core/poster'
import { DEMO_JOB_POST } from '@/onboarding-process/demo/jobPostDemo'

describe('salary toggle', () => {
  it('shows "Negotiable" when off, a range when on', () => {
    expect(salaryText({ show_salary: false, salary_min: 25000, salary_max: 32000 })).toBe('Negotiable')
    expect(salaryText({ show_salary: true, salary_min: 25000, salary_max: 32000 })).toBe('Tk 25,000 – 32,000 / month')
    expect(salaryText({ show_salary: true, salary_min: 125000, salary_max: 125000 })).toBe('Tk 1,25,000 / month')
  })
  it('needs min and max with min <= max (same rule as update_job_post)', () => {
    expect(salaryError({ show_salary: false, salary_min: null, salary_max: null })).toBeNull()
    expect(salaryError({ show_salary: true, salary_min: null, salary_max: null })).toMatch(/both/)
    expect(salaryError({ show_salary: true, salary_min: 30000, salary_max: 25000 })).toMatch(/below/)
    expect(salaryError({ show_salary: true, salary_min: 25000, salary_max: 25000 })).toBeNull()
  })
})

describe('deadline', () => {
  it('counts whole days', () => {
    expect(addDays('2026-10-25', 14)).toBe('2026-11-08')
    expect(daysLeft('2026-11-08', '2026-10-25')).toBe(14)
    expect(deadlineText('2026-10-25', '2026-10-25')).toBe('Closes today')
    expect(deadlineText('2026-10-26', '2026-10-25')).toBe('Closes tomorrow')
    expect(deadlineText('2026-10-24', '2026-10-25')).toBe('Deadline passed')
  })
})

describe('weights', () => {
  it('must be whole numbers adding up to 100', () => {
    expect(weightsError({ ats: 10, objective: 25, written: 20, interview: 45 })).toBeNull()
    expect(weightsError({ ats: 10, objective: 25, written: 10, interview: 45 })).toMatch(/90/)
    expect(weightsError({ ats: 10.5, objective: 25, written: 19.5, interview: 45 })).toMatch(/whole/)
  })
})

describe('CV rules (same as submit_job_application)', () => {
  const pdf = 'application/pdf'
  it('accepts PDF and DOCX up to 5 MB', () => {
    expect(cvError({ name: 'Rahim CV.PDF', size: 250_000, type: pdf })).toBeNull()
    expect(cvError({ name: 'cv.docx', size: 1000, type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })).toBeNull()
  })
  it('refuses other types, a name that does not match the type, empty and large files', () => {
    expect(cvError({ name: 'cv.exe', size: 1000, type: 'application/octet-stream' })).toMatch(/PDF or DOCX/)
    expect(cvError({ name: 'cv.pdf', size: 1000, type: 'image/png' })).toMatch(/PDF or DOCX/)
    expect(cvError({ name: 'cv.doc', size: 1000, type: 'application/msword' })).toMatch(/PDF or DOCX/)
    expect(cvError({ name: 'cv.pdf', size: 0, type: pdf })).toMatch(/empty/)
    expect(cvError({ name: 'cv.pdf', size: 6_000_000, type: pdf })).toMatch(/5 MB/)
  })
})

describe('slugify', () => {
  it('keeps a-z, 0-9 and single dashes', () => {
    expect(slugify('Senior Executive (Accounts)')).toBe('senior-executive-accounts')
    expect(slugify('  --QA / QC Officer--  ')).toBe('qa-qc-officer')
  })
})

describe('parseApplicantRows', () => {
  it('reads name, email and phone in any order; skips a header; reports bad lines', () => {
    const { rows, errors } = parseApplicantRows(
      'Name,Email,Phone\nKarim Ahmed, KARIM@example.com, 01811000002\n01711000003\tsadia@example.com\tSadia Islam\nno email here\n',
    )
    expect(rows).toEqual([
      { full_name: 'Karim Ahmed', email: 'karim@example.com', phone: '01811000002' },
      { full_name: 'Sadia Islam', email: 'sadia@example.com', phone: '01711000003' },
    ])
    expect(errors).toEqual(['Line 4: no email address'])
  })
})

describe('markdown subset', () => {
  it('parses headings, lists, paragraphs and bold', () => {
    expect(parseMarkdown('## About\n**Acme** is hiring.\n\n- one\n- **two**\nafter')).toEqual([
      { kind: 'heading', level: 2, parts: [{ text: 'About', bold: false }] },
      { kind: 'paragraph', parts: [{ text: 'Acme', bold: true }, { text: ' is hiring.', bold: false }] },
      { kind: 'list', items: [[{ text: 'one', bold: false }], [{ text: 'two', bold: true }]] },
      { kind: 'paragraph', parts: [{ text: 'after', bold: false }] },
    ])
  })
  it('treats markup as text', () => {
    expect(parseMarkdown('<img src=x onerror=alert(1)>')).toEqual([
      { kind: 'paragraph', parts: [{ text: '<img src=x onerror=alert(1)>', bold: false }] },
    ])
  })
  it('reads the items of a section', () => {
    expect(sectionItems(DEMO_JOB_POST.description_md, 'Requirements')).toEqual([
      'At least 2 years of experience',
      "Education: Bachelor's degree (Pass or Honours) in Accounting / Finance",
      'Skills: Tally, Excel, VAT',
    ])
  })
})

describe('poster', () => {
  it('collects the facts, requirements, salary and deadline', () => {
    const c = posterContent(DEMO_JOB_POST, 'https://example.com/careers/000000/senior-executive-accounts')
    expect(c.facts).toEqual(['1 position', 'Permanent', 'Head Office, Dhaka'])
    expect(c.requirements).toHaveLength(3)
    expect(c.salary).toBe('Salary: Tk 25,000 – 32,000 / month')
    expect(c.deadline).toBe('Apply by 8 November 2026')
    expect(posterContent({ ...DEMO_JOB_POST, show_salary: false }, '').salary).toBe('Salary: Negotiable')
  })
  it('wraps words and cuts with an ellipsis', () => {
    const measure = (s: string) => s.length
    expect(wrapText('one two three four', 9, measure)).toEqual(['one two', 'three', 'four'])
    expect(wrapText('one two three four', 9, measure, 2)).toEqual(['one two', 'three…'])
  })
})
