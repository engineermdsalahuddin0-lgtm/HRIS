import { Globe, MapPin, PenLine, QrCode, ScanFace, Timer } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { AttendanceRow, AttendanceStatus } from '@/lib/time'
import { STATUS_STYLE, WEEKDAYS } from '@/lib/time'
import { cx } from '@/components/ui'

export function AttendanceBadge({ status }: { status: AttendanceStatus }) {
  const s = STATUS_STYLE[status]
  return <span className={cx('inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium', s.cls)}>{s.label}</span>
}

const SOURCE_ICON: Record<string, { icon: LucideIcon; label: string }> = {
  web: { icon: Globe, label: 'Web' },
  gps: { icon: MapPin, label: 'GPS' },
  qr: { icon: QrCode, label: 'QR' },
  manual: { icon: PenLine, label: 'Manual' },
  biometric: { icon: ScanFace, label: 'Device' },
  auto: { icon: Timer, label: 'Auto check-out' },
}

export function SourceIcon({ source }: { source: string | null }) {
  if (!source) return null
  const s = SOURCE_ICON[source] ?? SOURCE_ICON.web
  const Icon = s.icon
  return (
    <span title={s.label} className="inline-flex text-slate-400">
      <Icon className="size-3.5" aria-label={s.label} />
    </span>
  )
}

/** Month grid with one coloured cell per day (status), Saturday..Friday aware of the locale start (Sunday). */
export function MonthCalendar({ month, rows, onPick }: { month: string; rows: AttendanceRow[]; onPick?: (r: AttendanceRow) => void }) {
  const [y, m] = month.split('-').map(Number)
  const first = new Date(Date.UTC(y, m - 1, 1)).getUTCDay()
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const byDate = new Map(rows.map((r) => [r.work_date, r]))
  const cells: (number | null)[] = [...Array(first).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)]

  return (
    <div>
      <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-medium uppercase text-slate-400">
        {WEEKDAYS.map((d) => <div key={d}>{d}</div>)}
      </div>
      <div className="mt-1 grid grid-cols-7 gap-1">
        {cells.map((d, i) => {
          if (!d) return <div key={`e${i}`} />
          const date = `${month}-${String(d).padStart(2, '0')}`
          const r = byDate.get(date)
          const style = r ? STATUS_STYLE[r.status] : null
          return (
            <button
              key={date}
              type="button"
              disabled={!r || !onPick}
              onClick={() => r && onPick?.(r)}
              title={r ? `${date}: ${style!.label}` : date}
              className={cx(
                'flex aspect-square flex-col items-center justify-center rounded-lg text-xs sm:text-sm',
                style ? style.cls : 'bg-slate-50 text-slate-400',
                r && onPick && 'hover:ring-2 hover:ring-primary-200',
              )}
            >
              <span className="font-medium">{d}</span>
              {r?.outside_geofence && <span className="size-1.5 rounded-full bg-red-500" aria-label="Outside geofence" />}
            </button>
          )
        })}
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {(Object.keys(STATUS_STYLE) as AttendanceStatus[]).map((k) => (
          <span key={k} className={cx('rounded-full px-2 py-0.5 text-[11px] font-medium', STATUS_STYLE[k].cls)}>{STATUS_STYLE[k].label}</span>
        ))}
      </div>
    </div>
  )
}

export function MonthPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <input
      type="month"
      value={value}
      onChange={(e) => e.target.value && onChange(e.target.value)}
      aria-label="Month"
      className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
    />
  )
}

export function DateInput({ value, onChange, label }: { value: string; onChange: (v: string) => void; label: string }) {
  return (
    <input
      type="date"
      value={value}
      onChange={(e) => e.target.value && onChange(e.target.value)}
      aria-label={label}
      className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
    />
  )
}
