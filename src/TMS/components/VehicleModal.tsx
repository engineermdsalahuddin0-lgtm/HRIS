import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Pencil, Upload } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, PageLoader } from '@/components/ui'
import { Modal } from '@/components/kit'
import { expiryBadge } from '@/DMS/core/dms'
import { useLibrary } from '@/DMS/data/api'
import { UploadForm } from '@/DMS/components/UploadForm'
import { FUEL, LICENCE_CLASS, VEHICLE_STATUS, VEHICLE_TYPE, formatKm, formatTaka } from '../core/tms'
import type { Paper } from '../core/types'
import { useLinkPaper, useVehicle } from '../data/api'

/** One vehicle: details, papers from the DMS (upload here: the DMS names, reviews and reminds). */
export function VehicleModal({ id, canManage, onEdit, onClose }: { id: string; canManage: boolean; onEdit: () => void; onClose: () => void }) {
  const v = useVehicle(id)
  const [uploading, setUploading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const d = v.data
  return (
    <Modal open onClose={onClose} size="lg" title={d?.reg_no ?? 'Vehicle'}
      description={d ? `${VEHICLE_TYPE[d.vtype]}${d.make ? ` · ${d.make} ${d.model ?? ''}` : ''}${d.year ? ` · ${d.year}` : ''}` : undefined}>
      {v.isPending ? <PageLoader /> : v.isError ? <Alert>{errorMessage(v.error)}</Alert> : d && (
        uploading ? (
          <PaperUpload vehicleId={d.id} onDone={(msg) => { setUploading(false); setMessage(msg) }} onCancel={() => setUploading(false)} />
        ) : (
          <div className="space-y-5">
            {message && <Alert tone="success">{message}</Alert>}
            <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
              {([
                ['Status', <Badge key="s" tone={VEHICLE_STATUS[d.status].tone}>{VEHICLE_STATUS[d.status].label}</Badge>],
                ['Fuel', `${FUEL[d.fuel].label}${d.fuel2 ? ` + ${FUEL[d.fuel2].label}` : ''}`],
                ['Odometer', formatKm(d.odometer_km)],
                ['Default driver', d.driver?.name ?? '—'],
                ['Licence needed', LICENCE_CLASS[d.class_needed]],
                ['Branch / department', [d.branch, d.department].filter(Boolean).join(' · ') || '—'],
                ['Tank', d.tank_l ? `${d.tank_l} L${d.cng_m3 ? ` · CNG ${d.cng_m3} m³` : ''}` : '—'],
                ['Seats / payload', [d.seats ? `${d.seats} seats` : null, d.payload_kg ? `${d.payload_kg} kg` : null].filter(Boolean).join(' · ') || '—'],
                ['Ownership', d.ownership],
                ['Chassis / engine', [d.chassis_no, d.engine_no].filter(Boolean).join(' / ') || '—'],
                ...(d.purchase_cost != null ? [['Purchase', `${formatTaka(d.purchase_cost)}${d.purchase_date ? ` · ${formatDate(d.purchase_date)}` : ''}`]] : []),
              ] as [string, ReactNode][]).map(([k, val]) => (
                <div key={k}><dt className="text-xs text-slate-500">{k}</dt><dd className="text-slate-900">{val}</dd></div>
              ))}
            </dl>
            <Papers title="Vehicle papers" papers={d.papers} empty="No papers yet: upload the registration, fitness, tax token, route permit and insurance." />
            {d.driver && <Papers title={`${d.driver.name}'s licence copy`} papers={d.driver_papers} empty="No licence copy uploaded." />}
            {canManage && (
              <div className="flex flex-wrap gap-2">
                <Button onClick={() => { setMessage(null); setUploading(true) }}><Upload className="size-4" /> Upload a paper</Button>
                <Button variant="secondary" onClick={onEdit}><Pencil className="size-4" /> Edit vehicle</Button>
              </div>
            )}
          </div>
        )
      )}
    </Modal>
  )
}

function Papers({ title, papers, empty }: { title: string; papers: Paper[]; empty: string }) {
  return (
    <div>
      <h3 className="mb-2 text-sm font-semibold text-slate-900">{title}</h3>
      {papers.length === 0 ? <p className="text-sm text-slate-500">{empty}</p> : (
        <ul className="divide-y divide-slate-100 rounded-xl ring-1 ring-slate-200">
          {papers.map((p) => {
            const b = expiryBadge(p.expiry_status, p.days_left)
            return (
              <li key={p.document_id} className="flex flex-wrap items-center gap-3 px-3 py-2 text-sm">
                <Link to={`/documents?tab=library&doc=${p.document_id}`} className="font-medium text-slate-900 hover:text-primary-700">{p.type_name}</Link>
                <span className="font-mono text-xs text-slate-500">{p.doc_code}</span>
                {p.lifecycle === 'pending' && <Badge tone="orange">In review</Badge>}
                <span className="ml-auto text-xs text-slate-600">{formatDate(p.expiry_date)}</span>
                <Badge tone={b.tone}>{b.label}</Badge>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

/** The DMS upload form inside "Transport & Vehicles"; the new document is then linked to this vehicle. */
function PaperUpload({ vehicleId, onDone, onCancel }: { vehicleId: string; onDone: (msg: string) => void; onCancel: () => void }) {
  const library = useLibrary()
  const link = useLinkPaper()
  if (library.isPending) return <PageLoader />
  if (library.isError) return <Alert>{errorMessage(library.error)}</Alert>
  const folder = library.data.folders.find((f) => f.catalog_code === 'TRP')
  if (!folder) return <Alert>The "Transport &amp; Vehicles" folder is switched off in Documents → Setup.</Alert>
  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-600">Saved in Documents → Transport &amp; Vehicles and linked to this vehicle. The DMS names it and reminds before expiry.</p>
      <UploadForm library={library.data} folderId={folder.id}
        onDone={(r) => link.mutate({ documentId: r.document_id, vehicleId }, {
          onSuccess: () => onDone(r.status === 'in_review' ? `${r.version_name} saved; it shows once approved in Documents → Review.` : `${r.version_name} saved.`),
        })}
        onNewVersion={() => onCancel()} />
      {link.isError && <Alert>{errorMessage(link.error)}</Alert>}
      <Button variant="ghost" onClick={onCancel}>Back</Button>
    </div>
  )
}
