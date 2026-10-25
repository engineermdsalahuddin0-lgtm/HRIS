// What goes on the job poster (1080 x 1350 px, fits LinkedIn and Facebook feeds)
// and how text wraps. Drawing happens in src/pages/onboarding/JobPoster.tsx;
// this part is pure so it can be tested.
import type { JobPost } from './types'
import { EMPLOYMENT_LABEL, salaryText } from './jobPost'
import { sectionItems } from './markdown'

export const POSTER_SIZE = { width: 1080, height: 1350 } as const

export interface PosterContent {
  orgName: string
  title: string
  department: string
  facts: string[]
  requirements: string[]
  salary: string
  deadline: string
  url: string
}

const longDate = (iso: string) =>
  new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })

export function posterContent(
  post: Pick<JobPost, 'org_name' | 'title' | 'department_name' | 'location' | 'seats' | 'employment_type' | 'deadline'
    | 'description_md' | 'show_salary' | 'salary_min' | 'salary_max'>,
  url: string,
): PosterContent {
  return {
    orgName: post.org_name,
    title: post.title,
    department: `${post.department_name} department`,
    facts: [
      post.seats === 1 ? '1 position' : `${post.seats} positions`,
      EMPLOYMENT_LABEL[post.employment_type],
      ...(post.location ? [post.location] : []),
    ],
    requirements: sectionItems(post.description_md, 'Requirements', 4),
    salary: `Salary: ${salaryText(post)}`,
    deadline: `Apply by ${longDate(post.deadline)}`,
    url,
  }
}

/** Greedy word wrap; `measure` returns the width of a string (canvas measureText in the browser). */
export function wrapText(text: string, maxWidth: number, measure: (s: string) => number, maxLines = Infinity): string[] {
  const lines: string[] = []
  let line = ''
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word
    if (measure(next) <= maxWidth || !line) {
      line = next
    } else {
      lines.push(line)
      line = word
    }
  }
  if (line) lines.push(line)
  if (lines.length <= maxLines) return lines
  const kept = lines.slice(0, maxLines)
  let last = kept[maxLines - 1]
  while (last.length > 1 && measure(`${last}…`) > maxWidth) last = last.slice(0, -1)
  kept[maxLines - 1] = `${last.trimEnd()}…`
  return kept
}
