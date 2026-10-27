// Sample resources for the unit tests of the access rules (core/access.ts).
import type { Resource } from '../core/types'

const daysAgo = (n: number) => new Date(Date.now() - n * 24 * 3600 * 1000).toISOString()

const sample = (r: Omit<Resource, 'status' | 'version' | 'uploadedBy' | 'chunks'> & { chunks?: number }): Resource => ({
  status: 'ready', version: 1, uploadedBy: 'Sample', chunks: r.chunks ?? r.passages.length, ...r,
})

export const SAMPLE_RESOURCES: Resource[] = [
  sample({
    id: 'sample-leave', name: 'Leave Policy 2026.pdf', kind: 'pdf', sizeBytes: 412_000, topicKey: 'kb.company_policy',
    audience: [], units: 9, uploadedAt: daysAgo(3),
    passages: [
      { location: '2', section: 'Casual leave', text: 'Every permanent employee gets 10 days of casual leave in a calendar year. Casual leave cannot be carried forward to the next year. Apply at least one day before, except in an emergency.' },
      { location: '3', section: 'Sick leave', text: 'Every employee gets 14 days of sick leave with full pay in a year. Sick leave of more than 2 days needs a doctor\'s certificate. Unused sick leave is not paid out.' },
      { location: '4', section: 'Annual (earned) leave', text: 'After one year of continuous service an employee earns one day of annual leave for every 18 days worked. Up to 40 days of annual leave can be carried forward.' },
      { location: '5', section: 'Maternity leave', text: 'A female employee gets 16 weeks of maternity leave with full pay: 8 weeks before and 8 weeks after the expected delivery date. She must have worked at least 6 months before the expected delivery date.' },
      { location: '7', section: 'How to apply', text: 'Leave is requested in Olympus HRIS under Leave → New request. The reporting manager approves; HR approves leave longer than 5 days.' },
    ],
  }),
  sample({
    id: 'sample-conduct', name: 'Code of Conduct.docx', kind: 'docx', sizeBytes: 268_000, topicKey: 'kb.company_policy',
    audience: [], units: 6, uploadedAt: daysAgo(20),
    passages: [
      { location: '1', section: 'Office hours', text: 'Office hours are 9:00 am to 6:00 pm, Sunday to Thursday. অফিস সকাল ৯টায় শুরু হয় এবং সন্ধ্যা ৬টায় শেষ হয়। Arriving more than 15 minutes late counts as late.' },
      { location: '3', section: 'Dress code', text: 'Business casual from Sunday to Wednesday; smart casual on Thursday. Factory floor staff must wear the company uniform and ID card at all times.' },
      { location: '5', section: 'Gifts', text: 'Employees must not accept gifts worth more than Tk 2,000 from suppliers or customers. Any gift above this must be reported to HR.' },
    ],
  }),
  sample({
    id: 'sample-labour', name: 'Bangladesh Labour Act summary.pdf', kind: 'pdf', sizeBytes: 690_000, topicKey: 'kb.labour_law',
    audience: [], units: 14, uploadedAt: daysAgo(30),
    passages: [
      { location: '6', section: 'Section 46 · Maternity benefit', text: 'Under section 46 of the Bangladesh Labour Act 2006 a woman worker is entitled to maternity benefit for 8 weeks before and 8 weeks after delivery, if she has worked for the employer for at least 6 months.' },
      { location: '9', section: 'Section 108 · Overtime', text: 'Under section 108 a worker who works more than the normal hours gets overtime at twice the ordinary rate of basic wage and dearness allowance.' },
      { location: '11', section: 'Section 117 · Annual leave', text: 'Under section 117 an adult worker who completed one year of continuous service gets one day of annual leave with wages for every 18 days of work.' },
    ],
  }),
  sample({
    id: 'sample-pay', name: 'Pay & Benefits Policy.pdf', kind: 'pdf', sizeBytes: 350_000, topicKey: 'kb.pay_policy',
    audience: [], units: 8, uploadedAt: daysAgo(10),
    passages: [
      { location: '2', section: 'Festival bonus', text: 'Two festival bonuses are paid every year, each equal to one month\'s basic salary, to employees with at least 6 months of service on the festival date.' },
      { location: '4', section: 'Increment', text: 'The yearly increment is between 5% and 12% of gross salary, decided by the performance rating and approved by the Admin.' },
    ],
  }),
  sample({
    id: 'sample-discipline', name: 'Disciplinary Procedure SOP.docx', kind: 'docx', sizeBytes: 180_000, topicKey: 'kb.confidential',
    audience: [], units: 5, uploadedAt: daysAgo(40),
    passages: [
      { location: '2', section: 'Show-cause notice', text: 'Before any disciplinary action a show-cause notice is issued; the employee has 7 days to reply in writing. An inquiry committee of three members is formed if the reply is not accepted.' },
    ],
  }),
  sample({
    id: 'sample-holidays', name: 'holidays-2026.json', kind: 'json', sizeBytes: 4_200, topicKey: 'kb.circulars',
    audience: [], units: 3, uploadedAt: daysAgo(1),
    passages: [
      { location: '$[0]', section: 'Victory Day', text: 'title: Victory Day\ndate: 2026-12-16\ntype: public holiday\nnote: Office closed. Factory closed.' },
      { location: '$[1]', section: 'Christmas Day', text: 'title: Christmas Day\ndate: 2026-12-25\ntype: public holiday\nnote: Office closed.' },
      { location: '$[2]', section: 'Annual picnic', text: 'title: Annual picnic\ndate: 2027-01-09\ntype: company event\nnote: Buses leave head office at 7:00 am.' },
    ],
  }),
]
