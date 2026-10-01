import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  ResponsiveContainer, LineChart, Line, BarChart, Bar, Cell, XAxis, YAxis, Tooltip, ReferenceArea,
} from 'recharts'
import { format } from 'date-fns'
import { ArrowRight } from 'lucide-react'
import { useDevelopmentAnalytics } from '@/api/analytics'
import type { DevelopmentAnalytics, DevelopmentBlock, DevelopmentLift, DevelopmentCurrency, DevelopmentPerBlock } from '@/api/types'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { cn } from '@/lib/utils'
import {
  blockBands, blockColor, currencySeries, dayStamp, formatDelta, liftSeries, METRIC_UNIT, type BlockBand, type SeriesPoint,
} from '@/lib/developmentShaping'
import { statusLevel } from './status'

/**
 * How the athlete has developed across programs — the history tables read
 * as one document (`GET /api/analytics/development`). Blocks along the top,
 * then each lift across the span with its per-block deltas, load by block,
 * and the standards ladder over time. The Program tab is the current block;
 * this is every block.
 */
export function DevelopmentTab() {
  const { data, isLoading, isError, error } = useDevelopmentAnalytics()

  if (isLoading) return <div className="p-6"><LoadingCard /></div>
  if (isError) return <div className="p-6"><ErrorBanner error={error as Error} title="Could not load development" /></div>
  if (!data || data.status === 'no_history' || data.blocks.length === 0) {
    return (
      <div className="p-6">
        <EmptyState
          title="No program history yet"
          description="Programs are recorded from the moment they are generated or saved. Development across them appears once there is a second block."
        />
      </div>
    )
  }
  return <Document data={data} />
}

function Document({ data }: { data: DevelopmentAnalytics }) {
  const today = data.window.to
  const bands = useMemo(() => blockBands(data.blocks, today), [data.blocks, today])
  const singleBlock = data.blocks.length < 2

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
      <BlockTimeline blocks={data.blocks} bands={bands} />
      {singleBlock && (
        <p className="text-xs text-muted-foreground">
          One block so far. Development across programs fills in when the next one starts; this program's own progress is on the{' '}
          <Link to="/analytics?tab=progress" className="text-primary hover:underline">Progress</Link> tab.
        </p>
      )}
      <LiftsAcrossBlocks lifts={data.lifts} currencies={data.currencies} blocks={data.blocks} bands={bands} />
      <LoadAcrossBlocks data={data} />
      <StandardsOverTime data={data} />
    </div>
  )
}

// ── Blocks ────────────────────────────────────────────────────────────────────

function BlockTimeline({ blocks, bands }: { blocks: DevelopmentBlock[]; bands: BlockBand[] }) {
  const first = bands[0]?.x1 ?? 0
  const last = bands[bands.length - 1]?.x2 ?? 1
  const span = Math.max(1, last - first)
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Blocks</p>
        <p className="text-xs text-muted-foreground">
          {blocks.length} block{blocks.length === 1 ? '' : 's'} · {format(new Date(first), 'd MMM yyyy')} → today
        </p>
      </div>
      {/* The timeline strip: each block's share of the span, in its colour. */}
      <div className="flex h-3 w-full overflow-hidden rounded-full bg-muted" role="img" aria-label="Program timeline">
        {bands.map((b) => (
          <div key={b.id} title={b.label}
               style={{ width: `${Math.max(1.5, ((b.x2 - b.x1) / span) * 100)}%`, backgroundColor: b.color }}
               className={cn('h-full', b.isActive && 'animate-pulse')} />
        ))}
      </div>
      <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {blocks.map((b) => (
          <li key={b.id} className="flex items-start gap-2 rounded-md border border-border/50 px-3 py-2">
            <span className="mt-1 size-2.5 shrink-0 rounded-full" style={{ backgroundColor: blockColor(blocks, b.id) }} />
            <div className="min-w-0 text-xs">
              <div className="flex items-center gap-1.5">
                <p className="truncate font-medium text-foreground">{b.methodologies.map((m) => m.name).join(' + ') || b.label}</p>
                {b.isActive && <span className="shrink-0 rounded bg-primary/15 px-1.5 py-0.5 text-[10px] text-primary">current</span>}
              </div>
              <p className="text-muted-foreground">
                {format(new Date(dayStamp(b.from)), 'd MMM')} → {b.to ? format(new Date(dayStamp(b.to)), 'd MMM') : 'now'} · {b.weeks} wk
              </p>
              <p className="text-muted-foreground">
                {b.completed} / {b.planned} sessions{b.completionPct != null && <> · {b.completionPct}%</>}
                {b.plannedTotal > b.planned && <> · {b.plannedTotal - b.planned} never reached</>}
              </p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}

// ── Lifts and currencies ──────────────────────────────────────────────────────

interface TooltipProps { active?: boolean; payload?: Array<{ payload: SeriesPoint }> }

function PointTooltip({ active, payload, unit }: TooltipProps & { unit: string }) {
  if (!active || !payload?.length) return null
  const p = payload[0].payload
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">{format(new Date(p.x), 'd MMM yyyy')}{p.isDeload ? ' · deload' : ''}</p>
      <p className="text-foreground"><span className="font-semibold">{p.value}</span> {unit}</p>
      {p.weight != null && p.reps != null && <p className="text-muted-foreground">{p.weight} kg × {p.reps}</p>}
    </div>
  )
}

function SeriesChart({ series, bands, unit, blocks }: {
  series: SeriesPoint[]; bands: BlockBand[]; unit: string; blocks: DevelopmentBlock[]
}) {
  if (series.length === 0) return null
  const x1 = Math.min(bands[0]?.x1 ?? series[0].x, series[0].x)
  const x2 = Math.max(bands[bands.length - 1]?.x2 ?? series[series.length - 1].x, series[series.length - 1].x)
  return (
    <ResponsiveContainer width="100%" height={200}>
      <LineChart data={series} margin={{ top: 8, right: 12, left: -16, bottom: 0 }}>
        {bands.map((b) => (
          <ReferenceArea key={b.id} x1={b.x1} x2={b.x2} fill={b.color} fillOpacity={0.08} strokeOpacity={0} />
        ))}
        <XAxis dataKey="x" type="number" domain={[x1, x2]} scale="time"
               tickFormatter={(v: number) => format(new Date(v), 'd MMM')}
               tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false}
               domain={['auto', 'auto']} unit={` ${unit}`} />
        <Tooltip content={<PointTooltip unit={unit} />} />
        <Line type="monotone" dataKey="value" stroke="#10b981" strokeWidth={2} connectNulls isAnimationActive={false}
              dot={(props: { cx?: number; cy?: number; payload?: SeriesPoint }) => (
                <circle key={`${props.cx}-${props.cy}`} cx={props.cx} cy={props.cy} r={4}
                        fill={props.payload?.isDeload ? 'var(--color-card)' : blockColor(blocks, props.payload?.blockId)}
                        stroke={blockColor(blocks, props.payload?.blockId)} strokeWidth={1.5} />
              )} />
      </LineChart>
    </ResponsiveContainer>
  )
}

function PerBlockTable({ rows, blocks, unit }: { rows: DevelopmentPerBlock[]; blocks: DevelopmentBlock[]; unit: string }) {
  if (rows.length === 0) return null
  return (
    <table className="w-full text-xs">
      <thead>
        <tr className="text-[10px] uppercase tracking-wider text-muted-foreground">
          <th className="py-1 text-left font-medium">Block</th>
          <th className="py-1 text-right font-medium">Sessions</th>
          <th className="py-1 text-right font-medium">First</th>
          <th className="py-1 text-right font-medium">Last</th>
          <th className="py-1 text-right font-medium">Best</th>
          <th className="py-1 text-right font-medium">Δ</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => {
          const block = blocks.find((b) => b.id === r.blockId)
          return (
            <tr key={r.blockId} className="border-t border-border/40">
              <td className="py-1.5">
                <span className="mr-1.5 inline-block size-2 rounded-full align-middle" style={{ backgroundColor: blockColor(blocks, r.blockId) }} />
                {block?.methodologies.map((m) => m.name).join(' + ') ?? block?.label ?? `Block ${r.blockId}`}
              </td>
              <td className="py-1.5 text-right tabular-nums">{r.sessions}</td>
              <td className="py-1.5 text-right tabular-nums">{r.first} {unit}</td>
              <td className="py-1.5 text-right tabular-nums">{r.last} {unit}</td>
              <td className="py-1.5 text-right tabular-nums">{r.best} {unit}</td>
              <td className={cn('py-1.5 text-right tabular-nums font-medium',
                                r.delta > 0 && 'text-emerald-700 dark:text-emerald-300',
                                r.delta < 0 && 'text-amber-700 dark:text-amber-300')}>
                {formatDelta(r.delta)}
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

function TrendLine({ trend }: { trend: DevelopmentLift['trend'] }) {
  if (trend.direction === 'insufficient_data') return <span className="text-muted-foreground">not enough points</span>
  const level = statusLevel(trend.direction === 'improving' ? 'on_track' : trend.direction === 'declining' ? 'behind' : 'stable_by_design')
  return (
    <span className={cn(level === 'green' && 'text-emerald-700 dark:text-emerald-300',
                        level === 'yellow' && 'text-amber-700 dark:text-amber-300',
                        level !== 'green' && level !== 'yellow' && 'text-muted-foreground')}>
      {trend.direction} · {trend.slopePct > 0 ? '+' : ''}{trend.slopePct}%/session over {trend.pointsUsed}
    </span>
  )
}

function LiftsAcrossBlocks({ lifts, currencies, blocks, bands }: {
  lifts: DevelopmentLift[]; currencies: DevelopmentCurrency[]; blocks: DevelopmentBlock[]; bands: BlockBand[]
}) {
  const options = useMemo(() => [
    ...lifts.map((l) => ({ key: `lift:${l.exerciseId}`, label: l.name, kind: 'lift' as const, lift: l })),
    ...currencies.map((c) => ({ key: `cur:${c.exerciseId}:${c.metric}`, label: `${c.name} · ${METRIC_UNIT[c.metric]}`, kind: 'currency' as const, currency: c })),
  ], [lifts, currencies])
  const [selectedKey, setSelectedKey] = useState<string | null>(null)
  const selected = options.find((o) => o.key === selectedKey) ?? options[0]

  if (options.length === 0) {
    return (
      <div className="rounded-lg border bg-card p-4">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Lifts across blocks</p>
        <p className="mt-2 text-xs text-muted-foreground">Nothing logged yet. Sets logged on a session appear here across every block that trained the lift.</p>
      </div>
    )
  }

  const series = selected.kind === 'lift' ? liftSeries(selected.lift) : currencySeries(selected.currency)
  const unit = selected.kind === 'lift' ? 'kg' : METRIC_UNIT[selected.currency.metric]
  const perBlock = selected.kind === 'lift' ? selected.lift.perBlock : selected.currency.perBlock
  const trend = selected.kind === 'lift' ? selected.lift.trend : selected.currency.trend

  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          {selected.kind === 'lift' ? 'Lifts across blocks' : 'Across blocks'}
        </p>
        <p className="text-[11px]"><TrendLine trend={trend} /></p>
      </div>
      <div className="flex flex-wrap gap-1">
        {options.map((o) => (
          <button key={o.key} type="button" onClick={() => setSelectedKey(o.key)}
                  className={cn('px-2 py-0.5 text-[10px] rounded border transition-colors',
                                o.key === selected.key ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}>
            {o.label}{o.kind === 'lift' && o.lift.blocks > 1 ? ` · ${o.lift.blocks} blocks` : ''}
          </button>
        ))}
      </div>
      <p className="text-[11px] text-muted-foreground">
        {selected.kind === 'lift' ? 'Estimated 1RM of the heaviest completed set per session; the band is the block.' : 'The logged value per session; the band is the block.'}
      </p>
      <SeriesChart series={series} bands={bands} unit={unit} blocks={blocks} />
      <PerBlockTable rows={perBlock} blocks={blocks} unit={unit} />
    </div>
  )
}

// ── Load ──────────────────────────────────────────────────────────────────────

function weekStart(isoWeek: string): Date {
  const [year, w] = isoWeek.split('-W').map(Number)
  const jan4 = new Date(year, 0, 4)
  const monday = new Date(jan4)
  monday.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7) + (w - 1) * 7)
  return monday
}

interface LoadRow { week: string; label: string; trimp: number; sessions: number; blockId: number | null }

function LoadTooltip({ active, payload }: { active?: boolean; payload?: Array<{ payload: LoadRow }> }) {
  if (!active || !payload?.length) return null
  const r = payload[0].payload
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">Week of {r.label}</p>
      <p className="text-foreground"><span className="font-semibold">{r.trimp}</span> TRIMP · {r.sessions} session{r.sessions === 1 ? '' : 's'}</p>
    </div>
  )
}

function LoadAcrossBlocks({ data }: { data: DevelopmentAnalytics }) {
  const weekly = data.load.weekly
  if (weekly.length === 0) return null
  const rows = weekly.map((w) => ({ ...w, label: format(weekStart(w.week), 'd MMM') }))
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Load across blocks</p>
        <p className="text-[11px] text-muted-foreground">Weekly TRIMP, coloured by block</p>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <BarChart data={rows} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
          <XAxis dataKey="label" tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
          <YAxis tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} />
          <Tooltip content={<LoadTooltip />} />
          <Bar dataKey="trimp" radius={[3, 3, 0, 0]} isAnimationActive={false}>
            {rows.map((r) => <Cell key={r.week} fill={blockColor(data.blocks, r.blockId)} fillOpacity={r.blockId == null ? 0.4 : 0.85} />)}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

// ── Standards ─────────────────────────────────────────────────────────────────

function StandardsOverTime({ data }: { data: DevelopmentAnalytics }) {
  if (data.benchmarks.length === 0) return null
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Standards over time</p>
        <Link to="/profile?tab=benchmarks" className="inline-flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground">
          Log a PR <ArrowRight className="size-3" />
        </Link>
      </div>
      <ul className="space-y-2">
        {data.benchmarks.map((b) => (
          <li key={b.benchmarkId} className="text-xs">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="font-medium">{b.name}</span>
              <span className={cn('rounded px-1.5 py-0.5 text-[10px]',
                                  b.levelsGained > 0 ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300' : 'bg-muted text-muted-foreground')}>
                {b.latestLevel ?? 'below entry'}{b.levelsGained > 0 && <> · +{b.levelsGained} level{b.levelsGained === 1 ? '' : 's'}</>}
              </span>
            </div>
            <p className="mt-0.5 text-muted-foreground">
              {b.history.map((h, i) => (
                <span key={h.date}>
                  {i > 0 && ' → '}
                  {h.value}{b.unit} <span className="text-[10px]">({h.level ?? 'below entry'}, {format(new Date(dayStamp(h.date)), 'd MMM')})</span>
                </span>
              ))}
            </p>
          </li>
        ))}
      </ul>
    </div>
  )
}
