import { useEffect, useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { useOrgSettings, useSettingsSave } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { useSession } from '@/stores/session'
import { Alert, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { PageHeader, Select } from '@/components/kit'

const TIMEZONES = ['Asia/Dhaka', 'Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore', 'Europe/London', 'UTC'].map((t) => ({ value: t, label: t }))

export default function SettingsPage() {
  const ctx = useMyContext()
  const settings = useOrgSettings(ctx.organization?.id)
  const save = useSettingsSave()
  const refreshContext = useSession((s) => s.refreshContext)
  const [name, setName] = useState('')
  const [timezone, setTimezone] = useState('Asia/Dhaka')
  const [mode, setMode] = useState<'auto' | 'custom'>('auto')
  const [length, setLength] = useState(8)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    if (!settings.data) return
    setName(settings.data.name)
    setTimezone(settings.data.timezone)
    setMode(settings.data.card_id_mode)
    setLength(settings.data.card_id_length)
  }, [settings.data])

  if (settings.isPending) return <PageLoader />
  if (settings.isError) return <Alert>{errorMessage(settings.error)}</Alert>

  const year = new Date().getFullYear().toString().slice(2)
  const example = year + '4827193051'.slice(0, length - 2)

  const submit = async () => {
    setSaved(false)
    await save.mutateAsync({
      id: settings.data.id,
      values: { name: name.trim(), timezone, card_id_mode: mode, card_id_length: length },
    })
    await refreshContext()
    setSaved(true)
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader title="Settings" description="Organization details and the employee card ID policy." />

      <Card className="space-y-4">
        <h3 className="font-semibold text-slate-900">Organization</h3>
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Organization name" name="org_name" value={name} onChange={(e) => setName(e.target.value)} />
          <Input label="Organization code" name="org_code" value={settings.data.org_code} disabled hint="Generated once; never changes" />
          <Select label="Timezone" name="timezone" value={timezone} onChange={(e) => setTimezone(e.target.value)} options={TIMEZONES} />
        </div>
      </Card>

      <Card className="space-y-4">
        <div>
          <h3 className="font-semibold text-slate-900">Card ID policy</h3>
          <p className="text-sm text-slate-500">
            Card IDs are for ID cards, QR and display only — never for login. Unique inside this organization.
          </p>
        </div>
        <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="Card ID mode">
          {(['auto', 'custom'] as const).map((m) => (
            <button
              key={m}
              role="radio"
              aria-checked={mode === m}
              onClick={() => setMode(m)}
              className={cx(
                'rounded-xl border p-4 text-left transition',
                mode === m ? 'border-primary-500 bg-primary-50 ring-2 ring-primary-100' : 'border-slate-200 hover:bg-slate-50',
              )}
            >
              <p className="font-medium text-slate-900">{m === 'auto' ? 'Automatic' : 'Custom'}</p>
              <p className="mt-1 text-sm text-slate-500">
                {m === 'auto'
                  ? 'Joining year (2 digits) + random digits. Safe when two people are added at once.'
                  : 'HR types each ID: 6–15 letters, numbers or hyphens. Duplicates are rejected.'}
              </p>
            </button>
          ))}
        </div>
        {mode === 'auto' && (
          <div className="flex flex-wrap items-end gap-4">
            <Select
              label="Total length"
              name="card_length"
              className="w-40"
              value={String(length)}
              onChange={(e) => setLength(Number(e.target.value))}
              options={[8, 9, 10].map((n) => ({ value: String(n), label: `${n} digits` }))}
            />
            <p className="pb-3 text-sm text-slate-500">
              Example: <span className="font-mono font-medium text-slate-800">{example}</span>
            </p>
          </div>
        )}
      </Card>

      <div className="flex items-center justify-end gap-3">
        {save.isError && <span className="text-sm text-red-600">{errorMessage(save.error)}</span>}
        {saved && <span className="text-sm text-green-700">Saved</span>}
        <Button loading={save.isPending} onClick={submit}>Save settings</Button>
      </div>
    </div>
  )
}
