import { useEffect, useState } from 'react'
import QRCode from 'qrcode'
import { Printer } from 'lucide-react'
import type { EmployeeProfile } from '@/lib/hr'
import { idCardQrPayload, useEmployeeFiles, useOrgLogo } from '@/lib/files'
import { formatDate } from '@/lib/options'
import { useMyContext } from '@/lib/appContext'
import { Button } from '@/components/ui'
import { Modal } from '@/components/kit'
import { initialsOf } from '@/components/UserMenu'

// CR80 card, portrait: 54 x 85.6 mm.
const CARD = 'relative flex h-[85.6mm] w-[54mm] shrink-0 flex-col overflow-hidden rounded-[3mm] bg-white text-slate-900 shadow-lg ring-1 ring-slate-200 print:shadow-none'

/** Auto-generated employee ID card (front + back) from the profile. */
export function IdCardDialog({ profile, open, onClose }: { profile: EmployeeProfile; open: boolean; onClose: () => void }) {
  const ctx = useMyContext()
  const org = ctx.organization!
  const e = profile.employee
  const files = useEmployeeFiles(org.id, e.id)
  const logo = useOrgLogo(org.id)
  const [qr, setQr] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    QRCode.toDataURL(idCardQrPayload(org.org_code, e.card_id), { margin: 0, width: 240, errorCorrectionLevel: 'M' })
      .then(setQr)
      .catch(() => setQr(null))
  }, [open, org.org_code, e.card_id])

  const photo = files.data?.photo?.url
  const signature = files.data?.signature?.url

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      title="Employee ID card"
      description="Generated from the profile. Upload a photo and signature on the profile to complete it."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Close</Button>
          <Button onClick={() => window.print()}><Printer className="size-4" />Print</Button>
        </>
      }
    >
      <div className="print-area flex flex-wrap justify-center gap-6">
        {/* Front */}
        <div className={CARD}>
          <div className="flex items-center gap-[2mm] bg-primary-600 px-[3mm] py-[2.5mm] text-white">
            {logo.data ? (
              <img src={logo.data} alt="" className="size-[8mm] rounded bg-white object-contain p-[0.5mm]" />
            ) : (
              <div className="flex size-[8mm] items-center justify-center rounded bg-white text-[4mm] font-bold text-primary-600">
                {org.name.charAt(0)}
              </div>
            )}
            <p className="text-[2.8mm] font-semibold leading-tight">{org.name}</p>
          </div>
          <div className="flex flex-1 flex-col items-center px-[3mm] pt-[4mm] text-center">
            {photo ? (
              <img src={photo} alt="" className="h-[26mm] w-[22mm] rounded-[1.5mm] object-cover ring-2 ring-primary-100" />
            ) : (
              <div className="flex h-[26mm] w-[22mm] items-center justify-center rounded-[1.5mm] bg-primary-50 text-[7mm] font-semibold text-primary-700">
                {initialsOf(e.full_name)}
              </div>
            )}
            <p className="mt-[3mm] text-[3.6mm] font-bold leading-tight">{e.full_name}</p>
            <p className="mt-[1mm] text-[2.6mm] text-slate-600">{e.designation_name ?? ''}</p>
            <p className="text-[2.4mm] text-slate-500">{e.department_name ?? ''}</p>
            <div className="mt-auto mb-[3mm] w-full space-y-[0.8mm] rounded-[1.5mm] bg-slate-50 px-[2mm] py-[1.5mm] text-left text-[2.3mm]">
              <p><span className="text-slate-500">ID </span><span className="font-mono font-semibold">{e.card_id}</span></p>
              {e.blood_group && <p><span className="text-slate-500">Blood </span><span className="font-semibold text-red-600">{e.blood_group}</span></p>}
              {e.join_date && <p><span className="text-slate-500">Joined </span>{formatDate(e.join_date)}</p>}
            </div>
          </div>
          <div className="h-[2mm] bg-primary-600" />
        </div>

        {/* Back */}
        <div className={CARD}>
          <div className="flex flex-1 flex-col items-center px-[4mm] pt-[5mm] text-center">
            {qr ? <img src={qr} alt="Card QR code" className="size-[26mm]" /> : <div className="size-[26mm] bg-slate-100" />}
            <p className="mt-[2mm] font-mono text-[2.8mm] font-semibold">{e.card_id}</p>
            <p className="text-[2.2mm] text-slate-500">{[e.branch_name, e.office_name].filter(Boolean).join(' · ')}</p>
            <div className="mt-[5mm] w-full">
              <div className="flex h-[9mm] items-end justify-center">
                {signature && <img src={signature} alt="" className="max-h-[9mm] max-w-[30mm] object-contain" />}
              </div>
              <div className="mx-auto w-[32mm] border-t border-slate-400 pt-[0.8mm] text-[2.1mm] text-slate-500">Holder's signature</div>
            </div>
            <div className="mt-[4mm] w-full">
              <div className="h-[6mm]" />
              <div className="mx-auto w-[32mm] border-t border-slate-400 pt-[0.8mm] text-[2.1mm] text-slate-500">Authorized signature</div>
            </div>
            <p className="mt-auto mb-[3mm] text-[2mm] leading-snug text-slate-500">
              This card is the property of {org.name}. If found, please return it. Org code {org.org_code}.
            </p>
          </div>
          <div className="h-[2mm] bg-primary-600" />
        </div>
      </div>
    </Modal>
  )
}
