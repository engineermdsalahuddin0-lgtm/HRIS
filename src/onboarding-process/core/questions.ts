// Question papers (R3): sections, checks (same rules as private.clean_question) and
// rows pasted from Excel. Objective: question | option A | B | C | D | correct (A-F) | marks [| section].
// Written: question | marks | model answer [| section].
import type { PaperKind, Question, QuestionSection } from './types'

export const SECTION_LABEL: Record<QuestionSection, string> = {
  aptitude: 'Aptitude / reasoning', job_knowledge: 'Job knowledge', language: 'Language (English / Bangla)',
  situational: 'Situational', general: 'General',
}

export const KIND_LABEL: Record<PaperKind, string> = { objective: 'Objective (online)', written: 'Written (on paper)' }

export const blankQuestion = (kind: PaperKind): Question => (kind === 'objective'
  ? { section: 'job_knowledge', stem: '', options: ['', '', '', ''], correct_index: 0, model_answer: null, marks: 1 }
  : { section: 'job_knowledge', stem: '', options: null, correct_index: null, model_answer: '', marks: 10 })

export function questionError(kind: PaperKind, q: Question, index: number): string | null {
  const n = index + 1
  if (q.stem.trim().length < 3) return `Question ${n}: write the question`
  if (!(q.marks >= 0.25 && q.marks <= 100)) return `Question ${n}: marks must be between 0.25 and 100`
  if (kind === 'objective') {
    const options = (q.options ?? []).map((o) => o.trim()).filter(Boolean)
    if (options.length < 2 || options.length > 6) return `Question ${n}: give 2 to 6 options`
    if (q.correct_index == null || q.correct_index < 0 || q.correct_index >= options.length || !(q.options ?? [])[q.correct_index]?.trim()) {
      return `Question ${n}: mark the correct option`
    }
  }
  return null
}

/** Drops empty options and moves the correct index with them, as the database stores it. */
export function cleanQuestion(kind: PaperKind, q: Question): Question {
  if (kind === 'written') return { ...q, stem: q.stem.trim(), options: null, correct_index: null }
  const kept = (q.options ?? []).map((o, i) => ({ o: o.trim(), i })).filter((x) => x.o)
  return {
    ...q, stem: q.stem.trim(), model_answer: null,
    options: kept.map((x) => x.o), correct_index: Math.max(0, kept.findIndex((x) => x.i === q.correct_index)),
  }
}

export const totalMarks = (questions: Question[]) => Math.round(questions.reduce((s, q) => s + (Number(q.marks) || 0), 0) * 100) / 100

const SECTIONS = Object.keys(SECTION_LABEL) as QuestionSection[]
const sectionOf = (text: string | undefined): QuestionSection => {
  const t = (text ?? '').toLowerCase().replace(/[^a-z]/g, '')
  return SECTIONS.find((s) => s.replace('_', '') === t || SECTION_LABEL[s].toLowerCase().startsWith(t) && t.length >= 3) ?? 'general'
}

export function parseQuestionRows(kind: PaperKind, text: string): { questions: Question[]; errors: string[] } {
  const questions: Question[] = []
  const errors: string[] = []
  text.split(/\r?\n/).forEach((line, index) => {
    const cells = line.split('\t').map((c) => c.trim())
    if (cells.every((c) => !c)) return
    if (index === 0 && /question/i.test(cells[0] ?? '')) return
    if (kind === 'objective') {
      const [stem, ...rest] = cells
      // The correct-answer cell is the first single letter A-F after the options.
      const letterAt = rest.findIndex((c, i) => i >= 2 && /^[A-Fa-f]$/.test(c))
      if (!stem || letterAt < 0) {
        errors.push(`Line ${index + 1}: need question, options, correct letter (A-F), marks`)
        return
      }
      const options = rest.slice(0, letterAt).filter(Boolean)
      const marks = Number(rest[letterAt + 1] || 1)
      questions.push({
        section: sectionOf(rest[letterAt + 2]), stem, options,
        correct_index: rest[letterAt].toUpperCase().charCodeAt(0) - 65, model_answer: null, marks,
      })
    } else {
      const [stem, marks, answer, section] = cells
      if (!stem || !(Number(marks) > 0)) {
        errors.push(`Line ${index + 1}: need question and marks`)
        return
      }
      questions.push({ section: sectionOf(section), stem, options: null, correct_index: null, model_answer: answer || '', marks: Number(marks) })
    }
  })
  questions.forEach((q, i) => {
    const problem = questionError(kind, q, i)
    if (problem) errors.push(problem)
  })
  return { questions, errors }
}
