// Onboarding process R2 (job posts and applications): React Query hooks.
// Rules live in the database; src/onboarding-process/core/jobPost.ts mirrors them for instant feedback.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type {
  Applicant, AssessmentBoard, CvMode, InterviewerOption, JobPost, JobPostList, JobProfileRow, PublicCareers, PublicJobPost,
  QuestionPapers, RecruitSettings, TestState,
} from '@/onboarding-process/core/types'
import type { CvExtension } from '@/onboarding-process/core/jobPost'
import { CV_TYPES, cvError, cvExtension } from '@/onboarding-process/core/jobPost'

const CV_BUCKET = 'recruit-cvs'

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

export function useJobPosts() {
  return useQuery({ queryKey: ['recruit', 'posts'], queryFn: () => callRpc<JobPostList>('list_job_posts') })
}

export function useJobProfiles(enabled = true) {
  return useQuery({ queryKey: ['recruit', 'profiles'], enabled, queryFn: () => callRpc<JobProfileRow[]>('list_job_profiles') })
}

// ---------------------------------------------------------------------------- R3: screening, papers, AI
export function useRecruitSettings() {
  return useQuery({ queryKey: ['recruit', 'settings'], queryFn: () => callRpc<RecruitSettings>('get_recruit_settings') })
}

export function useQuestionPapers(postId: string | undefined) {
  return useQuery({
    queryKey: ['recruit', 'papers', postId],
    enabled: !!postId,
    queryFn: () => callRpc<QuestionPapers>('get_question_papers', { p_job_post_id: postId }),
  })
}

// ---------------------------------------------------------------------------- R4: tests, marks, interviews
export function useAssessmentBoard(postId: string | undefined) {
  return useQuery({
    queryKey: ['recruit', 'board', postId],
    enabled: !!postId,
    refetchInterval: 30_000, // results arrive while applicants take the test
    queryFn: () => callRpc<AssessmentBoard>('get_assessment_board', { p_job_post_id: postId }),
  })
}

export function useInterviewerOptions(postId: string, enabled: boolean) {
  return useQuery({
    queryKey: ['recruit', 'interviewers', postId],
    enabled,
    staleTime: 5 * 60_000,
    queryFn: () => callRpc<InterviewerOption[]>('list_interviewer_options', { p_job_post_id: postId }),
  })
}

/** The public test page: every call carries the link's token. */
export const testApi = {
  get: (token: string) => callRpc<TestState>('get_test', { p_token: token }),
  start: (token: string) => callRpc<TestState>('start_test', { p_token: token }),
  answer: (token: string, position: number, choice: number) =>
    callRpc<void>('save_test_answer', { p_token: token, p_position: position, p_choice: choice }),
  submit: (token: string) => callRpc<{ status: string }>('submit_test', { p_token: token }),
}

/** The recruit-ai Edge Function (CV reading, AI question drafts, key test). Errors carry the function's message. */
export async function callRecruitAi<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('recruit-ai', { body })
  if (error) {
    const context = (error as { context?: Response }).context
    const detail = context && typeof context.json === 'function' ? await context.json().catch(() => null) : null
    throw new Error(detail?.error ?? (error.message.includes('Failed to send') ? 'The recruit-ai function is not deployed yet' : error.message))
  }
  return data as T
}

export interface CvReadResult { mode: CvMode; ai_ready: boolean; started_at: string; read: number; results: { applicant_id: string; status: string; error?: string }[] }

/** Reads CVs in rounds of 5 until a round finds none left (`since` keeps a re-read from repeating a CV). */
export function useReadCvs(postId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ again, onRound }: { again: boolean; onRound?: (total: number) => void }) => {
      // The database's clock of the first round marks where a re-read started.
      let since: string | null = null
      let total = 0
      let failed = 0
      for (let round = 0; round < 40; round += 1) {
        const r: CvReadResult = await callRecruitAi<CvReadResult>({ action: 'read_cvs', job_post_id: postId, again, since })
        since = since ?? r.started_at
        total += r.read
        failed += r.results.filter((x) => x.status === 'failed').length
        onRound?.(total)
        await qc.invalidateQueries({ queryKey: ['recruit', 'applicants', postId] })
        if (r.read === 0) break
      }
      return { total, failed }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['recruit'] }),
  })
}

export function useJobPost(id: string | undefined) {
  return useQuery({
    queryKey: ['recruit', 'post', id],
    enabled: !!id,
    queryFn: () => callRpc<JobPost>('get_job_post', { p_id: id }),
  })
}

export function useApplicants(postId: string | undefined) {
  return useQuery({
    queryKey: ['recruit', 'applicants', postId],
    enabled: !!postId,
    queryFn: () => callRpc<Applicant[]>('list_applicants', { p_job_post_id: postId }),
  })
}

/** Any recruitment RPC; refreshes recruitment and vacancy queries afterwards. */
export function useRecruitAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (args: A) => callRpc<R>(fn, args),
    onSuccess: () => Promise.all([qc.invalidateQueries({ queryKey: ['recruit'] }), qc.invalidateQueries({ queryKey: ['workforce'] })]),
  })
}

/** HR uploads a CV for an applicant added from email / LinkedIn / Bdjobs. */
export function useUploadApplicantCv(orgId: string | undefined, postId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ applicantId, file, previous }: { applicantId: string; file: File; previous: string | null }) => {
      const problem = cvError(file)
      if (problem) throw new Error(problem)
      const ext = cvExtension(file.name) as CvExtension
      const path = `${orgId}/${postId}/${applicantId}.${ext}`
      const bucket = supabase.storage.from(CV_BUCKET)
      if (previous && previous !== path) await bucket.remove([previous])
      const { error } = await bucket.upload(path, file, { upsert: true, contentType: CV_TYPES[ext] })
      if (error) throw error
      await callRpc('attach_applicant_cv', { p_applicant_id: applicantId, p_ext: ext })
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['recruit'] }),
  })
}

/** Short-lived link to read a CV (the storage policy allows HR of the same company only). */
export async function openCv(path: string) {
  const { data, error } = await supabase.storage.from(CV_BUCKET).createSignedUrl(path, 300)
  if (error) throw error
  window.open(data.signedUrl, '_blank', 'noopener')
}

// ---------------------------------------------------------------------------- public (no login)
export function usePublicCareers(orgCode: string | undefined) {
  return useQuery({
    queryKey: ['careers', orgCode],
    enabled: !!orgCode,
    retry: false,
    queryFn: () => callRpc<PublicCareers>('get_public_careers', { p_org_code: orgCode }),
  })
}

export function usePublicJobPost(orgCode: string | undefined, slug: string | undefined) {
  return useQuery({
    queryKey: ['careers', orgCode, slug],
    enabled: !!orgCode && !!slug,
    retry: false,
    queryFn: () => callRpc<PublicJobPost>('get_public_job_post', { p_org_code: orgCode, p_slug: slug }),
  })
}

export interface ApplicationForm {
  full_name: string; email: string; phone: string; cover_note: string; consent: boolean; website: string
}

/** Apply: the database records the application and returns where the CV may go; then upload and confirm. */
export function useSubmitApplication(orgCode: string, slug: string) {
  return useMutation({
    mutationFn: async ({ form, file }: { form: ApplicationForm; file: File }) => {
      const problem = cvError(file)
      if (problem) throw new Error(problem)
      const ticket = await callRpc<{ applicant_id: string; upload_path: string; upload_token: string }>('submit_job_application', {
        p_org_code: orgCode, p_slug: slug,
        p: { ...form, cv_file_name: file.name, cv_size: file.size, cv_type: file.type },
      })
      const { error } = await supabase.storage.from(CV_BUCKET).upload(ticket.upload_path, file, { contentType: file.type })
      if (error) throw new Error('Your application was saved, but the CV upload failed. Please contact the company with your CV.')
      await callRpc('confirm_cv_upload', { p_applicant_id: ticket.applicant_id, p_token: ticket.upload_token })
      return ticket.applicant_id
    },
  })
}
