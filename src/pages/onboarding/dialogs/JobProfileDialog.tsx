// What a designation needs. Every new job post for it is filled from this profile;
// posts already created keep their own copy.
import { useState } from 'react'
import type { EducationLevel, EmploymentType, JobProfileRow } from '@/onboarding-process/core/types'
import { EDUCATION_LABEL, EMPLOYMENT_LABEL } from '@/onboarding-process/core/jobPost'
import { useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'

const list = (text: string) => text.split(/,|\n/).map((s) => s.trim()).filter(Boolean)

export function JobProfileDialog({ row, onClose, onSaved }: { row: JobProfileRow; onClose: () => void; onSaved?: () => void }) {
  const p = row.profile
  const save = useRecruitAction<{ p_designation_id: string; p: Record<string, unknown> }, string>('save_job_profile')
  const [minYears, setMinYears] = useState(String(p?.experience_min_years ?? 0))
  const [maxYears, setMaxYears] = useState(p?.experience_max_years == null ? '' : String(p.experience_max_years))
  const [level, setLevel] = useState<EducationLevel>(p?.education_level ?? 'any')
  const [subjects, setSubjects] = useState((p?.education_subjects ?? []).join(', '))
  const [skills, setSkills] = useState((p?.required_skills ?? []).join(', '))
  const [nice, setNice] = useState((p?.nice_skills ?? []).join(', '))
  const [duties, setDuties] = useState(p?.duties ?? '')
  const [type, setType] = useState<EmploymentType>(p?.employment_type ?? 'permanent')

  const submit = () => save.mutate({
    p_designation_id: row.designation_id,
    p: {
      experience_min_years: Number(minYears || 0), experience_max_years: maxYears === '' ? null : Number(maxYears),
      education_level: level, education_subjects: list(subjects), required_skills: list(skills), nice_skills: list(nice),
      duties, employment_type: type,
    },
  }, { onSuccess: () => { onSaved?.(); onClose() } })

  return (
    <Modal open onClose={onClose} size="lg" title={`Job profile · ${row.designation_name}`}
      description={<>{row.department_name} · {row.grade_code}{p ? ` · version ${p.version}` : ' · new'}</>}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={duties.trim().length < 10} onClick={submit}>Save profile</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <div className="grid gap-4 sm:grid-cols-3">
          <Input label="Experience from (years)" inputMode="decimal" value={minYears} onChange={(e) => setMinYears(e.target.value)} />
          <Input label="Experience up to (optional)" inputMode="decimal" value={maxYears} onChange={(e) => setMaxYears(e.target.value)}
            hint="Leave empty for no upper limit" />
          <Select label="Employment type" value={type} onChange={(e) => setType(e.target.value as EmploymentType)}
            options={Object.entries(EMPLOYMENT_LABEL).map(([value, label]) => ({ value, label }))} />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <Select label="Minimum education" value={level} onChange={(e) => setLevel(e.target.value as EducationLevel)}
            options={Object.entries(EDUCATION_LABEL).map(([value, label]) => ({ value, label }))} />
          <Input label="Subjects (comma separated)" value={subjects} disabled={level === 'any'} placeholder="Accounting, Finance"
            onChange={(e) => setSubjects(e.target.value)} />
        </div>
        <Input label="Required skills (comma separated)" value={skills} placeholder="Tally, Excel, VAT"
          onChange={(e) => setSkills(e.target.value)} hint="Used later to score CVs; up to 20" />
        <Input label="Nice-to-have skills (comma separated)" value={nice} placeholder="IFRS" onChange={(e) => setNice(e.target.value)} />
        <Textarea label="Duties (one per line)" rows={6} value={duties} maxLength={4000} onChange={(e) => setDuties(e.target.value)}
          hint="Each line becomes a bullet under Responsibilities." />
        <p className="text-xs text-slate-500">Gender, age, religion, marital status and photo are never asked for or scored.</p>
      </div>
    </Modal>
  )
}
