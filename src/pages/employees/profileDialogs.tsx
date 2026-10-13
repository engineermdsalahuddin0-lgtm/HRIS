import { useEffect, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { errorMessage, normalizeBdPhone, passwordRule } from '@/lib/identity'
import { BLOOD_GROUPS, EMPLOYMENT_TYPES, GENDERS, LINE_TYPES, MARITAL, RELIGIONS, today } from '@/lib/options'
import type { EmployeeProfile, Nominee, OrgStructure } from '@/lib/hr'
import { useEmployeeOptions, useHrAction, useRolesData } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Button, Input } from '@/components/ui'
import type { Option } from '@/components/kit'
import { Modal, Select, Textarea } from '@/components/kit'

interface DialogProps {
  profile: EmployeeProfile
  open: boolean
  onClose: () => void
}

// ------------------------------------------------------------------- edit --
interface EditField {
  key: string
  label: string
  type?: 'date' | 'select' | 'textarea'
  options?: Option[]
  resource?: 'employees' | 'employee_sensitive'
}

const EDIT_FIELDS: EditField[] = [
  { key: 'full_name', label: 'Full name (as per NID)' },
  { key: 'phone', label: 'Phone' },
  { key: 'email', label: 'Email' },
  { key: 'date_of_birth', label: 'Date of birth', type: 'date' },
  { key: 'gender', label: 'Gender', type: 'select', options: GENDERS },
  { key: 'marital_status', label: 'Marital status', type: 'select', options: MARITAL },
  { key: 'religion', label: 'Religion', type: 'select', options: RELIGIONS },
  { key: 'blood_group', label: 'Blood group', type: 'select', options: BLOOD_GROUPS },
  { key: 'nid_number', label: 'NID number', resource: 'employee_sensitive' },
  { key: 'join_date', label: 'Join date', type: 'date' },
  { key: 'employment_type', label: 'Employment type', type: 'select', options: EMPLOYMENT_TYPES },
  { key: 'probation_end_date', label: 'Probation end date', type: 'date' },
  { key: 'confirmation_date', label: 'Confirmation date', type: 'date' },
  { key: 'present_address', label: 'Present address', type: 'textarea' },
  { key: 'permanent_address', label: 'Permanent address', type: 'textarea' },
]

export function EditEmployeeDialog({ profile, open, onClose }: DialogProps) {
  const update = useHrAction<{ p_employee_id: string; p: Record<string, unknown> }>('update_employee')
  const allowed = new Set(profile.editable_fields ?? [])
  const fields = EDIT_FIELDS.filter((f) => allowed.has(`${f.resource ?? 'employees'}.${f.key}`))
  const canNominees = allowed.has('employees.nominees')
  const [values, setValues] = useState<Record<string, string>>({})
  const [nominees, setNominees] = useState<Nominee[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    const e = profile.employee as unknown as Record<string, unknown>
    setValues(Object.fromEntries(fields.map((f) => [f.key, (e[f.key] as string | null) ?? ''])))
    setNominees(profile.nominees ?? [])
    setError(null)
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  const submit = async () => {
    setError(null)
    if (values.full_name !== undefined && values.full_name.trim().length < 2) return setError('Full name is required')
    if (values.phone && !normalizeBdPhone(values.phone)) return setError('Phone: use 01XXXXXXXXX')
    if (values.nid_number && !/^(\d{10}|\d{13}|\d{17})$/.test(values.nid_number)) return setError('NID must be 10, 13 or 17 digits')
    const e = profile.employee as unknown as Record<string, unknown>
    const p: Record<string, unknown> = {}
    for (const f of fields) if ((values[f.key] ?? '') !== ((e[f.key] as string | null) ?? '')) p[f.key] = values[f.key]
    if (canNominees) {
      const clean = nominees.filter((n) => n.name.trim())
      if (clean.some((n) => n.relation.trim().length < 2)) return setError('Each nominee needs a relation')
      if (JSON.stringify(clean) !== JSON.stringify(profile.nominees ?? [])) p.nominees = clean.map(({ name, relation, phone }) => ({ name, relation, phone }))
    }
    if (Object.keys(p).length === 0) return onClose()
    try {
      await update.mutateAsync({ p_employee_id: profile.employee.id, p })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      title="Edit employee"
      description="Only the fields your role may edit are shown."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button loading={update.isPending} onClick={submit}>Save</Button>
        </>
      }
    >
      <div className="space-y-5">
        {error && <Alert>{error}</Alert>}
        {fields.length === 0 && !canNominees && <p className="text-sm text-slate-500">Your role cannot edit any field here.</p>}
        <div className="grid gap-4 sm:grid-cols-2">
          {fields.map((f) => {
            const common = { name: f.key, value: values[f.key] ?? '' }
            const set = (v: string) => setValues((s) => ({ ...s, [f.key]: v }))
            if (f.type === 'select') return <Select key={f.key} {...common} label={f.label} options={f.options!} placeholder="—" onChange={(e) => set(e.target.value)} />
            if (f.type === 'textarea') return <Textarea key={f.key} {...common} label={f.label} onChange={(e) => set(e.target.value)} />
            return <Input key={f.key} {...common} label={f.label} type={f.type ?? 'text'} onChange={(e) => set(e.target.value)} />
          })}
        </div>
        {canNominees && (
          <div>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-medium text-slate-700">Nominees</p>
              <Button variant="ghost" onClick={() => setNominees([...nominees, { name: '', relation: '', phone: '' }])}>
                <Plus className="size-4" /> Add
              </Button>
            </div>
            <div className="space-y-2">
              {nominees.map((n, i) => (
                <div key={i} className="grid gap-2 sm:grid-cols-[1fr_1fr_1fr_auto]">
                  {(['name', 'relation', 'phone'] as const).map((k) => (
                    <input
                      key={k}
                      value={n[k] ?? ''}
                      placeholder={k[0].toUpperCase() + k.slice(1)}
                      aria-label={`Nominee ${i + 1} ${k}`}
                      onChange={(e) => setNominees(nominees.map((x, j) => (j === i ? { ...x, [k]: e.target.value } : x)))}
                      className="rounded-xl border border-slate-300 px-3 py-2 text-sm outline-none focus:border-primary-500"
                    />
                  ))}
                  <button onClick={() => setNominees(nominees.filter((_, j) => j !== i))} className="rounded-lg p-2 text-slate-400 hover:text-red-600" aria-label="Remove nominee">
                    <Trash2 className="size-4" />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </Modal>
  )
}

// --------------------------------------------------------------- transfer --
export function TransferDialog({ profile, open, onClose, structure }: DialogProps & { structure: OrgStructure }) {
  const transfer = useHrAction<{ p_employee_id: string; p: Record<string, unknown> }, string>('transfer_employee')
  const e = profile.employee
  const [v, setV] = useState({ department_id: '', designation_id: '', branch_id: '', office_id: '', operation_id: '', effective_date: today(), reason: '' })
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setV({
      department_id: e.department_id ?? '', designation_id: e.designation_id ?? '', branch_id: e.branch_id ?? '',
      office_id: e.office_id ?? '', operation_id: e.operation_id ?? '', effective_date: today(), reason: '',
    })
    setError(null)
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  const s = structure
  const active = <T extends { status: string }>(xs: T[]) => xs.filter((x) => x.status === 'active')
  const gradeCode = (id: string) => s.grades.find((g) => g.id === id)?.code ?? '—'
  const officeOps = new Set(s.officeOperations.filter((x) => x.office_id === v.office_id).map((x) => x.operation_id))

  const submit = async () => {
    setError(null)
    try {
      await transfer.mutateAsync({ p_employee_id: e.id, p: v })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      title="Transfer or promote"
      description="A higher grade is recorded as a promotion; a new department, branch or office as a transfer."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button loading={transfer.isPending} onClick={submit}>Save change</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {error && <div className="sm:col-span-2"><Alert>{error}</Alert></div>}
        <Select label="Department" value={v.department_id} options={active(s.departments).map((d) => ({ value: d.id, label: d.name }))}
          onChange={(ev) => setV({ ...v, department_id: ev.target.value, designation_id: '' })} placeholder="Select…" />
        <Select label="Designation" value={v.designation_id}
          options={active(s.designations).filter((d) => d.department_id === v.department_id).map((d) => ({ value: d.id, label: `${d.name} (${gradeCode(d.grade_id)})` }))}
          onChange={(ev) => setV({ ...v, designation_id: ev.target.value })} placeholder="Select…" />
        <Select label="Branch" value={v.branch_id} options={active(s.branches).map((b) => ({ value: b.id, label: b.name }))}
          onChange={(ev) => setV({ ...v, branch_id: ev.target.value, office_id: '', operation_id: '' })} placeholder="Select…" />
        <Select label="Office" value={v.office_id}
          options={active(s.offices).filter((o) => o.branch_id === v.branch_id).map((o) => ({ value: o.id, label: o.name }))}
          onChange={(ev) => setV({ ...v, office_id: ev.target.value, operation_id: '' })} placeholder="Select…" />
        <Select label="Operation" value={v.operation_id}
          options={active(s.operations).filter((o) => officeOps.has(o.id)).map((o) => ({ value: o.id, label: o.name }))}
          onChange={(ev) => setV({ ...v, operation_id: ev.target.value })} placeholder="None" />
        <Input label="Effective date" type="date" name="effective_date" value={v.effective_date} onChange={(ev) => setV({ ...v, effective_date: ev.target.value })} />
        <Textarea label="Reason" className="sm:col-span-2" value={v.reason} onChange={(ev) => setV({ ...v, reason: ev.target.value })} />
      </div>
    </Modal>
  )
}

// ------------------------------------------------------------- reporting --
export function ReportingDialog({ profile, open, onClose }: DialogProps) {
  const setLine = useHrAction<{ p_employee_id: string; p_line_type: string; p_manager_id: string | null; p_effective_date: string; p_reason: string }>('set_reporting_line')
  const managers = useEmployeeOptions(open)
  const [lineType, setLineType] = useState('reporting_manager')
  const [manager, setManager] = useState('')
  const [effective, setEffective] = useState(today())
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const current = profile.reporting?.find((r) => r.line_type === lineType && !r.end_date)

  useEffect(() => {
    if (open) {
      setManager('')
      setReason('')
      setEffective(today())
      setError(null)
    }
  }, [open])

  const submit = async (clear = false) => {
    setError(null)
    try {
      await setLine.mutateAsync({
        p_employee_id: profile.employee.id,
        p_line_type: lineType,
        p_manager_id: clear ? null : manager || null,
        p_effective_date: effective,
        p_reason: reason,
      })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Change reporting line"
      description="The current line is closed and kept in history; a new one starts on the effective date."
      footer={
        <>
          {current && <Button variant="ghost" onClick={() => submit(true)} loading={setLine.isPending}>Remove current</Button>}
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button disabled={!manager} loading={setLine.isPending} onClick={() => submit()}>Save</Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Line type" value={lineType} onChange={(e) => setLineType(e.target.value)} options={LINE_TYPES} />
        <p className="text-sm text-slate-500">
          Current: <span className="font-medium text-slate-800">{current ? `${current.manager_name} (${current.manager_card_id})` : 'none'}</span>
        </p>
        <Select
          label="New manager"
          value={manager}
          onChange={(e) => setManager(e.target.value)}
          options={(managers.data ?? []).filter((m) => m.id !== profile.employee.id).map((m) => ({ value: m.id, label: `${m.full_name} (${m.card_id})` }))}
          placeholder="Select…"
        />
        <Input label="Effective date" type="date" name="reporting_effective" value={effective} onChange={(e) => setEffective(e.target.value)} />
        <Textarea label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}

// ------------------------------------------------------- deactivate / back --
export function StatusDialog({ profile, open, onClose, structure }: DialogProps & { structure: OrgStructure }) {
  const e = profile.employee
  const deactivate = useHrAction('deactivate_employee')
  const reactivate = useHrAction('reactivate_employee')
  const [status, setStatus] = useState('inactive')
  const [exitDate, setExitDate] = useState(today())
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const isActive = e.status === 'active'

  useEffect(() => {
    if (open) {
      setReason('')
      setError(null)
      setExitDate(today())
    }
  }, [open])

  // Reactivation needs a placement if the old one is inactive.
  const placementOk =
    structure.departments.find((d) => d.id === e.department_id)?.status !== 'inactive' &&
    structure.designations.find((d) => d.id === e.designation_id)?.status !== 'inactive' &&
    structure.branches.find((b) => b.id === e.branch_id)?.status !== 'inactive' &&
    structure.offices.find((o) => o.id === e.office_id)?.status !== 'inactive'

  const submit = async () => {
    setError(null)
    if (!reason.trim()) return setError('A reason is required')
    try {
      if (isActive) await deactivate.mutateAsync({ p_employee_id: e.id, p_status: status, p_exit_date: exitDate, p_reason: reason })
      else await reactivate.mutateAsync({ p_employee_id: e.id, p_reason: reason, p: {} })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="sm"
      title={isActive ? 'Deactivate employee' : 'Reactivate employee'}
      description={e.full_name}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant={isActive ? 'danger' : 'primary'} loading={deactivate.isPending || reactivate.isPending} onClick={submit}>
            {isActive ? 'Deactivate' : 'Reactivate'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        {isActive ? (
          <>
            <Alert tone="info">Their portal access is revoked immediately and their reporting lines are closed. Nothing is deleted.</Alert>
            <Select label="New status" value={status} onChange={(ev) => setStatus(ev.target.value)} options={[{ value: 'inactive', label: 'Inactive' }, { value: 'terminated', label: 'Terminated' }]} />
            <Input label="Exit date" type="date" name="exit_date" value={exitDate} onChange={(ev) => setExitDate(ev.target.value)} />
          </>
        ) : (
          !placementOk && <Alert>Their old department, designation, branch or office is inactive. Reactivation will fail until it is active again.</Alert>
        )}
        <Textarea label="Reason" value={reason} onChange={(ev) => setReason(ev.target.value)} />
      </div>
    </Modal>
  )
}

// ------------------------------------------------------------ portal access --
export function PortalDialog({ profile, open, onClose }: DialogProps) {
  const ctx = useMyContext()
  const isAdmin = ctx.role?.system_key === 'admin'
  const canPortal = ctx.permissions.includes('employees.portal_access')
  const canReset = ctx.permissions.includes('users.reset_password')
  const roles = useRolesData()
  const grant = useHrAction('grant_portal_access')
  const revoke = useHrAction('revoke_portal_access')
  const changeRole = useHrAction('change_portal_role')
  const reset = useHrAction('reset_user_password')
  const e = profile.employee
  const p = profile.portal
  const hasAccess = e.has_portal_access

  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [roleId, setRoleId] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setEmail(p?.email ?? e.email ?? '')
    setPhone(p?.phone ?? e.phone ?? '')
    setPassword('')
    setRoleId(e.portal_role_id ?? '')
    setError(null)
    setDone(null)
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  const roleOptions = (roles.data?.roles ?? [])
    .filter((r) => r.status === 'active' && (isAdmin || r.system_key === 'employee'))
    .map((r) => ({ value: r.id, label: r.name }))

  const run = async (fn: () => Promise<unknown>, message: string) => {
    setError(null)
    setDone(null)
    try {
      await fn()
      setDone(message)
      setPassword('')
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  const passwordOk = passwordRule.test(password)

  return (
    <Modal open={open} onClose={onClose} title="Portal access" description={e.full_name} size="md" footer={<Button variant="secondary" onClick={onClose}>Close</Button>}>
      <div className="space-y-5">
        {error && <Alert>{error}</Alert>}
        {done && <Alert tone="success">{done}</Alert>}

        {!hasAccess ? (
          canPortal ? (
            <div className="space-y-4">
              <p className="text-sm text-slate-600">
                Create a login with a first password. They log in with email or mobile and must change the password at first login.
              </p>
              <div className="grid gap-4 sm:grid-cols-2">
                <Input label="Login email" name="portal_email" type="email" value={email} onChange={(ev) => setEmail(ev.target.value)} />
                <Input label="Login mobile" name="portal_phone" placeholder="01XXXXXXXXX" value={phone} onChange={(ev) => setPhone(ev.target.value)} />
                <Input label="First password" name="portal_password" autoComplete="off" hint={passwordRule.message} value={password} onChange={(ev) => setPassword(ev.target.value)} />
                <Select label="Role" value={roleId} onChange={(ev) => setRoleId(ev.target.value)} options={roleOptions} placeholder="Employee" />
              </div>
              <div className="flex justify-end">
                <Button
                  loading={grant.isPending}
                  disabled={!passwordOk || (!email && !phone)}
                  onClick={() => run(() => grant.mutateAsync({
                    p_employee_id: e.id, p_email: email || null, p_phone: phone || null, p_password: password, p_role_id: roleId || null,
                  }), 'Portal access given. Share the first password with them privately.')}
                >
                  Give portal access
                </Button>
              </div>
            </div>
          ) : (
            <p className="text-sm text-slate-500">This employee has no login.</p>
          )
        ) : (
          <div className="space-y-5">
            <dl className="grid grid-cols-2 gap-3 rounded-xl bg-slate-50 p-4 text-sm">
              <dt className="text-slate-500">Login</dt><dd className="text-slate-800">{p?.email ?? p?.phone ?? '—'}</dd>
              <dt className="text-slate-500">Role</dt><dd className="text-slate-800">{e.portal_role_name}</dd>
              <dt className="text-slate-500">Last login</dt><dd className="text-slate-800">{p?.last_login_at ? new Date(p.last_login_at).toLocaleString() : 'Never'}</dd>
              <dt className="text-slate-500">Password</dt><dd className="text-slate-800">{p?.must_change_password ? 'Must change at next login' : 'Set by user'}</dd>
            </dl>

            {isAdmin && !e.is_self && (
              <div className="flex items-end gap-2">
                <Select className="flex-1" label="Change role" value={roleId} onChange={(ev) => setRoleId(ev.target.value)} options={roleOptions} />
                <Button variant="secondary" loading={changeRole.isPending} disabled={!roleId || roleId === e.portal_role_id}
                  onClick={() => run(() => changeRole.mutateAsync({ p_employee_id: e.id, p_role_id: roleId }), 'Role changed. It applies on their next request.')}>
                  Apply
                </Button>
              </div>
            )}

            {canReset && !e.is_self && (
              <div className="flex items-end gap-2">
                <Input className="flex-1" label="Reset password" name="reset_password" autoComplete="off" placeholder="New first password" hint={passwordRule.message}
                  value={password} onChange={(ev) => setPassword(ev.target.value)} />
                <Button variant="secondary" loading={reset.isPending} disabled={!passwordOk}
                  onClick={() => run(() => reset.mutateAsync({ p_employee_id: e.id, p_new_password: password }), 'Password reset. They are signed out and must change it at next login.')}>
                  Reset
                </Button>
              </div>
            )}

            {canPortal && !e.is_self && (
              <div className="flex items-center justify-between rounded-xl border border-red-200 p-4">
                <div>
                  <p className="text-sm font-medium text-slate-900">Revoke access</p>
                  <p className="text-xs text-slate-500">Stops their login immediately. The employee record stays.</p>
                </div>
                <Button variant="danger" loading={revoke.isPending}
                  onClick={() => confirm(`Revoke portal access for ${e.full_name}?`) && run(() => revoke.mutateAsync({ p_employee_id: e.id, p_reason: null }), 'Portal access revoked.')}>
                  Revoke
                </Button>
              </div>
            )}
          </div>
        )}
      </div>
    </Modal>
  )
}
