import { describe, expect, it } from 'vitest'
import { NID_PATTERN, documentBody, escapeHtml, printPage } from '@/onboarding-process/core/joining'

const FACTS = {
  company: { name: 'Alpha <Offers>' },
  employee: { card_id: 'EMP26001', full_name: 'Rahim Uddin', designation: 'Senior Executive', department: 'Accounts', office: 'Head Office',
              branch: 'Dhaka', present_address: 'House 5, Mirpur', permanent_address: 'Village Char, Bhola', date_of_birth: '1995-04-12',
              probation_end_date: '2027-05-04', employment_type: 'permanent' },
  offer: { gross: 35000, joining_date: '2026-11-04', probation_months: 6, terms: 'Transport <script>alert(1)</script> included.' },
  nominees: [{ name: 'Rokeya Begum', relation: 'Mother', phone: '+8801911000003' }],
}

describe('joining documents', () => {
  it('escapes every value', () => {
    expect(escapeHtml('<a href="x">&\'')).toBe('&lt;a href=&quot;x&quot;&gt;&amp;&#39;')
    const html = documentBody('appointment_letter', FACTS, '2026-10-25')
    expect(html).not.toContain('<script>')
    expect(html).toContain('Transport &lt;script&gt;')
    expect(html).toContain('Alpha &lt;Offers&gt;')
  })
  it('fills the appointment letter from the offer', () => {
    const html = documentBody('appointment_letter', FACTS, '2026-10-25')
    expect(html).toContain('Tk 35,000')
    expect(html).toContain('4 November 2026')
    expect(html).toContain('Probation: 6 months (until 4 May 2027)')
    expect(html).toContain('EMP26001')
  })
  it('lists the nominees and prints all four on separate pages', () => {
    expect(documentBody('nominee_form', FACTS, '2026-10-25')).toContain('Rokeya Begum')
    const page = printPage(['appointment_letter', 'joining_report', 'nominee_form', 'code_of_conduct'], FACTS, '2026-10-25')
    expect(page.match(/class="page"/g)).toHaveLength(4)
    expect(page.startsWith('<!doctype html>')).toBe(true)
  })
  it('checks NID length like the database', () => {
    expect(['1234567890', '1234567890123', '12345678901234567'].every((n) => NID_PATTERN.test(n))).toBe(true)
    expect(NID_PATTERN.test('12345')).toBe(false)
  })
})
