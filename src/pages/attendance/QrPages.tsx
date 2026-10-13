import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import QRCode from 'qrcode'
import { CheckCircle2, XCircle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { useInvalidateTime } from '@/lib/time'
import { useOrgStructure } from '@/lib/hr'
import { Alert, Button, Card, Spinner } from '@/components/ui'

/** Full-screen rotating QR for an office (kiosk/monitor). The code is a link to /attendance/qr. */
export function QrDisplayPage() {
  const { officeId } = useParams()
  const structure = useOrgStructure()
  const [img, setImg] = useState<string | null>(null)
  const [until, setUntil] = useState<number>(0)
  const [now, setNow] = useState(Date.now())
  const [error, setError] = useState<string | null>(null)
  const timer = useRef<number | undefined>(undefined)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('issue_qr_code', { p_office_id: officeId })
    if (error) {
      setError(errorMessage(error))
      timer.current = window.setTimeout(refresh, 10_000)
      return
    }
    setError(null)
    const { code, valid_until } = data as { code: string; valid_until: string }
    const url = `${window.location.origin}/attendance/qr?c=${encodeURIComponent(code)}`
    setImg(await QRCode.toDataURL(url, { margin: 1, width: 640, errorCorrectionLevel: 'M' }))
    const end = new Date(valid_until).getTime()
    setUntil(end)
    timer.current = window.setTimeout(refresh, Math.max(5_000, end - Date.now() - 3_000))
  }, [officeId])

  useEffect(() => {
    refresh()
    const tick = window.setInterval(() => setNow(Date.now()), 1000)
    return () => {
      window.clearTimeout(timer.current)
      window.clearInterval(tick)
    }
  }, [refresh])

  const office = structure.data?.offices.find((o) => o.id === officeId)
  const secs = Math.max(0, Math.round((until - now) / 1000))

  return (
    <div className="flex min-h-[80vh] flex-col items-center justify-center gap-6 text-center">
      <div>
        <h2 className="text-2xl font-semibold text-slate-900 sm:text-3xl">Scan to check in or out</h2>
        <p className="mt-1 text-slate-500">{office?.name ?? 'Office'} · open your phone camera and scan</p>
      </div>
      {error && <Alert>{error}</Alert>}
      <Card className="p-4">
        {img ? <img src={img} alt="Check-in QR code" className="size-[min(80vw,420px)]" /> : <div className="flex size-[min(80vw,420px)] items-center justify-center"><Spinner className="size-10" /></div>}
      </Card>
      <p className="text-sm text-slate-500">New code in {secs}s. A photo of an old code will not work.</p>
    </div>
  )
}

/** Opened from the scanned QR link: punches with the code and shows the result. */
export function QrCheckinPage() {
  const [params] = useSearchParams()
  const code = params.get('c') ?? ''
  const invalidate = useInvalidateTime()
  const [state, setState] = useState<{ ok: boolean; text: string } | null>(null)
  const sent = useRef(false)

  useEffect(() => {
    if (sent.current || !code) return
    sent.current = true
    supabase.rpc('punch', { p_source: 'qr', p_qr_code: code }).then(({ error }) => {
      setState(error ? { ok: false, text: errorMessage(error) } : { ok: true, text: `Punch saved at ${new Date().toLocaleTimeString()}.` })
      invalidate()
    })
  }, [code, invalidate])

  return (
    <div className="mx-auto flex min-h-[60vh] max-w-md flex-col items-center justify-center gap-4 text-center">
      {!code ? (
        <Alert>No QR code in the link. Scan the code shown at the office.</Alert>
      ) : !state ? (
        <><Spinner className="size-10 text-primary-600" /><p className="text-slate-600">Saving your punch…</p></>
      ) : state.ok ? (
        <><CheckCircle2 className="size-16 text-green-600" /><p className="text-lg font-medium text-slate-900">{state.text}</p></>
      ) : (
        <><XCircle className="size-16 text-red-600" /><p className="text-lg font-medium text-slate-900">{state.text}</p></>
      )}
      <Link to="/attendance/me"><Button variant="secondary">My attendance</Button></Link>
    </div>
  )
}
