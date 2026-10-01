import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, Legend } from 'recharts'
import type { AnalyticsIntensity } from '@/api/types'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { StatusBadge } from './StatusBadge'
import { CoverageNotice } from './CoverageNotice'

const BUCKETS = INTENSITY_BUCKETS

interface TooltipProps { active?: boolean; payload?: Array<{ payload: Record<string, unknown> }> }

function WeekTooltip({ active, payload }: TooltipProps) {
  if (!active || !payload?.length) return null
  const w = payload[0].payload as { week: number; actualPct: Record<string, number | null>; plannedPct: Record<string, number> | null; unclassified: number; isDeload: boolean }
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">Week {w.week}{w.isDeload ? ' · deload' : ''}</p>
      {BUCKETS.map((b) => (
        <p key={b.key} className="text-foreground">
          {b.label}: <span className="font-semibold">{w.actualPct[b.key] ?? 0}%</span>
          {w.plannedPct && <span className="text-muted-foreground"> / {w.plannedPct[b.key]}% planned</span>}
        </p>
      ))}
      {w.unclassified > 0 && <p className="text-muted-foreground">{w.unclassified} min unclassified</p>}
    </div>
  )
}

/** Planned intensity split against actual, per week. */
export function IntensitySplit({ intensity }: { intensity: AnalyticsIntensity }) {
  const data = intensity.weeks.map((w) => ({ ...w, label: `W${w.week}` }))
  const current = intensity.byFramework[intensity.byFramework.length - 1]
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Intensity split</p>
          <p className="text-xs text-muted-foreground">Minutes per bucket, against what the framework prescribes.</p>
        </div>
        <StatusBadge status={intensity.status} />
      </div>
      <CoverageNotice coverage={intensity.coverage} />
      {data.length > 0 && (
        <ResponsiveContainer width="100%" height={170}>
          <BarChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }} barCategoryGap={4}>
            <XAxis dataKey="label" tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} unit=" min" />
            <Tooltip content={<WeekTooltip />} cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }} />
            <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />
            {BUCKETS.map((b, i) => (
              <Bar key={b.key} dataKey={b.key} name={b.label} stackId="split" fill={b.color}
                   stroke="var(--color-card)" strokeWidth={1}
                   radius={i === BUCKETS.length - 1 ? [3, 3, 0, 0] : 0} />
            ))}
          </BarChart>
        </ResponsiveContainer>
      )}
      {current?.plannedPct && current.deviationPts && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-muted-foreground">
          {BUCKETS.map((b) => (
            <span key={b.key}>
              <span className="inline-block size-2 rounded-sm align-middle mr-1" style={{ backgroundColor: b.color }} />
              {b.label} {current.actualPct[b.key] ?? 0}% vs {current.plannedPct![b.key]}%
              <span className={Math.abs(current.deviationPts![b.key]) > 10 ? ' text-amber-800 dark:text-amber-300' : ''}>
                {' '}({current.deviationPts![b.key] > 0 ? '+' : ''}{current.deviationPts![b.key]})
              </span>
            </span>
          ))}
        </div>
      )}
      {intensity.pct1rm && intensity.pct1rm.meanPct != null && (
        <p className="text-[11px] text-muted-foreground">
          Working sets averaged <span className="font-semibold text-foreground">{intensity.pct1rm.meanPct}%</span> of estimated 1RM
          across {intensity.pct1rm.sessions} logged lifts.
        </p>
      )}
    </div>
  )
}
