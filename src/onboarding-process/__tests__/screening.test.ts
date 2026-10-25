import { describe, expect, it } from 'vitest'
import { atsFigures } from '@/onboarding-process/core/ats'
import { cleanQuestion, parseQuestionRows, questionError, totalMarks } from '@/onboarding-process/core/questions'

describe('ATS score: the 5 cases of recruit_r3_screening_test.sql', () => {
  it('1 everything matched with relevance -> 97.0 pass', () => {
    const f = atsFigures({ req_total: 3, req_matched: 3, nice_total: 1, nice_matched: 1, min_years: 2, years: 4,
      required_level: 'bachelor', applicant_level: 'masters', subjects_required: 2, subject_matched: true, relevance: 12 })
    expect([f.score, f.gate, f.max]).toEqual([97, 'pass', 100])
  })
  it('2 basic mode (no relevance) -> 66.67 / 85 = 78.4', () => {
    const f = atsFigures({ req_total: 3, req_matched: 2, nice_total: 1, nice_matched: 0, min_years: 2, years: 3,
      required_level: 'bachelor', applicant_level: 'bachelor', subjects_required: 2, subject_matched: false, relevance: null })
    expect([f.skills, f.education, f.max, f.score, f.gate]).toEqual([26.67, 15, 85, 78.4, 'pass'])
  })
  it('3 below the minimum -> 30.8 fail with both reasons', () => {
    const f = atsFigures({ req_total: 3, req_matched: 1, min_years: 2, years: 1, required_level: 'bachelor',
      applicant_level: 'hsc', relevance: 5 })
    expect([f.experience, f.score, f.gate]).toEqual([12.5, 30.8, 'fail'])
    expect(f.reasons).toEqual(['experience_below_minimum', 'education_below_required'])
  })
  it('4 nothing known -> 47.1 review', () => {
    const f = atsFigures({ req_total: 0, req_matched: 0, min_years: 2, years: null, required_level: 'bachelor',
      applicant_level: null, relevance: null })
    expect([f.score, f.gate]).toEqual([47.1, 'review'])
    expect(f.reasons).toEqual(['experience_unknown', 'education_unknown'])
  })
  it('5 no minimums -> 52.9 pass', () => {
    const f = atsFigures({ req_total: 2, req_matched: 0, min_years: 0, years: null, required_level: 'any',
      applicant_level: null, relevance: null })
    expect([f.score, f.gate]).toEqual([52.9, 'pass'])
  })
  it('the Alpha applicants of the SQL test', () => {
    const base = { req_total: 3, nice_total: 1, nice_matched: 0, min_years: 2, required_level: 'bachelor' as const, subjects_required: 2 }
    expect(atsFigures({ ...base, req_matched: 2, years: 7, applicant_level: 'bachelor', subject_matched: true, relevance: null }).score).toBe(84.3)
    expect(atsFigures({ ...base, req_matched: 1, years: 1, applicant_level: 'hsc', relevance: 4 }).score).toBe(29.8)
    expect(atsFigures({ ...base, req_matched: 2, years: 3, applicant_level: 'bachelor', subject_matched: true, relevance: 10 }).score).toBe(81.7)
  })
})

describe('question papers', () => {
  it('checks questions like the database', () => {
    const ok = { section: 'aptitude' as const, stem: '12 is what percent of 48?', options: ['20%', '25%', ''], correct_index: 1, model_answer: null, marks: 2 }
    expect(questionError('objective', ok, 0)).toBeNull()
    expect(questionError('objective', { ...ok, correct_index: 2 }, 0)).toMatch(/correct/)
    expect(questionError('objective', { ...ok, options: ['only one'] }, 0)).toMatch(/2 to 6/)
    expect(questionError('written', { ...ok, options: null, marks: 0 }, 4)).toBe('Question 5: marks must be between 0.25 and 100')
  })
  it('drops empty options and keeps the right answer', () => {
    const q = cleanQuestion('objective', { section: 'general', stem: ' Q ', options: ['a', '', 'c'], correct_index: 2, model_answer: 'x', marks: 1 })
    expect(q).toEqual({ section: 'general', stem: 'Q', options: ['a', 'c'], correct_index: 1, model_answer: null, marks: 1 })
  })
  it('reads objective rows pasted from Excel', () => {
    const { questions, errors } = parseQuestionRows('objective',
      'Question\tA\tB\tC\tD\tCorrect\tMarks\tSection\nWhich is a debit?\tRent\tCapital\tSales\tLoan\tA\t1\tJob knowledge\n2+2?\t3\t4\tB\t2\taptitude\nbad row')
    expect(errors).toEqual(['Line 4: need question, options, correct letter (A-F), marks'])
    expect(questions).toEqual([
      { section: 'job_knowledge', stem: 'Which is a debit?', options: ['Rent', 'Capital', 'Sales', 'Loan'], correct_index: 0, model_answer: null, marks: 1 },
      { section: 'aptitude', stem: '2+2?', options: ['3', '4'], correct_index: 1, model_answer: null, marks: 2 },
    ])
    expect(totalMarks(questions)).toBe(3)
  })
  it('reads written rows', () => {
    const { questions, errors } = parseQuestionRows('written', 'Explain a bank reconciliation.\t10\tMatch cash book and statement\nNo marks\t')
    expect(questions).toHaveLength(1)
    expect(questions[0]).toMatchObject({ marks: 10, model_answer: 'Match cash book and statement', options: null })
    expect(errors).toEqual(['Line 2: need question and marks'])
  })
})
