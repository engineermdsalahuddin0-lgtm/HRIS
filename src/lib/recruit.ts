// Onboarding process R2 (job posts and applications): React Query hooks.
// Rules live in the database; src/onboarding-process/core/jobPost.ts mirrors them for instant feedback.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type {
  Applicant, JobPost, JobPostList, JobProfileRow, PublicCareers, PublicJobPost,
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

export function useJobProfiles() {
  return useQuery({ queryKey: ['recruit', 'profiles'], queryFn: () => callRpc<JobProfileRow[]>('list_job_profiles') })
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
