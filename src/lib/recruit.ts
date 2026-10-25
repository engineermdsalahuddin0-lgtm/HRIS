// Onboarding process R2 (job posts and applications): React Query hooks.
// Rules live in the database; src/onboarding-process/core/jobPost.ts mirrors them for instant feedback.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type {
  Applicant, AssessmentBoard, CandidateResults, Channel, CvMode, InterviewerKit, InterviewerOption, JobPost, JobPostList,
  JobProfileRow, MessagingSettings, MyInterview, NotificationRow, OfferContext, OfferList, OnboardingCase, OnboardingCaseRow,
  PreinterviewForm, PrehireReview, PrehireState, PublicCareers, PublicJobPost, PublicOffer, PurgePlan, QuestionPapers,
  RecruitSettings, TestState,
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

// ---------------------------------------------------------------------------- R5: messages, forms, interviewers, results
export function useMessagingSettings() {
  return useQuery({ queryKey: ['recruit', 'messaging'], queryFn: () => callRpc<MessagingSettings>('get_messaging_settings') })
}

export function useNotifications(postId: string) {
  return useQuery({ queryKey: ['recruit', 'outbox', postId], queryFn: () => callRpc<NotificationRow[]>('list_notifications', { p_job_post_id: postId }) })
}

export function useCandidateResults(postId: string) {
  return useQuery({ queryKey: ['recruit', 'results', postId], queryFn: () => callRpc<CandidateResults>('get_candidate_results', { p_job_post_id: postId }) })
}

export function useMyInterviews() {
  return useQuery({ queryKey: ['interviews', 'mine'], queryFn: () => callRpc<MyInterview[]>('list_my_interviews') })
}

export function useInterviewerKit(id: string | undefined) {
  return useQuery({ queryKey: ['interviews', 'kit', id], enabled: !!id, queryFn: () => callRpc<InterviewerKit>('get_interviewer_kit', { p_interview_id: id }) })
}

export function useSubmitInterviewScore(id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (p: Record<string, unknown>) => callRpc<{ mean: number; panel_complete: boolean }>('submit_interview_score', { p_interview_id: id, p }),
    onSuccess: () => Promise.all([qc.invalidateQueries({ queryKey: ['interviews'] }), qc.invalidateQueries({ queryKey: ['recruit'] })]),
  })
}

/** Sends what is queued (Edge Function recruit-notify). Quietly does nothing when it is not deployed or set up. */
export async function sendQueuedMessages(): Promise<{ sent: number; failed: number } | { error: string }> {
  const { data, error } = await supabase.functions.invoke('recruit-notify', { body: { action: 'send' } })
  if (error) {
    const context = (error as { context?: Response }).context
    const detail = context && typeof context.json === 'function' ? await context.json().catch(() => null) : null
    return { error: detail?.error ?? (error.message.includes('Failed to send') ? 'The recruit-notify function is not deployed yet' : error.message) }
  }
  return data
}

export async function testMessaging(channel: Channel, to: string): Promise<{ ok: boolean; message: string }> {
  const { data, error } = await supabase.functions.invoke('recruit-notify', { body: { action: 'test', channel, to } })
  if (error) {
    const context = (error as { context?: Response }).context
    const detail = context && typeof context.json === 'function' ? await context.json().catch(() => null) : null
    return { ok: false, message: detail?.error ?? (error.message.includes('Failed to send') ? 'The recruit-notify function is not deployed yet' : error.message) }
  }
  return data
}

/** The public pre-interview form. */
export const formApi = {
  get: (token: string) => callRpc<PreinterviewForm>('get_preinterview_form', { p_token: token }),
  submit: (token: string, p: Record<string, unknown>) => callRpc<void>('submit_preinterview_form', { p_token: token, p }),
}

// ---------------------------------------------------------------------------- R6 / R7: offers, pre-joining, joining
export function useOffers(postId: string) {
  return useQuery({ queryKey: ['recruit', 'offers', postId], queryFn: () => callRpc<OfferList>('list_offers', { p_job_post_id: postId }) })
}

export function useOfferContext(applicantId: string) {
  return useQuery({ queryKey: ['recruit', 'offer-context', applicantId], queryFn: () => callRpc<OfferContext>('get_offer_context', { p_applicant_id: applicantId }) })
}

export function usePrehire(id: string | undefined) {
  return useQuery({ queryKey: ['recruit', 'prehire', id], enabled: !!id, queryFn: () => callRpc<PrehireReview>('get_prehire', { p_prehire_id: id }) })
}

export function useOnboardingCases(postId: string) {
  return useQuery({ queryKey: ['recruit', 'cases', postId], queryFn: () => callRpc<OnboardingCaseRow[]>('list_onboarding_cases', { p_job_post_id: postId }) })
}

export function useOnboardingCase(id: string | undefined) {
  return useQuery({ queryKey: ['recruit', 'case', id], enabled: !!id, queryFn: () => callRpc<OnboardingCase>('get_onboarding_case', { p_case_id: id }) })
}

/** Signed link to a private file (HR may read prehire photos and signed documents of the company). */
export async function signedUrl(bucket: string, path: string, seconds = 300) {
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, seconds)
  if (error) throw error
  return data.signedUrl
}

/** Copies the pre-joining photo into the employee's profile (employee-files/{org}/{employee}/photo). */
export async function copyPrehirePhoto(orgId: string, employeeId: string, photoPath: string) {
  const { data, error } = await supabase.storage.from('prehire-files').download(photoPath)
  if (error) throw error
  const { error: up } = await supabase.storage.from('employee-files').upload(`${orgId}/${employeeId}/photo`, data, { upsert: true, contentType: data.type || 'image/jpeg' })
  if (up) throw up
}

/** Close hiring: delete the files listed in the plan, then purge the applicants (the database refuses while files remain). */
export async function closeHiring(postId: string, plan: PurgePlan) {
  for (const bucket of ['recruit-cvs', 'prehire-files'] as const) {
    const paths = plan.files[bucket]
    for (let i = 0; i < paths.length; i += 100) {
      const { error } = await supabase.storage.from(bucket).remove(paths.slice(i, i + 100))
      if (error) throw error
    }
  }
  return callRpc<{ purged: number }>('purge_post_applicants', { p_job_post_id: postId, p_confirm: 'DELETE' })
}

export const getPurgePlan = (postId: string) => callRpc<PurgePlan>('get_purge_plan', { p_job_post_id: postId })

/** The public offer page and pre-joining form. */
export const offerApi = {
  get: (token: string) => callRpc<PublicOffer>('get_offer', { p_token: token }),
  respond: (token: string, answer: 'accept' | 'decline', note: string) => callRpc<PublicOffer>('respond_offer', { p_token: token, p_answer: answer, p_note: note }),
  photoPath: (token: string, ext: string) => callRpc<string>('start_prejoining_photo', { p_token: token, p_ext: ext }),
  uploadPhoto: async (path: string, file: File) => {
    const { error } = await supabase.storage.from('prehire-files').upload(path, file, { contentType: file.type })
    if (error) throw error
  },
  submit: (token: string, p: Record<string, unknown>) => callRpc<PrehireState>('submit_prejoining', { p_token: token, p }),
}

export const feedbackApi = {
  get: (token: string) => callRpc<{ organization: string; full_name: string; joining_date: string; submitted: boolean; open: boolean }>('get_joining_feedback', { p_token: token }),
  submit: (token: string, p: Record<string, unknown>) => callRpc<void>('submit_joining_feedback', { p_token: token, p }),
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
