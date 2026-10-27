import { useMemo, useState } from 'react'
import { Paperclip, X } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { useEmployeeOptions, useOrgStructure } from '@/lib/hr'
import { Alert, Button, Input, cx } from '@/components/ui'
import { Checkbox, Label, Modal, Select, Switch } from '@/components/kit'
import { RichTextEditor } from '../../shared/RichText'
import type { Audience, NoticeCategory, NoticeDraft } from '../core/notices'
import {
  AUDIENCE_LABEL, CATEGORIES, CATEGORY_LABEL, EMPTY_DRAFT, ackByDefault, draftProblems, fromLocalInput, toLocalInput,
} from '../core/notices'
import type { ManagedNotice, SaveResult } from '../data/api'
import { useSaveNotice } from '../data/api'

function draftOf(n: ManagedNotice | null): NoticeDraft {
  if (!n) return EMPTY_DRAFT
  return {
    category: n.category, title: n.title, title_bn: n.title_bn ?? '', body: n.body, body_bn: n.body_bn ?? '', audience: n.audience,
    department_ids: n.department_ids, branch_ids: n.branch_ids, employee_ids: n.employee_ids, pinned: n.pinned,
    requires_ack: n.requires_ack, email_copy: n.email_copy, publish_now: !n.publish_at || n.status !== 'draft',
    publish_at: toLocalInput(n.publish_at), expires_at: toLocalInput(n.expires_at),
  }
}

/** Multi-select as a scrollable checkbox list with a filter (departments, branches, employees). */
function PickList({ label, options, value, onChange, error }: {
  label: string; options: { id: string; label: string }[]; value: string[]; onChange: (v: string[]) => void; error?: string
}) {
  const [filter, setFilter] = useState('')
  const shown = options.filter((o) => o.label.toLowerCase().includes(filter.toLowerCase()))
  return (
    <div>
      <Label>{label} <span className="font-normal text-slate-400">({value.length} chosen)</span></Label>
      {options.length > 8 && (
        <input type="search" aria-label={`Filter ${label}`} placeholder="Filter…" value={filter} onChange={(e) => setFilter(e.target.value)}
          className="mb-2 w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
      )}
      <div className={cx('max-h-48 space-y-1.5 overflow-y-auto rounded-xl p-3 ring-1', error ? 'ring-red-300' : 'ring-slate-200')}>
        {shown.length === 0 && <p className="text-sm text-slate-400">Nothing found</p>}
        {shown.map((o) => (
          <div key={o.id}>
            <Checkbox label={o.label} checked={value.includes(o.id)}
              onChange={(v) => onChange(v ? [...value, o.id] : value.filter((x) => x !== o.id))} />
          </div>
        ))}
      </div>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </div>
  )
}

/**
 * New / edit notice. Publishers with notices.manage choose the audience; Managers always send to
 * their own department (the database fills it in).
 */
export function NoticeForm({ open, notice, canTargetAll, myDepartment, orgId, onClose, onDone }: {
  open: boolean; notice: ManagedNotice | null; canTargetAll: boolean; myDepartment: string | null; orgId: string
  onClose: () => void; onDone: (r: SaveResult) => void
}) {
  const [d, setD] = useState<NoticeDraft>(() => draftOf(notice))
  const [file, setFile] = useState<File | null>(null)
  const [removeFile, setRemoveFile] = useState(false)
  const [showBangla, setShowBangla] = useState(!!(notice?.title_bn || notice?.body_bn))
  const [tried, setTried] = useState(false)
  const structure = useOrgStructure()
  const people = useEmployeeOptions(canTargetAll && d.audience === 'employees')
  const save = useSaveNotice()
  const isDraft = !notice || notice.status === 'draft'
  const problems = draftProblems(d, canTargetAll)
  const set = (patch: Partial<NoticeDraft>) => setD({ ...d, ...patch })

  const departments = useMemo(() => (structure.data?.departments ?? []).filter((x) => x.status === 'active').map((x) => ({ id: x.id, label: x.name })), [structure.data])
  const branches = useMemo(() => (structure.data?.branches ?? []).filter((x) => x.status === 'active').map((x) => ({ id: x.id, label: x.name })), [structure.data])
  const employees = useMemo(() => (people.data ?? []).map((e) => ({ id: e.id, label: `${e.full_name} · ${e.card_id}` })), [people.data])

  const submit = (publish: boolean) => {
    setTried(true)
    if (Object.keys(problems).length) return
    const payload = {
      category: d.category, title: d.title.trim(), title_bn: showBangla ? d.title_bn.trim() : '', body: d.body,
      body_bn: showBangla ? d.body_bn : '', audience: d.audience, department_ids: d.department_ids, branch_ids: d.branch_ids,
      employee_ids: d.employee_ids, pinned: d.pinned, requires_ack: d.requires_ack, email_copy: d.email_copy,
      publish_at: d.publish_now ? null : fromLocalInput(d.publish_at), expires_at: fromLocalInput(d.expires_at),
    }
    save.mutate({ id: notice?.id ?? null, payload, file, removeFile, orgId, publish }, { onSuccess: onDone })
  }
  const err = (k: keyof NoticeDraft) => (tried ? problems[k] : undefined)

  return (
    <Modal open={open} onClose={onClose} size="xl" title={notice ? 'Edit notice' : 'New notice'}
      description={!canTargetAll ? `Goes to your department${myDepartment ? `: ${myDepartment}` : ''}.` : undefined}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        {isDraft && <Button variant="secondary" loading={save.isPending} onClick={() => submit(false)}>Save draft</Button>}
        <Button loading={save.isPending} onClick={() => submit(isDraft)}>
          {!isDraft ? 'Save changes' : d.publish_now ? 'Publish now' : 'Schedule'}
        </Button>
      </>}>
      <div className="space-y-5">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <div className="grid gap-4 sm:grid-cols-[1fr_220px]">
          <Input label="Title" name="notice_title" value={d.title} maxLength={200} error={err('title')}
            onChange={(e) => set({ title: e.target.value })} />
          <Select label="Category" name="notice_category" value={d.category}
            onChange={(e) => {
              const category = e.target.value as NoticeCategory
              set({ category, requires_ack: isDraft ? ackByDefault(category) || (d.requires_ack && !ackByDefault(d.category)) : d.requires_ack })
            }}
            options={CATEGORIES.map((c) => ({ value: c, label: CATEGORY_LABEL[c].label }))} />
        </div>
        <RichTextEditor id="notice_body" label="Notice text" required value={d.body} onChange={(body) => set({ body })}
          hint={err('body') ?? 'Bold, italic, lists, headings and links. Plain text is fine too.'} />

        <div className="rounded-xl ring-1 ring-slate-200">
          <div className="flex items-center justify-between gap-3 p-3">
            <div>
              <p className="text-sm font-medium text-slate-800">বাংলা version</p>
              <p className="text-xs text-slate-500">Readers can switch between English and Bangla.</p>
            </div>
            <Switch label="Add a Bangla version" checked={showBangla} onChange={setShowBangla} />
          </div>
          {showBangla && (
            <div className="space-y-4 border-t border-slate-100 p-3">
              <Input label="শিরোনাম (Bangla title)" name="notice_title_bn" lang="bn" value={d.title_bn} maxLength={200} error={err('title_bn')}
                onChange={(e) => set({ title_bn: e.target.value })} />
              <RichTextEditor id="notice_body_bn" label="বিস্তারিত (Bangla text)" lang="bn" rows={6} value={d.body_bn} onChange={(body_bn) => set({ body_bn })} />
            </div>
          )}
        </div>

        {canTargetAll && (
          <div className="space-y-3">
            <div>
              <Label>Who should see it</Label>
              <div className="grid gap-2 sm:grid-cols-4" role="radiogroup" aria-label="Audience">
                {(Object.keys(AUDIENCE_LABEL) as Audience[]).map((a) => (
                  <button key={a} type="button" role="radio" aria-checked={d.audience === a} onClick={() => set({ audience: a })}
                    className={cx('rounded-xl p-2.5 text-left text-sm ring-1',
                      d.audience === a ? 'bg-primary-50 font-medium text-primary-800 ring-2 ring-primary-500' : 'text-slate-700 ring-slate-200 hover:bg-slate-50')}>
                    {AUDIENCE_LABEL[a]}
                  </button>
                ))}
              </div>
            </div>
            {d.audience === 'department' && <PickList label="Departments" options={departments} value={d.department_ids} onChange={(v) => set({ department_ids: v })} error={err('department_ids')} />}
            {d.audience === 'branch' && <PickList label="Branches" options={branches} value={d.branch_ids} onChange={(v) => set({ branch_ids: v })} error={err('branch_ids')} />}
            {d.audience === 'employees' && <PickList label="Employees" options={employees} value={d.employee_ids} onChange={(v) => set({ employee_ids: v })} error={err('employee_ids')} />}
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-3">
            {isDraft && (
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-medium text-slate-800">Publish immediately</p>
                <Switch label="Publish immediately" checked={d.publish_now} onChange={(publish_now) => set({ publish_now })} />
              </div>
            )}
            {isDraft && !d.publish_now && (
              <Input label="Publish at" name="notice_publish_at" type="datetime-local" value={d.publish_at} error={err('publish_at')}
                onChange={(e) => set({ publish_at: e.target.value })} />
            )}
            <Input label="Expires at (optional)" name="notice_expires_at" type="datetime-local" value={d.expires_at} error={err('expires_at')}
              onChange={(e) => set({ expires_at: e.target.value })} />
          </div>
          <div className="space-y-3">
            {[
              { k: 'pinned' as const, label: 'Pin this notice', hint: 'Shown first and on the dashboard', disabled: false },
              { k: 'requires_ack' as const, label: 'Require acknowledgement', hint: '"I have read and agree"', disabled: false },
              { k: 'email_copy' as const, label: 'Send an email copy', hint: isDraft ? 'Through the company email channel' : 'Set when publishing', disabled: !isDraft },
            ].map((o) => (
              <div key={o.k} className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-medium text-slate-800">{o.label}</p>
                  <p className="text-xs text-slate-500">{o.hint}</p>
                </div>
                <Switch label={o.label} checked={d[o.k]} disabled={o.disabled} onChange={(v) => set({ [o.k]: v })} />
              </div>
            ))}
          </div>
        </div>

        <div>
          <Label>Attachment (optional)</Label>
          {(file || (notice?.attachment_name && !removeFile)) ? (
            <div className="flex items-center gap-3 rounded-xl p-3 text-sm ring-1 ring-slate-200">
              <Paperclip className="size-4 text-primary-600" aria-hidden />
              <span className="flex-1 truncate">{file?.name ?? notice?.attachment_name}</span>
              <button type="button" aria-label="Remove the file" className="rounded-lg p-1 text-slate-400 hover:bg-slate-100"
                onClick={() => { if (file) setFile(null); else setRemoveFile(true) }}>
                <X className="size-4" />
              </button>
            </div>
          ) : (
            <input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" aria-label="Attachment"
              onChange={(e) => { setFile(e.target.files?.[0] ?? null); setRemoveFile(false) }}
              className="block w-full text-sm text-slate-600 file:mr-3 file:rounded-lg file:border-0 file:bg-primary-50 file:px-3 file:py-2 file:text-sm file:font-medium file:text-primary-700" />
          )}
          <p className="mt-1 text-xs text-slate-500">PDF or image, up to 10 MB.</p>
        </div>
      </div>
    </Modal>
  )
}
