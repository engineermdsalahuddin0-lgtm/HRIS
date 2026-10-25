// Interviews (R5): score categories, recommendations, message templates and the
// suggested questions in the interviewer kit (built from the job profile and the gaps
// the screening found; no AI needed).

export const CATEGORIES = ['job_knowledge', 'communication', 'problem_solving', 'confidence', 'culture_fit'] as const
export type Category = (typeof CATEGORIES)[number]

export const CATEGORY_LABEL: Record<Category, { label: string; hint: string }> = {
  job_knowledge: { label: 'Job knowledge', hint: 'Knows the work of this position' },
  communication: { label: 'Communication', hint: 'Explains clearly, listens' },
  problem_solving: { label: 'Problem solving', hint: 'Thinks through a real situation' },
  confidence: { label: 'Confidence', hint: 'Calm, sure of their answers' },
  culture_fit: { label: 'Team & culture fit', hint: 'Works well with people, values match' },
}

export const SCALE_LABEL: Record<number, string> = { 1: 'Poor', 2: 'Below', 3: 'Meets', 4: 'Good', 5: 'Excellent' }

export type Recommendation = 'strong_yes' | 'yes' | 'no' | 'strong_no'
export const RECOMMENDATION_LABEL: Record<Recommendation, string> = {
  strong_yes: 'Strongly recommend', yes: 'Recommend', no: 'Do not recommend', strong_no: 'Strongly against',
}

export const meanOf = (scores: Partial<Record<Category, number>>) => {
  const values = CATEGORIES.map((c) => scores[c]).filter((v): v is number => v != null)
  return values.length === CATEGORIES.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 100) / 100 : null
}

export type TemplateKey = 'test_invite' | 'interview_invite' | 'rejection' | 'offer'
export const TEMPLATE_LABEL: Record<TemplateKey, string> = {
  test_invite: 'Online test link', interview_invite: 'Interview invitation', rejection: 'Not selected', offer: 'Offer',
}
/** Placeholders each template may use (the database fills them; unknown ones stay as typed). */
export const PLACEHOLDERS: Record<TemplateKey, string[]> = {
  test_invite: ['name', 'company', 'job_title', 'test_link', 'duration', 'valid_until'],
  interview_invite: ['name', 'company', 'job_title', 'interview_time', 'interview_place', 'form_link'],
  rejection: ['name', 'company', 'job_title'],
  offer: ['name', 'company', 'job_title'],
}

/** Same as private.render_template: {key} → value; unknown placeholders stay. */
export function renderTemplate(text: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce((out, [k, v]) => out.split(`{${k}}`).join(String(v)), text)
}

export interface KitFacts {
  job: { title: string; profile: { duties: string; required_skills: string[]; experience_min_years: number } }
  screening: { matched_required: string[] | null; years: number | null } | null
  objective: { sections: Record<string, { percent: number | null }> } | null
}

/** Questions for the panel: every required skill the CV did not show, weak test sections, then standard ones. */
export function suggestedQuestions(k: KitFacts): { category: Category; text: string }[] {
  const out: { category: Category; text: string }[] = []
  const matched = new Set((k.screening?.matched_required ?? []).map((s) => s.toLowerCase()))
  for (const skill of k.job.profile.required_skills) {
    if (!matched.has(skill.toLowerCase())) out.push({ category: 'job_knowledge', text: `The CV does not show ${skill}. Tell us about any work you have done with ${skill}.` })
  }
  for (const skill of k.job.profile.required_skills.filter((s) => matched.has(s.toLowerCase())).slice(0, 2)) {
    out.push({ category: 'job_knowledge', text: `Describe a recent task where you used ${skill}. What was the result?` })
  }
  const duty = k.job.profile.duties.split(/\r?\n/).map((d) => d.replace(/^[-*•\s]+/, '').trim()).find(Boolean)
  if (duty) out.push({ category: 'problem_solving', text: `In this job you will "${duty}". Walk us through how you would do it in your first month.` })
  const weak = Object.entries(k.objective?.sections ?? {}).filter(([, v]) => v.percent != null && v.percent < 50).map(([s]) => s.replace('_', ' '))
  if (weak.length) out.push({ category: 'job_knowledge', text: `The online test was weak in ${weak.join(', ')}. Ask one practical question on it.` })
  if (k.screening?.years != null && k.screening.years < k.job.profile.experience_min_years) {
    out.push({ category: 'confidence', text: `You have less experience than we asked for. Why should we still choose you?` })
  }
  out.push(
    { category: 'communication', text: 'Explain your current (or last) job to someone outside your field in two minutes.' },
    { category: 'problem_solving', text: 'Tell us about a mistake at work and what you did to fix it.' },
    { category: 'culture_fit', text: 'Describe a disagreement with a colleague. How was it solved?' },
    { category: 'confidence', text: 'What is the strongest reason we should hire you for this position?' },
  )
  return out
}
