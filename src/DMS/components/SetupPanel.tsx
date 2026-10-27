import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Badge, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { Checkbox, Select, Switch, Table, td, th } from '@/components/kit'
import { CLASSIFICATION } from '../core/dms'
import type { Classification, Setup } from '../core/types'
import { useSaveCustodian, useSaveDocType, useSaveFolder, useSaveSettings, useSetProfiles, useSetup } from '../data/api'

/** dms.manage: ISO standards (optional), folders on/off and names, document types, department codes. */
export function SetupPanel() {
  const setup = useSetup(true)
  if (setup.isPending) return <PageLoader />
  if (setup.isError) return <Alert>{errorMessage(setup.error)}</Alert>
  return (
    <div className="space-y-6">
      <IsoCard setup={setup.data} />
      <ReviewCard setup={setup.data} />
      <FoldersCard setup={setup.data} />
      <TypesCard setup={setup.data} />
      <DepartmentsCard setup={setup.data} />
    </div>
  )
}

function IsoCard({ setup }: { setup: Setup }) {
  const save = useSetProfiles()
  const [codes, setCodes] = useState<string[]>(setup.profiles)
  const [noIso, setNoIso] = useState(setup.no_iso)
  const changed = codes.join() !== setup.profiles.join() || noIso !== setup.no_iso
  return (
    <Card className="space-y-4">
      <div>
        <h3 className="text-base font-semibold text-slate-900">1. ISO standards (optional)</h3>
        <p className="text-sm text-slate-500">
          A standard only adds folders and a checklist; files and names never change. Not sure? Licences are already covered by the base
          folders; start with ISO 9001, add 45001 and 14001 for a factory, 27001 if you handle data.
        </p>
      </div>
      <ul className="grid gap-3 md:grid-cols-2">
        {setup.catalog.map((p) => {
          const on = codes.includes(p.code)
          return (
            <li key={p.code}>
              <label className={cx('flex h-full cursor-pointer gap-3 rounded-xl p-3 ring-1 transition', on ? 'bg-primary-50 ring-primary-300' : 'ring-slate-200 hover:ring-slate-300')}>
                <input type="checkbox" className="mt-1 size-4 accent-primary-600" checked={on}
                  onChange={(e) => { setNoIso(false); setCodes(e.target.checked ? [...codes, p.code] : codes.filter((c) => c !== p.code)) }} />
                <span className="text-sm">
                  <span className="font-medium text-slate-900">{p.name}</span> <span className="text-xs text-slate-500">({p.edition})</span>
                  <span className="block text-slate-700">“{p.summary}”</span>
                  <span className="block text-xs text-slate-500">Who needs it: {p.who_needs_it}</span>
                  <span className="block text-xs text-slate-500">Adds: {p.folders.join(', ')}</span>
                </span>
              </label>
            </li>
          )
        })}
      </ul>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Checkbox label="We do not use any ISO standard" checked={noIso && codes.length === 0}
          onChange={(v) => { setNoIso(v); if (v) setCodes([]) }} />
        <Button disabled={!changed} loading={save.isPending} onClick={() => save.mutate({ codes, noIso })}>Save standards</Button>
      </div>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
    </Card>
  )
}

function FoldersCard({ setup }: { setup: Setup }) {
  const save = useSaveFolder()
  const [editing, setEditing] = useState<{ id: string | null; name: string } | null>(null)
  const label = { base: 'Base', iso: 'ISO', custom: 'Custom' } as const
  const visible = setup.folders.filter((f) => f.origin !== 'iso' || f.enabled || f.documents > 0)
  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold text-slate-900">Folders</h3>
          <p className="text-sm text-slate-500">Switch off what your company does not need. A folder that holds documents stays on until they are moved.</p>
        </div>
        <Button variant="secondary" onClick={() => setEditing({ id: null, name: '' })}><Plus className="size-4" /> New folder</Button>
      </div>
      {editing && (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => {
          e.preventDefault()
          save.mutate({ id: editing.id, p: { name: editing.name } }, { onSuccess: () => setEditing(null) })
        }}>
          <Input label={editing.id ? 'Rename folder' : 'New folder name'} value={editing.name} autoFocus className="min-w-60 flex-1"
            onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
          <Button type="submit" loading={save.isPending}>Save</Button>
          <Button type="button" variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
        </form>
      )}
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <ul className="divide-y divide-slate-100 rounded-xl ring-1 ring-slate-200">
        {visible.map((f) => (
          <li key={f.id} className="flex flex-wrap items-center gap-3 px-3 py-2 text-sm">
            <Switch label={`${f.name} on`} checked={f.enabled} disabled={save.isPending}
              onChange={(v) => save.mutate({ id: f.id, p: { enabled: v } })} />
            <span className={cx('font-medium', f.enabled ? 'text-slate-900' : 'text-slate-400')}>{f.name}</span>
            <Badge tone={f.origin === 'custom' ? 'orange' : 'slate'}>{label[f.origin]}{f.profile_code ? ` · ${f.profile_code.replace('_', ' ')}` : ''}</Badge>
            <span className="text-xs text-slate-500">{f.documents} documents</span>
            <button type="button" className="ml-auto text-xs font-medium text-primary-700 hover:underline" onClick={() => setEditing({ id: f.id, name: f.name })}>
              Rename
            </button>
            {f.enabled && <Custodians setup={setup} folderId={f.id} />}
          </li>
        ))}
      </ul>
    </Card>
  )
}

/** The people responsible for a folder: they upload there without a role permission and get its reminders. */
function Custodians({ setup, folderId }: { setup: Setup; folderId: string }) {
  const save = useSaveCustodian()
  const current = setup.custodians.filter((c) => c.folder_id === folderId)
  const others = setup.people.filter((p) => !current.some((c) => c.user_id === p.user_id))
  return (
    <div className="flex w-full flex-wrap items-center gap-2 pl-14 text-xs">
      <span className="text-slate-500">Responsible:</span>
      {current.length === 0 && <span className="text-slate-400">nobody yet</span>}
      {current.map((c) => (
        <span key={c.user_id} className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-slate-700">
          {c.name}
          <button type="button" aria-label={`Remove ${c.name}`} className="text-slate-400 hover:text-red-600"
            onClick={() => save.mutate({ folderId, userId: c.user_id, active: false })}>×</button>
        </span>
      ))}
      <select aria-label="Add a responsible person" className="rounded-lg border border-slate-300 bg-white px-2 py-0.5" value=""
        onChange={(e) => e.target.value && save.mutate({ folderId, userId: e.target.value, active: true })}>
        <option value="">+ Add person</option>
        {others.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
      </select>
      {save.isError && <span className="text-red-600">{errorMessage(save.error)}</span>}
    </div>
  )
}

function ReviewCard({ setup }: { setup: Setup }) {
  const save = useSaveSettings()
  const [review, setReview] = useState(setup.require_review)
  const [days, setDays] = useState(String(setup.review_days))
  const [steps, setSteps] = useState(setup.reminder_days.join(', '))
  return (
    <Card className="space-y-4">
      <div>
        <h3 className="text-base font-semibold text-slate-900">Review and reminders</h3>
        <p className="text-sm text-slate-500">
          Uploads wait for review by the Admin (or someone with “Review documents”) before anyone else sees them. The Admin's own uploads publish
          directly. Nothing is ever approved by itself: past the review period it shows as “Review overdue”.
        </p>
      </div>
      <form className="grid gap-3 sm:grid-cols-3" onSubmit={(e) => {
        e.preventDefault()
        save.mutate({ require_review: review, review_days: Number(days), reminder_days: steps.split(/[ ,]+/).filter(Boolean).map(Number) })
      }}>
        <div className="flex items-center gap-3 sm:col-span-3">
          <Switch label="Review uploads before publishing" checked={review} onChange={setReview} />
          <span className="text-sm text-slate-700">Review uploads before publishing</span>
        </div>
        <Input label="Review period (working days)" type="number" min={1} max={30} value={days} onChange={(e) => setDays(e.target.value)} />
        <Input label="Reminders before expiry / review (days)" value={steps} onChange={(e) => setSteps(e.target.value)} hint="e.g. 60, 30, 7, 0" />
        <div className="flex items-end"><Button type="submit" loading={save.isPending}>Save</Button></div>
      </form>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {save.isSuccess && <Alert tone="success">Saved.</Alert>}
    </Card>
  )
}

function TypesCard({ setup }: { setup: Setup }) {
  const save = useSaveDocType()
  const enabledFolders = setup.folders.filter((f) => f.enabled)
  const [draft, setDraft] = useState<{ code: string; name: string; folder_id: string; has_expiry: boolean; default_classification: Classification } | null>(null)
  const folderName = (id: string) => setup.folders.find((f) => f.id === id)?.name ?? '—'
  const types = setup.types.filter((t) => setup.folders.find((f) => f.id === t.folder_id)?.enabled)
  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold text-slate-900">Document types</h3>
          <p className="text-sm text-slate-500">The type gives the middle part of every code (HR-<b>POL</b>-0012). Codes never change once used.</p>
        </div>
        <Button variant="secondary" onClick={() => setDraft({ code: '', name: '', folder_id: enabledFolders[0]?.id ?? '', has_expiry: false, default_classification: 'internal' })}>
          <Plus className="size-4" /> New type
        </Button>
      </div>
      {draft && (
        <form className="grid gap-3 rounded-xl bg-slate-50 p-3 sm:grid-cols-2" onSubmit={(e) => {
          e.preventDefault()
          save.mutate({ id: null, p: draft }, { onSuccess: () => setDraft(null) })
        }}>
          <Input label="Name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} required />
          <Input label="Code (2–4 letters)" value={draft.code} maxLength={4} required
            onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase().replace(/[^A-Z]/g, '') })} />
          <Select label="Folder" value={draft.folder_id} onChange={(e) => setDraft({ ...draft, folder_id: e.target.value })}
            options={enabledFolders.map((f) => ({ value: f.id, label: f.name }))} />
          <Select label="Default classification" value={draft.default_classification}
            onChange={(e) => setDraft({ ...draft, default_classification: e.target.value as Classification })}
            options={(Object.keys(CLASSIFICATION) as Classification[]).map((k) => ({ value: k, label: CLASSIFICATION[k].label }))} />
          <Checkbox label="Has an expiry date" checked={draft.has_expiry} onChange={(v) => setDraft({ ...draft, has_expiry: v })} />
          <div className="flex justify-end gap-2 sm:col-span-2">
            <Button type="button" variant="ghost" onClick={() => setDraft(null)}>Cancel</Button>
            <Button type="submit" loading={save.isPending}>Add type</Button>
          </div>
        </form>
      )}
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <Table minWidth={720} head={
        <tr><th className={th}>On</th><th className={th}>Type</th><th className={th}>Folder</th><th className={th}>Expiry</th><th className={th}>Default access</th><th className={th}>Documents</th></tr>
      }>
        {types.map((t) => (
          <tr key={t.id}>
            <td className={td}><Switch label={`${t.name} on`} checked={t.active} disabled={save.isPending} onChange={(v) => save.mutate({ id: t.id, p: { active: v } })} /></td>
            <td className={td}><span className="font-medium text-slate-900">{t.name}</span> <span className="font-mono text-xs text-slate-500">{t.code}</span></td>
            <td className={td}>{folderName(t.folder_id)}</td>
            <td className={td}>
              {!t.has_expiry ? '—' : (
                <label className="inline-flex items-center gap-2 text-xs">
                  <input type="checkbox" className="size-4 accent-primary-600" checked={t.expiry_default === 'fiscal_year_end'}
                    onChange={(e) => save.mutate({ id: t.id, p: { expiry_default: e.target.checked ? 'fiscal_year_end' : 'none' } })} />
                  Default 30 June
                </label>
              )}
            </td>
            <td className={td}>
              <select aria-label={`${t.name} default access`} className="rounded-lg border border-slate-300 bg-white px-2 py-1 text-xs"
                value={t.default_classification} onChange={(e) => save.mutate({ id: t.id, p: { default_classification: e.target.value } })}>
                {(Object.keys(CLASSIFICATION) as Classification[]).map((k) => <option key={k} value={k}>{CLASSIFICATION[k].label}</option>)}
              </select>
            </td>
            <td className={td}>{t.documents ?? 0}</td>
          </tr>
        ))}
      </Table>
    </Card>
  )
}

function DepartmentsCard({ setup }: { setup: Setup }) {
  const missing = setup.departments.filter((d) => !d.code)
  return (
    <Card className="space-y-3">
      <h3 className="text-base font-semibold text-slate-900">2. Department codes</h3>
      <p className="text-sm text-slate-500">The department gives the first part of every code (<b>HR</b>-POL-0012).</p>
      {missing.length === 0 ? (
        <Alert tone="success">Every department has a code.</Alert>
      ) : (
        <Alert tone="info">
          Without a code: {missing.map((d) => d.name).join(', ')}.{' '}
          <Link to="/organization" className="font-medium underline">Add codes in Organization → Departments</Link>.
        </Alert>
      )}
      <div className="flex flex-wrap gap-2">
        {setup.departments.map((d) => <Badge key={d.id} tone={d.code ? 'green' : 'red'}>{d.name}: {d.code ?? 'no code'}</Badge>)}
      </div>
    </Card>
  )
}
