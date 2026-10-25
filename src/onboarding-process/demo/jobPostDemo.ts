// A sample job post for the dev preview (/preview/job-post): demo case 5
// (Accounts, backfill 1 Senior Executive). The text is what
// private.job_post_markdown writes for this profile (see recruit_r2_job_posts_test.sql).
import type { JobPost } from '../core/types'

export const DEMO_JOB_POST: JobPost = {
  id: 'demo', vacancy_id: 'demo', department_id: 'demo', designation_id: 'demo',
  profile: {
    designation_id: 'demo', department_id: 'demo', experience_min_years: 2, experience_max_years: null,
    education_level: 'bachelor', education_subjects: ['Accounting', 'Finance'],
    required_skills: ['Tally', 'Excel', 'VAT'], nice_skills: ['IFRS'],
    duties: 'Prepare and check vouchers\nMonthly bank reconciliation\nVAT and AIT returns',
    employment_type: 'permanent', version: 1,
  },
  profile_version: 1, profile_current_version: 1,
  title: 'Senior Executive',
  description_md: [
    '## About the role',
    '**Demo Garments Ltd.** is hiring Senior Executive (1 position) in the Accounts department.',
    '',
    '## Responsibilities',
    '- Prepare and check vouchers',
    '- Monthly bank reconciliation',
    '- VAT and AIT returns',
    '',
    '## Requirements',
    '- At least 2 years of experience',
    "- Education: Bachelor's degree (Pass or Honours) in Accounting / Finance",
    '- Skills: Tally, Excel, VAT',
    '',
    '## Nice to have',
    '- IFRS',
    '',
    '## Employment',
    '- Type: Permanent',
    '',
  ].join('\n'),
  location: 'Head Office, Dhaka', seats: 1, employment_type: 'permanent',
  show_salary: true, salary_min: 25000, salary_max: 32000,
  deadline: '2026-11-08', public_slug: 'senior-executive-accounts', poster: { theme: 'orange' },
  weights: { ats: 10, objective: 25, written: 20, interview: 45 }, has_written_test: true,
  status: 'draft', published_at: null, closed_at: null, close_note: null,
  department_name: 'Accounts', designation_name: 'Senior Executive', grade_code: 'MS0',
  org_code: '000000', org_name: 'Demo Garments Ltd.', vacancy_status: 'approved', vacancy_reason: 'replacement',
  today: '2026-10-25',
}
