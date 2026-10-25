// Shared types of the onboarding-process module (R1: workforce planning; R2: job posts, applicants).
// Field names match the JSON the database returns (snake_case).

export type WorkloadMethod = 'hours' | 'output_smv' | 'volume_std' | 'ratio'
export type Band = 'critical' | 'overload' | 'watch' | 'balanced' | 'underloaded'
export type WorkloadAction = 'hire' | 'watch' | 'hold' | 'underloaded' | 'balanced'
export type BudgetStatus = 'ok' | 'blocked' | 'unknown'

export interface Bands {
  underload: number; watch: number; overload: number; critical: number
  sustain_months: number; attrition_flag_percent: number
}

/** Inputs of the pure calculation (private.workload_figures). */
export interface WorkloadInput {
  demand_hours: number
  capacity_per_fte: number
  active: number
  sanctioned: number
  separations?: number
  avg_headcount?: number | null
  prior_overload_months?: number
  cost_per_seat?: number | null
  budget_remaining?: number | null
  bands?: Bands
}

/** Output of the calculation; snapshots add the facts they were built from. */
export interface WorkloadFigures {
  demand_hours: number; capacity_per_fte: number; capacity_hours: number
  active: number; sanctioned: number; vacancy: number; vacancy_rate: number | null
  required_fte: number; gap: number; index: number | null; band: Band
  overload_months: number; overload_rule: boolean
  backfill_seats: number; new_positions: number; hold_seats: number; seats_total: number
  budget_status: BudgetStatus; budget_ok_seats: number; budget_ok_backfill: number; budget_ok_new: number
  budget_blocked_seats: number
  /** Hidden from roles without compensation.view. */
  cost_per_seat?: number | null
  budget_remaining?: number | null
  separations: number; avg_headcount: number | null; attrition_percent: number | null; attrition_flag: boolean
  action: WorkloadAction
  bands: Bands
}

export interface SnapshotFigures extends WorkloadFigures {
  period_month: string; method: WorkloadMethod; availability: number
  capacity_hours_setting: number; availability_source: 'attendance' | 'fixed'
  scheduled_workdays: number | null; lost_workdays: number | null
  regular_hours: number; overtime_hours: number
  org_headcount: number; per_employees: number | null
  monthly_budget?: number | null; department_payroll?: number | null
  built_at?: string
}

export interface WorkloadInputRow { metric_key: string; label: string | null; quantity: number; std_minutes: number; source?: 'manual' | 'csv' }

export interface WorkforceSettings {
  capacity_hours: number; availability_source: 'attendance' | 'fixed'; fixed_availability_percent: number
  band_underload: number; band_watch: number; band_overload: number; band_critical: number
  sustain_months: number; attrition_flag_percent: number; confirmed_at: string | null
}

export interface PlanRow {
  designation_id: string; designation_name: string; grade_code: string
  sanctioned: number; planned: boolean; active: number
}

export interface DepartmentWorkforce {
  id: string; name: string; method: WorkloadMethod; per_employees: number | null; monthly_budget?: number | null
  plan: PlanRow[]; inputs: WorkloadInputRow[]; snapshot: SnapshotFigures | null
  trend: { period_month: string; index: number | null; band: Band }[]
  open_seats: number
}

export interface WorkforceDashboard {
  period_month: string
  settings: WorkforceSettings | null
  can: { manage: boolean; headcount: boolean; request: boolean; review: boolean; approve: boolean; money: boolean }
  departments: DepartmentWorkforce[]
}

export type VacancyStatus = 'draft' | 'hr_reviewed' | 'approved' | 'on_hold' | 'rejected' | 'cancelled' | 'filled'
export type VacancyReason = 'replacement' | 'new_position'

export interface VacancyEvent { event: string; from_status: string | null; to_status: string | null; note: string | null; actor_name: string | null; created_at: string }

export interface Vacancy {
  id: string; department_id: string; department_name: string; designation_id: string; designation_name: string
  grade_code: string; office_name: string | null; seats: number; reason: VacancyReason
  origin: 'separation' | 'snapshot' | 'manual'; separated_employee_name: string | null; period_month: string | null
  estimated_monthly_cost?: number | null; budget_status: BudgetStatus
  recommendation: SnapshotFigures | null; latest_snapshot: SnapshotFigures | null
  note: string | null; status: VacancyStatus; decision_note: string | null; created_at: string
  drafted_by_name: string | null; hr_reviewed_by: string | null; hr_reviewed_by_name: string | null
  hr_reviewed_at: string | null; decided_by_name: string | null; decided_at: string | null
  events: VacancyEvent[]
}

// ----------------------------------------------------------------------------- R2
export type EducationLevel = 'any' | 'ssc' | 'hsc' | 'diploma' | 'bachelor' | 'masters' | 'phd'
export type EmploymentType = 'permanent' | 'contract' | 'probation' | 'intern' | 'part_time'

export interface JobProfile {
  id: string; designation_id: string; department_id: string
  experience_min_years: number; experience_max_years: number | null
  education_level: EducationLevel; education_subjects: string[]
  required_skills: string[]; nice_skills: string[]; duties: string
  employment_type: EmploymentType; version: number; updated_at: string
}

export interface JobProfileRow {
  designation_id: string; designation_name: string; department_id: string; department_name: string
  grade_code: string; profile: JobProfile | null
}

export type JobPostStatus = 'draft' | 'published' | 'closed' | 'cancelled'
export type PosterTheme = 'orange' | 'navy' | 'green' | 'maroon'
export interface Weights { ats: number; objective: number; written: number; interview: number }

/** Salary fields shared by the HR and public views of a post. */
export interface SalaryFields { show_salary: boolean; salary_min: number | null; salary_max: number | null }

export interface JobPostSummary extends SalaryFields {
  id: string; vacancy_id: string; title: string; status: JobPostStatus; deadline: string; public_slug: string
  department_name: string; designation_name: string; seats: number
  published_at: string | null; created_at: string; applicants: number; with_cv: number; shortlisted?: number
}

export interface ReadyVacancy {
  vacancy_id: string; department_name: string; designation_id: string; designation_name: string
  grade_code: string; seats: number; reason: VacancyReason; decided_at: string | null; has_profile: boolean
}

export interface JobPostList { org_code: string; can?: { manage: boolean }; posts: JobPostSummary[]; ready: ReadyVacancy[] }

export interface JobPost extends SalaryFields {
  id: string; vacancy_id: string; department_id: string; designation_id: string
  profile: Omit<JobProfile, 'id' | 'updated_at'>; profile_version: number; profile_current_version: number | null
  title: string; description_md: string; location: string | null; seats: number; employment_type: EmploymentType
  deadline: string; public_slug: string; poster: { theme: PosterTheme }; weights: Weights; has_written_test: boolean
  status: JobPostStatus; published_at: string | null; closed_at: string | null; close_note: string | null
  department_name: string; designation_name: string; grade_code: string; org_code: string; org_name: string
  vacancy_status: VacancyStatus; vacancy_reason: VacancyReason; today: string
  /** R3 */
  cv_mode?: CvMode | null; cv_mode_effective?: CvMode; ai_ready?: boolean; can?: { manage: boolean }
}

export type ApplicantSource = 'form' | 'email' | 'linkedin' | 'bdjobs' | 'referral' | 'other'
export type ApplicantStatus =
  | 'applied' | 'screened_out' | 'shortlisted' | 'test_invited' | 'test_done' | 'written_done'
  | 'interview_scheduled' | 'interviewed' | 'selected' | 'rejected' | 'offer_sent' | 'offer_accepted'
  | 'offer_declined' | 'prejoining_done' | 'joined' | 'purged'

export interface Applicant {
  id: string; full_name: string; email: string; phone: string | null; source: ApplicantSource
  status: ApplicantStatus; has_cv: boolean; cv_path: string | null; cover_note: string | null
  consent_at: string | null; is_internal: boolean; created_at: string
  events: { event: string; from_status: string | null; to_status: string | null; actor_name: string | null; created_at: string }[]
  /** R3 */
  profile?: ApplicantProfile | null
  decisions?: { from_status: string; to_status: string; gate: string | null; note: string | null; actor_name: string | null; created_at: string }[]
}

/** What the public careers page receives (no internal fields). */
export interface PublicJobPost extends SalaryFields {
  slug: string; title: string; location: string | null; seats: number; employment_type: EmploymentType
  deadline: string; published_at: string | null; department_name: string; is_open: boolean
  description_md?: string; organization?: { name: string; org_code: string }
}

export interface PublicCareers { organization: { name: string; org_code: string }; posts: PublicJobPost[] }

// ----------------------------------------------------------------------------- R3
export type CvMode = 'basic' | 'ai'
export type AiModel = 'claude-opus-5-5' | 'claude-sonnet-5-5' | 'claude-haiku-5-5'
type Level = Exclude<EducationLevel, 'any'>

export interface ApplicantProfile {
  status: 'reading' | 'done' | 'failed'; mode_used: CvMode | 'manual' | null
  markdown: string | null; summary: string | null
  years: number | null; years_source: 'ai' | 'estimate' | 'hr' | null
  education_level: Level | null; education_source: 'ai' | 'estimate' | 'hr' | null
  skills_found: string[]; matched_required: string[]; matched_nice: string[]; subject_matched: boolean
  relevance: number | null; relevance_reason: string | null; relevance_source: 'ai' | 'hr' | null
  figures: import('./ats').AtsFigures | null; ats_score: number | null; gate: import('./ats').Gate | null
  ai_model: string | null; ai_error: string | null; error: string | null; read_at: string | null; updated_at: string
}

export interface RecruitSettings {
  cv_mode: CvMode; is_admin: boolean
  ai: { configured: boolean; enabled: boolean; model: AiModel; last4: string | null; tested_at: string | null
        test_status: 'ok' | 'failed' | null; test_message: string | null; updated_at: string } | null
}

export type PaperKind = 'objective' | 'written'
export type QuestionSection = 'aptitude' | 'job_knowledge' | 'language' | 'situational' | 'general'

export interface Question {
  section: QuestionSection; stem: string; options: string[] | null; correct_index: number | null
  model_answer: string | null; marks: number
}

export interface QuestionPaper {
  id: string; job_post_id: string; kind: PaperKind; duration_minutes: number | null; pass_percent: number | null
  total_marks: number; question_count: number; version: number; locked_at: string | null; updated_at: string
  questions: Question[]
}

export interface QuestionPapers {
  job_post_id: string; title: string; designation_id: string; designation_name: string; ai_available: boolean
  papers: Record<PaperKind, QuestionPaper | null>
  bank: Record<PaperKind, Question[]>
}

// ----------------------------------------------------------------------------- R4
export type InviteStatus = 'invited' | 'started' | 'submitted' | 'expired' | 'cancelled'

export interface BoardPaper {
  id: string; question_count: number; total_marks: number; duration_minutes: number | null
  pass_percent: number | null; locked: boolean
  questions?: { position: number; stem: string; marks: number; model_answer: string | null }[] | null
}

export interface Interview {
  id: string; starts_at: string; duration_minutes: number; mode: 'in_person' | 'online'
  location: string | null; online_link: string | null; panel: string[]; panel_names: string[] | null
  due_by: string; late_reason: string | null; note: string | null; proposed_by: 'system' | 'user'
}

export interface BoardRow {
  applicant_id: string; full_name: string; email: string; phone: string | null; status: ApplicantStatus
  ats_score: number | null; gate: import('./ats').Gate | null
  invite: { id: string; status: InviteStatus; expires_at: string; started_at: string | null; submitted_at: string | null
            auto_submitted: boolean; created_at: string } | null
  objective: { score: number; total: number; percent: number; passed: boolean | null; answered: number; correct: number
               sections: Partial<Record<QuestionSection, { score: number; total: number; percent: number | null }>> } | null
  written: { score: number; total: number; percent: number; passed: boolean | null; marks: { position: number; marks: number }[]
             updated_at: string } | null
  interview: Interview | null
  due_by: string
}

export interface AssessmentBoard {
  can: { manage: boolean; schedule: boolean }; today: string; timezone: string
  papers: Partial<Record<PaperKind, BoardPaper>>
  rows: BoardRow[]
}

export interface InterviewerOption { id: string; full_name: string; department_name: string | null; designation_name: string | null; same_department: boolean }

/** What the public test page receives: never the answer key. */
export interface TestState {
  status: InviteStatus; organization: string; job_title: string; first_name: string
  duration_minutes: number; question_count: number; total_marks: number; expires_at: string; auto_submitted: boolean
  seconds_left: number | null
  questions: { position: number; section: QuestionSection; stem: string; options: string[]; marks: number }[] | null
  answers: Record<string, number> | null
}
