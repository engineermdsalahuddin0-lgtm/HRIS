import type { ReactNode } from 'react'
import { useId, useState } from 'react'
import { Table2, ChartColumn } from 'lucide-react'
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { TooltipContentProps, TooltipValueType } from 'recharts'
import { Card } from '@/components/ui'

// Chart tokens (mirrors @theme in index.css). Fixed order: color follows the entity.
export const SERIES = ['#2a78d6', '#eb6834', '#1baf7a'] as const
const GRID = '#e7e5e4'
const TICK = { fill: '#64748b', fontSize: 12 }
const SURFACE = '#ffffff'

type Row = Record<string, string | number>

/** A chart card with a title, optional legend slot and a "view as table" toggle. */
export function ChartCard({
  title,
  subtitle,
  table,
  className,
  children,
}: {
  title: string
  subtitle?: string
  table: { columns: string[]; rows: (string | number)[][] }
  className?: string
  children: ReactNode
}) {
  const [asTable, setAsTable] = useState(false)
  const id = useId()
  return (
    <Card className={className}>
      <div className="mb-4 flex items-start justify-between gap-3">
        <div>
          <h2 id={id} className="font-semibold text-slate-900">{title}</h2>
          {subtitle && <p className="text-xs text-slate-500">{subtitle}</p>}
        </div>
        <button
          onClick={() => setAsTable((v) => !v)}
          className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
          aria-pressed={asTable}
          aria-label={asTable ? 'Show chart' : 'Show as table'}
          title={asTable ? 'Show chart' : 'Show as table'}
        >
          {asTable ? <ChartColumn className="size-4" /> : <Table2 className="size-4" />}
        </button>
      </div>
      {asTable ? (
        <div className="max-h-72 overflow-auto">
          <table className="w-full text-sm" aria-labelledby={id}>
            <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                {table.columns.map((c, i) => (
                  <th key={c} className={i ? 'py-2 text-right font-medium' : 'py-2 font-medium'}>{c}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {table.rows.map((r) => (
                <tr key={String(r[0])}>
                  {r.map((v, i) => (
                    <td key={i} className={i ? 'py-2 text-right tabular-nums text-slate-700' : 'py-2 text-slate-700'}>{v}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        children
      )}
    </Card>
  )
}

function TooltipBox({ active, payload, label }: TooltipContentProps<TooltipValueType, number | string>) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-xl bg-white px-3 py-2 text-xs shadow-lg ring-1 ring-slate-200">
      {label !== undefined && <p className="mb-1 font-medium text-slate-900">{label}</p>}
      {payload.map((p) => (
        <div key={String(p.dataKey ?? p.name)} className="flex items-center gap-2 text-slate-600">
          <span className="size-2.5 rounded-sm" style={{ background: p.color ?? p.payload?.fill }} aria-hidden />
          <span className="capitalize">{p.name}</span>
          <span className="ml-auto pl-3 font-medium tabular-nums text-slate-900">{String(p.value)}</span>
        </div>
      ))}
    </div>
  )
}

/** Single series over time: area with a 2px line and crosshair tooltip. */
export function HeadcountArea({ data }: { data: Row[] }) {
  const gid = useId().replace(/:/g, '')
  return (
    <div className="h-64" role="img" aria-label="Headcount by month">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
          <defs>
            <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SERIES[1]} stopOpacity={0.22} />
              <stop offset="100%" stopColor={SERIES[1]} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} stroke={GRID} />
          <XAxis dataKey="month" tick={TICK} axisLine={false} tickLine={false} />
          <YAxis tick={TICK} axisLine={false} tickLine={false} domain={['dataMin - 20', 'dataMax + 10']} allowDecimals={false} />
          <Tooltip content={TooltipBox} cursor={{ stroke: '#94a3b8', strokeDasharray: '4 4' }} />
          <Area
            type="monotone"
            dataKey="headcount"
            name="Headcount"
            stroke={SERIES[1]}
            strokeWidth={2}
            fill={`url(#${gid})`}
            activeDot={{ r: 5, stroke: SURFACE, strokeWidth: 2 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}

/** Part-to-whole with three parts: donut with direct value labels in the legend. */
export function EmploymentDonut({ data }: { data: { type: string; count: number }[] }) {
  const total = data.reduce((s, d) => s + d.count, 0)
  return (
    <div className="flex flex-col items-center gap-4">
      <div className="relative h-48 w-48" role="img" aria-label="Employees by employment type">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Tooltip content={TooltipBox} />
            <Pie
              data={data}
              dataKey="count"
              nameKey="type"
              innerRadius="64%"
              outerRadius="100%"
              stroke={SURFACE}
              strokeWidth={2}
              startAngle={90}
              endAngle={-270}
            >
              {data.map((d, i) => (
                <Cell key={d.type} fill={SERIES[i]} />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-semibold tabular-nums text-slate-900">{total}</span>
          <span className="text-xs text-slate-500">employees</span>
        </div>
      </div>
      <ul className="w-full space-y-2 text-sm">
        {data.map((d, i) => (
          <li key={d.type} className="flex items-center gap-2">
            <span className="size-2.5 rounded-sm" style={{ background: SERIES[i] }} aria-hidden />
            <span className="text-slate-600">{d.type}</span>
            <span className="ml-auto font-medium tabular-nums text-slate-900">{d.count}</span>
            <span className="w-10 text-right text-xs tabular-nums text-slate-500">{Math.round((d.count / total) * 100)}%</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

/** Magnitude by category: horizontal bars, one color, sorted, value labels at the end. */
export function DepartmentBars({ data }: { data: { department: string; count: number }[] }) {
  return (
    <div style={{ height: data.length * 32 + 8 }} role="img" aria-label="Employees by department">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} layout="vertical" margin={{ top: 0, right: 36, bottom: 0, left: 0 }} barCategoryGap={6}>
          <XAxis type="number" hide />
          <YAxis type="category" dataKey="department" width={110} tick={TICK} axisLine={false} tickLine={false} />
          <Tooltip content={TooltipBox} cursor={{ fill: '#f1f5f9' }} />
          <Bar
            dataKey="count"
            name="Employees"
            fill={SERIES[0]}
            radius={[0, 4, 4, 0]}
            label={{ position: 'right', fill: '#334155', fontSize: 12 }}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

/** Two series by month: grouped bars with a 2px gap and a legend. */
export function JoinersLeaversBars({ data }: { data: Row[] }) {
  return (
    <div className="h-64" role="img" aria-label="Joiners and leavers by month">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -24 }} barGap={2} barCategoryGap="28%">
          <CartesianGrid vertical={false} stroke={GRID} />
          <XAxis dataKey="month" tick={TICK} axisLine={false} tickLine={false} />
          <YAxis tick={TICK} axisLine={false} tickLine={false} allowDecimals={false} />
          <Tooltip content={TooltipBox} cursor={{ fill: '#f1f5f9' }} />
          <Legend
            verticalAlign="top"
            align="right"
            iconType="square"
            iconSize={10}
            height={28}
            formatter={(v: string) => <span className="text-xs text-slate-600">{v}</span>}
          />
          <Bar dataKey="joiners" name="Joiners" fill={SERIES[0]} radius={[4, 4, 0, 0]} />
          <Bar dataKey="leavers" name="Leavers" fill={SERIES[1]} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
