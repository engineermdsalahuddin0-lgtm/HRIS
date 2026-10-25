// The offer (/offer/:token), no login: read it, accept or decline; after accepting, the
// pre-joining form on the same page (personal details, NID, nominees, salary account, photo).
// NID and account numbers are never shown back (last 4 only); leaving them empty keeps them.
import { useEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { CheckCircle2, Plus, Trash2 } from 'lucide-react'
import type { PublicOffer } from '@/onboarding-process/core/types'
import { EMPLOYMENT_LABEL } from '@/onboarding-process/core/jobPost'
import { NID_PATTERN } from '@/onboarding-process/core/joining'
import { offerApi } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { formatTaka } from '@/lib/payroll'
import { Alert, Button, Card, Input, PageLoader } from '@/components/ui'
import { Select, Textarea } from '@/components/kit'

type Nominee = { name: string; relation: string; phone: string }

function Shell({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white"><div className="mx-auto flex h-14 max-w-3xl items-center px-4 font-semibold">{title}</div></header>
      <main className="mx-auto max-w-3xl space-y-6 px-4 py-6">{children}</main>
      <footer className="py-6 text-center text-xs text-slate-400">Powered by Olympus HRIS</footer>
    </div>
  )
}

function PrejoiningForm({ token, offer, onSaved }: { token: string; offer: PublicOffer; onSaved: (o: PublicOffer) => void }) {
  const pre = offer.prejoining!
  const d = pre.data
  const editable = pre.status === 'pending' || pre.status === 'returned'
  const photoInput = useRef<HTMLInputElement>(null)
  const [f, setF] = useState({
    father_name: d.father_name ?? '', mother_name: d.mother_name ?? '', date_of_birth: d.date_of_birth ?? '', gender: d.gender ?? '',
    marital_status: d.marital_status ?? '', blood_group: d.blood_group ?? '', religion: d.religion ?? '',
    present_address: d.present_address ?? '', permanent_address: d.permanent_address ?? '',
    emergency_name: d.emergency_name ?? '', emergency_phone: d.emergency_phone ?? '', nid_number: '',
    payment_method: pre.payment_method ?? 'bank', bank_name: pre.bank_name ?? '', branch_name: pre.branch_name ?? '',
    routing_number: pre.routing_number ?? '', account_name: pre.account_name ?? offer.full_name, account_number: '',
    wallet_provider: pre.wallet_provider ?? 'bkash', wallet_number: '',
  })
  const [nominees, setNominees] = useState<Nominee[]>(d.nominees?.length ? d.nominees.map((n) => ({ ...n, phone: n.phone ?? '' })) : [{ name: '', relation: '', phone: '' }])
  const [photo, setPhoto] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const set = (k: keyof typeof f, v: string) => setF((x) => ({ ...x, [k]: v }))

  const submit = async () => {
    setError(null)
    if (f.nid_number && !NID_PATTERN.test(f.nid_number)) return setError('The NID number has 10, 13 or 17 digits')
    if (photo && (!['image/jpeg', 'image/png', 'image/webp'].includes(photo.type) || photo.size > 2 * 1024 * 1024)) return setError('The photo must be JPG, PNG or WEBP, up to 2 MB')
    setBusy(true)
    try {
      if (photo) {
        const ext = photo.type === 'image/png' ? 'png' : photo.type === 'image/webp' ? 'webp' : 'jpg'
        await offerApi.uploadPhoto(await offerApi.photoPath(token, ext), photo)
      }
      await offerApi.submit(token, { ...f, nominees: nominees.filter((n) => n.name.trim()) })
      onSaved(await offerApi.get(token))
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  if (!editable) {
    return (
      <Card className="space-y-2">
        <h2 className="text-lg font-semibold">Pre-joining form</h2>
        <Alert tone="success"><CheckCircle2 className="mr-1 inline size-4" />{pre.status === 'verified' ? 'Checked by HR. See you on your joining day!' : 'Submitted. HR will check it and contact you if anything is missing.'}</Alert>
        <p className="text-sm text-slate-600">Bring the originals of your NID, certificates and two photos on the first day.</p>
      </Card>
    )
  }
  return (
    <Card className="space-y-5">
      <div>
        <h2 className="text-lg font-semibold">Pre-joining form</h2>
        <p className="text-sm text-slate-600">Needed for your employee record, nominee and salary. Your NID and account numbers are stored encrypted.</p>
      </div>
      {pre.status === 'returned' && pre.return_note && <Alert tone="info">HR asked you to fix: {pre.return_note}</Alert>}
      {error && <Alert>{error}</Alert>}
      <fieldset className="grid gap-3 sm:grid-cols-2">
        <legend className="mb-2 text-sm font-semibold text-slate-800">About you</legend>
        <Input label="Father's name" value={f.father_name} onChange={(e) => set('father_name', e.target.value)} />
        <Input label="Mother's name" value={f.mother_name} onChange={(e) => set('mother_name', e.target.value)} />
        <Input label="Date of birth" type="date" value={f.date_of_birth} onChange={(e) => set('date_of_birth', e.target.value)} />
        <Select label="Gender" value={f.gender} placeholder="Prefer not to say" onChange={(e) => set('gender', e.target.value)}
          options={[{ value: 'male', label: 'Male' }, { value: 'female', label: 'Female' }, { value: 'other', label: 'Other' }]} />
        <Select label="Marital status" value={f.marital_status} placeholder="—" onChange={(e) => set('marital_status', e.target.value)}
          options={['single', 'married', 'divorced', 'widowed'].map((v) => ({ value: v, label: v[0].toUpperCase() + v.slice(1) }))} />
        <Select label="Blood group" value={f.blood_group} placeholder="—" onChange={(e) => set('blood_group', e.target.value)}
          options={['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map((v) => ({ value: v, label: v }))} />
        <Input label={pre.nid_last4 ? `NID number (on file: •••• ${pre.nid_last4}; leave empty to keep)` : 'NID number'} inputMode="numeric"
          value={f.nid_number} onChange={(e) => set('nid_number', e.target.value.replace(/\D/g, ''))} autoComplete="off" />
        <Input label="Religion (optional)" value={f.religion} onChange={(e) => set('religion', e.target.value)} />
        <Textarea label="Present address" className="sm:col-span-2" value={f.present_address} maxLength={300} onChange={(e) => set('present_address', e.target.value)} />
        <Textarea label="Permanent address" className="sm:col-span-2" value={f.permanent_address} maxLength={300} onChange={(e) => set('permanent_address', e.target.value)} />
        <Input label="Emergency contact name" value={f.emergency_name} onChange={(e) => set('emergency_name', e.target.value)} />
        <Input label="Emergency contact mobile" type="tel" value={f.emergency_phone} onChange={(e) => set('emergency_phone', e.target.value)} />
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="mb-2 text-sm font-semibold text-slate-800">Nominees (who receives your dues)</legend>
        {nominees.map((n, i) => (
          <div key={i} className="grid gap-2 sm:grid-cols-[1fr_9rem_9rem_auto]">
            <Input label="Name" value={n.name} onChange={(e) => setNominees(nominees.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
            <Input label="Relation" value={n.relation} onChange={(e) => setNominees(nominees.map((x, j) => (j === i ? { ...x, relation: e.target.value } : x)))} />
            <Input label="Mobile" type="tel" value={n.phone} onChange={(e) => setNominees(nominees.map((x, j) => (j === i ? { ...x, phone: e.target.value } : x)))} />
            <Button variant="ghost" className="self-end" aria-label="Remove nominee" disabled={nominees.length === 1}
              onClick={() => setNominees(nominees.filter((_, j) => j !== i))}><Trash2 className="size-4" /></Button>
          </div>
        ))}
        {nominees.length < 5 && <Button variant="secondary" onClick={() => setNominees([...nominees, { name: '', relation: '', phone: '' }])}><Plus className="size-4" />Add nominee</Button>}
      </fieldset>

      <fieldset className="grid gap-3 sm:grid-cols-2">
        <legend className="mb-2 text-sm font-semibold text-slate-800">Salary payment</legend>
        <Select label="Paid by" value={f.payment_method} onChange={(e) => set('payment_method', e.target.value)}
          options={[{ value: 'bank', label: 'Bank account' }, { value: 'mobile_wallet', label: 'Mobile wallet (bKash, Nagad …)' }, { value: 'cash', label: 'Cash' }]} />
        <Input label="Account holder name" value={f.account_name} onChange={(e) => set('account_name', e.target.value)} />
        {f.payment_method === 'bank' && <>
          <Input label="Bank" value={f.bank_name} onChange={(e) => set('bank_name', e.target.value)} />
          <Input label="Branch" value={f.branch_name} onChange={(e) => set('branch_name', e.target.value)} />
          <Input label={pre.payment_method === 'bank' && pre.number_last4 ? `Account number (on file: •••• ${pre.number_last4}; empty keeps it)` : 'Account number'}
            inputMode="numeric" autoComplete="off" value={f.account_number} onChange={(e) => set('account_number', e.target.value.replace(/[^\d]/g, ''))} />
          <Input label="Routing number (9 digits, optional)" inputMode="numeric" value={f.routing_number} onChange={(e) => set('routing_number', e.target.value.replace(/\D/g, ''))} />
        </>}
        {f.payment_method === 'mobile_wallet' && <>
          <Select label="Wallet" value={f.wallet_provider} onChange={(e) => set('wallet_provider', e.target.value)}
            options={['bkash', 'nagad', 'rocket', 'upay', 'other'].map((v) => ({ value: v, label: v === 'bkash' ? 'bKash' : v[0].toUpperCase() + v.slice(1) }))} />
          <Input label={pre.payment_method === 'mobile_wallet' && pre.number_last4 ? `Wallet number (on file: •••• ${pre.number_last4})` : 'Wallet number'} type="tel"
            value={f.wallet_number} onChange={(e) => set('wallet_number', e.target.value)} />
        </>}
      </fieldset>

      <div>
        <span className="mb-1.5 block text-sm font-semibold text-slate-800">Photo (passport size, JPG / PNG, up to 2 MB)</span>
        <input ref={photoInput} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => setPhoto(e.target.files?.[0] ?? null)} />
        <Button variant="secondary" onClick={() => photoInput.current?.click()}>{photo ? photo.name : pre.has_photo ? 'Replace photo (one is on file)' : 'Choose photo'}</Button>
      </div>
      <Button className="w-full sm:w-auto" loading={busy} onClick={submit}>Submit form</Button>
    </Card>
  )
}

export function OfferPage() {
  const { token = '' } = useParams()
  const [offer, setOffer] = useState<PublicOffer | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { offerApi.get(token).then(setOffer).catch((e) => setError(errorMessage(e))) }, [token])

  if (error && !offer) return <Shell title="Job offer"><Alert>{error.includes('not valid') ? 'This offer link is not valid. Please check the link in your email.' : error}</Alert></Shell>
  if (!offer) return <Shell title="Job offer"><PageLoader /></Shell>
  const respond = async (answer: 'accept' | 'decline') => {
    if (answer === 'decline' && !confirm('Decline this offer? This cannot be undone.')) return
    setBusy(true)
    setError(null)
    try { setOffer(await offerApi.respond(token, answer, note)) } catch (e) { setError(errorMessage(e)) } finally { setBusy(false) }
  }

  return (
    <Shell title={`${offer.organization} · Job offer`}>
      <Card className="space-y-4">
        <h1 className="text-xl font-semibold">Dear {offer.full_name},</h1>
        <p className="text-sm text-slate-700">{offer.organization} offers you the position of <b>{offer.designation}</b> in the {offer.department} department, {offer.office}.</p>
        <dl className="grid gap-3 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-2">
          <div><dt className="text-xs text-slate-500">Monthly gross salary</dt><dd className="text-lg font-semibold">{formatTaka(offer.gross)}</dd></div>
          <div><dt className="text-xs text-slate-500">Joining date</dt><dd className="font-medium">{formatDate(offer.joining_date)}</dd></div>
          <div><dt className="text-xs text-slate-500">Employment</dt><dd>{EMPLOYMENT_LABEL[offer.employment_type]}{offer.probation_months ? ` · ${offer.probation_months} months probation` : ''}</dd></div>
          <div><dt className="text-xs text-slate-500">Reply by</dt><dd>{formatDate(offer.expires_on)}</dd></div>
        </dl>
        {offer.terms && <p className="whitespace-pre-wrap text-sm text-slate-700">{offer.terms}</p>}
        {error && <Alert>{error}</Alert>}
        {offer.status === 'sent' ? (
          <>
            <Textarea label="Message to HR (optional)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
            <div className="flex flex-wrap gap-2">
              <Button loading={busy} onClick={() => respond('accept')}>Accept the offer</Button>
              <Button variant="ghost" disabled={busy} onClick={() => respond('decline')}>Decline</Button>
            </div>
          </>
        ) : offer.status === 'accepted' ? <Alert tone="success"><CheckCircle2 className="mr-1 inline size-4" />You accepted this offer. Welcome! Please fill in the pre-joining form below.</Alert>
          : offer.status === 'declined' ? <Alert tone="info">You declined this offer. Thank you for letting us know.</Alert>
            : <Alert tone="info">This offer has expired. Please contact {offer.organization}.</Alert>}
      </Card>
      {offer.status === 'accepted' && offer.prejoining && <PrejoiningForm token={token} offer={offer} onSaved={setOffer} />}
    </Shell>
  )
}
