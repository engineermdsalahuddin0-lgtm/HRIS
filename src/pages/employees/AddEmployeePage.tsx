import { useState } from 'react'
import { useFieldArray, useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft, Check, Plus, Trash2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage, normalizeBdPhone, passwordRule } from '@/lib/identity'
import { BLOOD_GROUPS, EMPLOYMENT_TYPES, GENDERS, LINE_TYPES, MARITAL, RELIGIONS, today } from '@/lib/options'
import { useEmployeeOptions, useInvalidate, useOrgSettings, useOrgStructure, useRolesData } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { Checkbox, PageHeader, Select, Textarea } from '@/components/kit'

const optionalPhone = z.string().trim().refine((v) => v === '' || normalizeBdPhone(v) !== null, 'Use 01XXXXXXXXX or +8801XXXXXXXXX')

const schema = z
  .object({
    full_name: z.string().trim().min(2, 'Full name is required (as per NID)'),
    date_of_birth: z.string(),
    gender: z.string(),
    marital_status: z.string(),
    religion: z.string(),
    blood_group: z.string(),
    phone: optionalPhone,
    email: z.string().trim().refine((v) => v === '' || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Enter a valid email'),
    nid_number: z.string().trim().refine((v) => v === '' || /^(\d{10}|\d{13}|\d{17})$/.test(v), 'NID must be 10, 13 or 17 digits'),
    join_date: z.string().min(1, 'Join date is required'),
    department_id: z.string().min(1, 'Choose a department'),
    designation_id: z.string().min(1, 'Choose a designation'),
    branch_id: z.string().min(1, 'Choose a branch'),
    office_id: z.string().min(1, 'Choose an office'),
    operation_id: z.string(),
    present_address: z.string(),
    permanent_address: z.string(),
    nominees: z.array(z.object({ name: z.string().trim().min(2, 'Name required'), relation: z.string().trim().min(2, 'Relation required'), phone: optionalPhone })),
    // Step 2
    employment_type: z.string().min(1),
    probation_end_date: z.string(),
    card_id: z.string().trim(),
    reporting: z.record(z.string(), z.string()),
    portal: z.boolean(),
    portal_email: z.string().trim(),
    portal_phone: z.string().trim(),
    portal_password: z.string(),
    portal_role_id: z.string(),
  })
  .superRefine((v, ctx) => {
    if (!v.portal) return
    if (!v.portal_email && !v.portal_phone) ctx.addIssue({ code: 'custom', path: ['portal_email'], message: 'Give an email or mobile number for the login' })
    if (v.portal_phone && !normalizeBdPhone(v.portal_phone)) ctx.addIssue({ code: 'custom', path: ['portal_phone'], message: 'Use 01XXXXXXXXX' })
    if (!passwordRule.test(v.portal_password)) ctx.addIssue({ code: 'custom', path: ['portal_password'], message: passwordRule.message })
  })
type FormValues = z.infer<typeof schema>

const STEP1_FIELDS: (keyof FormValues)[] = [
  'full_name', 'phone', 'email', 'nid_number', 'join_date', 'department_id', 'designation_id', 'branch_id', 'office_id', 'nominees',
]

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card>
      <h3 className="mb-4 font-semibold text-slate-900">{title}</h3>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{children}</div>
    </Card>
  )
}

export default function AddEmployeePage() {
  const ctx = useMyContext()
  const navigate = useNavigate()
  const invalidate = useInvalidate()
  const isAdmin = ctx.role?.system_key === 'admin'
  const canPortal = ctx.permissions.includes('employees.portal_access')
  const structure = useOrgStructure()
  const settings = useOrgSettings(ctx.organization?.id)
  const managers = useEmployeeOptions()
  const roles = useRolesData()
  const [step, setStep] = useState<1 | 2>(1)
  const [error, setError] = useState<string | null>(null)
  const [warning, setWarning] = useState<string | null>(null)

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      full_name: '', date_of_birth: '', gender: '', marital_status: '', religion: '', blood_group: '', phone: '', email: '',
      nid_number: '', join_date: today(), department_id: '', designation_id: '', branch_id: '', office_id: '', operation_id: '',
      present_address: '', permanent_address: '', nominees: [], employment_type: 'probation', probation_end_date: '',
      card_id: '', reporting: {}, portal: false, portal_email: '', portal_phone: '', portal_password: '', portal_role_id: '',
    },
  })
  const { register, watch, setValue, getValues, formState: { errors, isSubmitting } } = form
  const nominees = useFieldArray({ control: form.control, name: 'nominees' })

  if (structure.isPending || settings.isPending) return <PageLoader />
  if (structure.isError) return <Alert>{errorMessage(structure.error)}</Alert>
  const s = structure.data
  const customCard = settings.data?.card_id_mode === 'custom'

  const dept = watch('department_id')
  const branch = watch('branch_id')
  const office = watch('office_id')
  const opts = <T extends { id: string; name: string; status: string }>(xs: T[], pred: (x: T) => boolean = () => true) =>
    xs.filter((x) => x.status === 'active' && pred(x)).map((x) => ({ value: x.id, label: x.name }))
  const gradeOf = (gradeId: string) => s.grades.find((g) => g.id === gradeId)?.code
  const designationOptions = s.designations
    .filter((d) => d.status === 'active' && d.department_id === dept)
    .map((d) => ({ value: d.id, label: `${d.name} (${gradeOf(d.grade_id) ?? '—'})` }))
  const officeOps = new Set(s.officeOperations.filter((x) => x.office_id === office).map((x) => x.operation_id))
  const roleOptions = (roles.data?.roles ?? [])
    .filter((r) => r.status === 'active' && (isAdmin || r.system_key === 'employee'))
    .map((r) => ({ value: r.id, label: r.name }))

  const next = async () => {
    setError(null)
    if (await form.trigger(STEP1_FIELDS)) {
      setStep(2)
      window.scrollTo({ top: 0 })
    }
  }

  const submit = form.handleSubmit(async (v) => {
    setError(null)
    if (customCard && !/^[A-Za-z0-9-]{6,15}$/.test(v.card_id)) {
      form.setError('card_id', { message: '6–15 letters, numbers or hyphens' })
      return
    }
    // Login details go only to grant_portal_access, never into the employee payload.
    const { portal: _p, portal_email: _e, portal_phone: _ph, portal_password: _pw, portal_role_id: _r, reporting, ...employee } = v
    const payload = {
      ...employee,
      reporting: Object.entries(reporting).filter(([, id]) => id).map(([line_type, manager_employee_id]) => ({ line_type, manager_employee_id })),
    }
    const { data: id, error: createError } = await supabase.rpc('create_employee', { p: payload })
    if (createError) {
      setError(errorMessage(createError))
      return
    }
    if (v.portal) {
      const { error: portalError } = await supabase.rpc('grant_portal_access', {
        p_employee_id: id,
        p_email: v.portal_email || null,
        p_phone: v.portal_phone || null,
        p_password: v.portal_password,
        p_role_id: v.portal_role_id || null,
      })
      if (portalError) {
        await invalidate('employees', 'dashboard')
        setWarning(`Employee created, but portal access failed: ${errorMessage(portalError)}. You can give access from the profile.`)
        setTimeout(() => navigate(`/employees/${id}`), 2500)
        return
      }
    }
    await invalidate('employees', 'dashboard')
    navigate(`/employees/${id}`)
  })

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <button onClick={() => navigate('/employees')} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
        <ArrowLeft className="size-4" /> Employees
      </button>
      <PageHeader title="Add employee" description="Two steps: personal and job details, then role, card ID and reporting chain." />

      <ol className="flex items-center gap-3 text-sm" aria-label="Progress">
        {['Personal & job', 'Role, card ID & reporting'].map((label, i) => {
          const n = (i + 1) as 1 | 2
          const done = step > n
          return (
            <li key={label} className="flex items-center gap-2">
              <span
                className={cx(
                  'flex size-7 items-center justify-center rounded-full text-xs font-semibold',
                  step === n ? 'bg-primary-600 text-white' : done ? 'bg-green-600 text-white' : 'bg-slate-200 text-slate-600',
                )}
                aria-current={step === n ? 'step' : undefined}
              >
                {done ? <Check className="size-4" /> : n}
              </span>
              <span className={step === n ? 'font-medium text-slate-900' : 'text-slate-500'}>{label}</span>
              {i === 0 && <span className="mx-1 h-px w-8 bg-slate-300" aria-hidden />}
            </li>
          )
        })}
      </ol>

      {error && <Alert>{error}</Alert>}
      {warning && <Alert tone="info">{warning}</Alert>}

      <form onSubmit={submit} noValidate className="space-y-6">
        {step === 1 && (
          <>
            <Section title="Personal information">
              <Input label="Full name (as per NID) *" error={errors.full_name?.message} {...register('full_name')} className="sm:col-span-2" />
              <Input label="Date of birth" type="date" {...register('date_of_birth')} />
              <Select label="Gender" options={GENDERS} placeholder="—" {...register('gender')} />
              <Select label="Marital status" options={MARITAL} placeholder="—" {...register('marital_status')} />
              <Select label="Religion" options={RELIGIONS} placeholder="—" {...register('religion')} />
              <Select label="Blood group" options={BLOOD_GROUPS} placeholder="—" {...register('blood_group')} />
              <Input label="Phone" placeholder="01XXXXXXXXX" error={errors.phone?.message} {...register('phone')} />
              <Input label="Email" type="email" error={errors.email?.message} {...register('email')} />
            </Section>

            <Section title="Identification">
              <Input label="NID number" inputMode="numeric" hint="10, 13 or 17 digits" error={errors.nid_number?.message} {...register('nid_number')} />
            </Section>

            <Section title="Job">
              <Input label="Join date *" type="date" error={errors.join_date?.message} {...register('join_date')} />
              <Select
                label="Department" required options={opts(s.departments)} placeholder="Select…" error={errors.department_id?.message}
                {...register('department_id', { onChange: () => setValue('designation_id', '') })}
              />
              <Select
                label="Designation" required options={designationOptions} placeholder={dept ? 'Select…' : 'Choose a department first'}
                disabled={!dept} error={errors.designation_id?.message} {...register('designation_id')}
              />
              <Select
                label="Branch" required options={opts(s.branches)} placeholder="Select…" error={errors.branch_id?.message}
                {...register('branch_id', { onChange: () => { setValue('office_id', ''); setValue('operation_id', '') } })}
              />
              <Select
                label="Office" required options={opts(s.offices, (o) => o.branch_id === branch)}
                placeholder={branch ? 'Select…' : 'Choose a branch first'} disabled={!branch} error={errors.office_id?.message}
                {...register('office_id', { onChange: () => setValue('operation_id', '') })}
              />
              <Select
                label="Operation" options={opts(s.operations, (o) => officeOps.has(o.id))}
                placeholder={office ? (officeOps.size ? 'None' : 'No operations in this office') : 'Choose an office first'}
                disabled={!office || officeOps.size === 0} {...register('operation_id')}
              />
            </Section>

            <Card>
              <div className="mb-4 flex items-center justify-between">
                <h3 className="font-semibold text-slate-900">Nominees</h3>
                <Button type="button" variant="secondary" onClick={() => nominees.append({ name: '', relation: '', phone: '' })}>
                  <Plus className="size-4" /> Add nominee
                </Button>
              </div>
              {nominees.fields.length === 0 ? (
                <p className="text-sm text-slate-500">No nominees added.</p>
              ) : (
                <div className="space-y-3">
                  {nominees.fields.map((f, i) => (
                    <div key={f.id} className="grid gap-3 rounded-xl bg-slate-50 p-3 sm:grid-cols-[1fr_1fr_1fr_auto] sm:items-start">
                      <Input label="Name" error={errors.nominees?.[i]?.name?.message} {...register(`nominees.${i}.name`)} />
                      <Input label="Relation" placeholder="e.g. Mother" error={errors.nominees?.[i]?.relation?.message} {...register(`nominees.${i}.relation`)} />
                      <Input label="Phone" placeholder="01XXXXXXXXX" error={errors.nominees?.[i]?.phone?.message} {...register(`nominees.${i}.phone`)} />
                      <button type="button" onClick={() => nominees.remove(i)} className="mt-7 rounded-lg p-2 text-slate-400 hover:bg-white hover:text-red-600" aria-label="Remove nominee">
                        <Trash2 className="size-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </Card>

            <Card>
              <h3 className="mb-4 font-semibold text-slate-900">Address</h3>
              <div className="grid gap-4 sm:grid-cols-2">
                <Textarea label="Present address" {...register('present_address')} />
                <div>
                  <Textarea label="Permanent address" {...register('permanent_address')} />
                  <button type="button" className="mt-1 text-xs font-medium text-primary-600" onClick={() => setValue('permanent_address', getValues('present_address'))}>
                    Same as present address
                  </button>
                </div>
              </div>
            </Card>

            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" onClick={() => navigate('/employees')}>Cancel</Button>
              <Button type="button" onClick={next}>Next</Button>
            </div>
          </>
        )}

        {step === 2 && (
          <>
            <Section title="Employment">
              <Select label="Employment type" required options={EMPLOYMENT_TYPES} {...register('employment_type')} />
              {watch('employment_type') === 'probation' && <Input label="Probation end date" type="date" {...register('probation_end_date')} />}
              {customCard ? (
                <Input label="Card ID *" placeholder="e.g. GZP-00123" hint="6–15 letters, numbers or hyphens" error={errors.card_id?.message} {...register('card_id')} />
              ) : (
                <Input label="Card ID" value={`Generated automatically (${settings.data?.card_id_length} digits)`} disabled name="card_id_preview" />
              )}
            </Section>

            <Section title="Reporting chain">
              {LINE_TYPES.map((l) => (
                <Select
                  key={l.value}
                  label={l.label}
                  options={(managers.data ?? []).map((m) => ({ value: m.id, label: `${m.full_name} (${m.card_id})` }))}
                  placeholder="None"
                  {...register(`reporting.${l.value}`)}
                />
              ))}
            </Section>

            {canPortal && (
              <Card>
                <Checkbox label="Give portal access now" checked={watch('portal')} onChange={(v) => setValue('portal', v)} />
                {watch('portal') && (
                  <div className="mt-4 grid gap-4 sm:grid-cols-2">
                    <Input label="Login email" type="email" error={errors.portal_email?.message} {...register('portal_email')} />
                    <Input label="Login mobile" placeholder="01XXXXXXXXX" error={errors.portal_phone?.message} {...register('portal_phone')} />
                    <Input label="First password" type="text" autoComplete="off" hint="They must change it at first login" error={errors.portal_password?.message} {...register('portal_password')} />
                    <Select
                      label="Role"
                      options={roleOptions}
                      placeholder="Employee"
                      hint={isAdmin ? undefined : 'Only an Admin can give other roles'}
                      {...register('portal_role_id')}
                    />
                  </div>
                )}
              </Card>
            )}

            <div className="flex justify-between gap-2">
              <Button type="button" variant="secondary" onClick={() => setStep(1)}>Back</Button>
              <Button type="submit" loading={isSubmitting}>Create employee</Button>
            </div>
          </>
        )}
      </form>
    </div>
  )
}
