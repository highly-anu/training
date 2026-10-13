import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  BarChart3,
  Activity,
  Timer,
  Footprints,
  Flame,
  ArrowDownToLine,
  TrendingUp,
  TrendingDown,
} from 'lucide-react'
import { format, parseISO } from 'date-fns'
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  Cell,
  XAxis,
  YAxis,
  Tooltip as RechartTooltip,
  PieChart,
  Pie,
} from 'recharts'
import { cn } from '@/lib/utils'
import { WeeklyLoadChart } from '@/components/bio/WeeklyLoadChart'
import { PMCChart } from '@/components/bio/PMCChart'
import { ProgramTab } from '@/components/analytics/ProgramTab'
import { ProgressionTab } from '@/components/progression/ProgressionTab'
import { RecoveryTab } from '@/components/bio/RecoveryTab'
import { DevelopmentTab } from '@/components/analytics/DevelopmentTab'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { useLoadSummary } from '@/api/health'
import type { ModalityId } from '@/api/types'
import { formatActivityType } from '@/lib/activityType'
import { EmptyState } from '@/components/shared/EmptyState'

// ── Types ──────────────────────────────────────────────────────────────────────

type SubTab = 'program' | 'progress' | 'blocks' | 'load' | 'recovery'
type Period = '7d' | '30d' | '3m' | '1y' | 'all'

// Analytics is the interpretation: what the program is for (Program), how the
// athlete is progressing against it (Progress), what the body has been asked
// to absorb (Load) and how it is coping (Recovery); Blocks reads every program
// the athlete has run. The record itself — every recorded workout — lives under
// Log. Names and order match the phone's Analytics sections.
const SUB_TABS: { id: SubTab; label: string }[] = [
  { id: 'program',  label: 'Program'  },
  { id: 'progress', label: 'Progress' },
  { id: 'blocks',   label: 'Blocks'   },
  { id: 'load',     label: 'Load'     },
  { id: 'recovery', label: 'Recovery' },
]
const SUB_TAB_IDS = new Set<string>(SUB_TABS.map((t) => t.id))

const PERIODS: { id: Period; label: string; days: number | null }[] = [
  { id: '7d',  label: '7d',   days: 7   },
  { id: '30d', label: '30d',  days: 30  },
  { id: '3m',  label: '3m',   days: 90  },
  { id: '1y',  label: '1y',   days: 365 },
  { id: 'all', label: 'All',  days: null },
]

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtHours(minutes: number): string {
  const h = minutes / 60
  return h >= 10 ? `${Math.round(h)}h` : `${h.toFixed(1)}h`
}

function fmtDist(km: number): string {
  return km >= 100 ? `${Math.round(km)} km` : `${km.toFixed(1)} km`
}

function fmtElev(m: number): string {
  return `${Math.round(m).toLocaleString()} m`
}

// ── Tab Selector ───────────────────────────────────────────────────────────────

function TabSelector({
  active,
  onChange,
  tabs,
}: {
  active: string
  onChange: (t: SubTab) => void
  tabs: typeof SUB_TABS
}) {
  return (
    <div className="flex items-center gap-1">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onChange(tab.id as SubTab)}
          className={cn(
            'px-3 py-1 text-xs rounded border transition-colors',
            tab.id === active
              ? 'bg-primary/15 border-primary/40 text-primary'
              : 'border-border text-muted-foreground hover:bg-muted'
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}

// ── Period Selector ────────────────────────────────────────────────────────────

function PeriodSelector({ active, onChange }: { active: Period; onChange: (p: Period) => void }) {
  return (
    <div className="flex items-center gap-1">
      {PERIODS.map((p) => (
        <button
          key={p.id}
          type="button"
          onClick={() => onChange(p.id)}
          className={cn(
            'px-2.5 py-1 text-xs rounded border transition-colors',
            p.id === active
              ? 'bg-primary/15 border-primary/40 text-primary'
              : 'border-border text-muted-foreground hover:bg-muted'
          )}
        >
          {p.label}
        </button>
      ))}
    </div>
  )
}

// ── KPI Cards ─────────────────────────────────────────────────────────────────

function KpiCard({
  label,
  value,
  icon: Icon,
  color,
}: {
  label: string
  value: string | null
  icon: React.ElementType
  color: string
}) {
  return (
    <div className="rounded-xl border bg-card p-4 flex flex-col gap-1.5">
      <div className="flex items-center gap-1.5">
        <Icon className={cn('size-3.5', color)} />
        <span className="text-xs text-muted-foreground">{label}</span>
      </div>
      <span className="text-2xl font-bold tabular-nums text-foreground">
        {value ?? '—'}
      </span>
    </div>
  )
}

// ── Overview Tab ───────────────────────────────────────────────────────────────

/**
 * Period totals, what kinds of training they were, and week-by-week
 * consistency — the first half of the Load tab.
 */
function VolumeSection({ period, onPeriodChange }: { period: Period; onPeriodChange: (p: Period) => void }) {
  const navigate = useNavigate()
  // Totals, mixes and consistency are the server's (GET /health/load/summary),
  // the same document the phone's Load section reads.
  const { data: summary } = useLoadSummary(period)
  const sessionCount = summary?.totals.sessions ?? 0

  const stats = useMemo(() => {
    const t = summary?.totals
    return {
      sessions: t?.sessions ?? 0,
      hours: t && t.minutes > 0 ? fmtHours(t.minutes) : null,
      distance: t?.distanceKm ? fmtDist(t.distanceKm) : null,
      ascended: t?.elevationGainM ? fmtElev(t.elevationGainM) : null,
      descended: t?.elevationLossM ? fmtElev(t.elevationLossM) : null,
      calories: t?.calories ? `${Math.round(t.calories).toLocaleString()} kcal` : null,
    }
  }, [summary])

  const activityBreakdown = useMemo(() => (summary?.activities ?? []).map((a) => {
    const modalityId = a.modalityId as ModalityId | null
    return {
      type: formatActivityType(a.activityType),
      hours: Math.round((a.minutes / 60) * 10) / 10,
      sessions: a.sessions,
      modalityId,
      color: modalityId ? MODALITY_COLORS[modalityId]?.hex ?? '#94a3b8' : '#94a3b8',
    }
  }), [summary])

  const modalityBreakdown = useMemo(() => (summary?.modalities ?? []).map((m) => ({
    id: m.id ?? '__unclassified__',
    label: m.id == null ? 'Unclassified' : (MODALITY_COLORS[m.id as ModalityId]?.label ?? m.id),
    pct: m.pct,
    color: m.id == null ? '#475569' : (MODALITY_COLORS[m.id as ModalityId]?.hex ?? '#94a3b8'),
  })), [summary])

  const weeklyConsistency = useMemo(() => {
    const weeks = summary?.consistency ?? []
    return weeks.map((w, i) => ({
      label: i === weeks.length - 1 ? 'This wk' : format(parseISO(w.weekStart), 'MMM d'),
      count: w.sessions,
    }))
  }, [summary])

  function consistencyColor(count: number): string {
    if (count === 0) return 'var(--color-muted)'
    if (count <= 2) return '#10b981'
    if (count <= 4) return '#38bdf8'
    if (count <= 6) return '#f59e0b'
    return '#ef4444'
  }

  const dominantModality = modalityBreakdown[0]

  return (
    <>
      {/* Period selector */}
      <div className="flex items-center gap-3">
        <span className="text-xs text-muted-foreground">Period</span>
        <PeriodSelector active={period} onChange={onPeriodChange} />
        {sessionCount > 0 && (
          <span className="text-xs text-muted-foreground ml-auto">{sessionCount} workout{sessionCount !== 1 ? 's' : ''}</span>
        )}
      </div>

      {/* KPI row */}
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Totals</h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <KpiCard label="Sessions"  value={stats.sessions > 0 ? String(stats.sessions) : null} icon={Activity}     color="text-primary"        />
          <KpiCard label="Time"      value={stats.hours}         icon={Timer}        color="text-sky-700 dark:text-sky-300"        />
          <KpiCard label="Distance"  value={stats.distance}      icon={Footprints}   color="text-emerald-700 dark:text-emerald-300"    />
          <KpiCard label="Ascended"  value={stats.ascended}      icon={TrendingUp}   color="text-amber-700 dark:text-amber-300"      />
          <KpiCard label="Descended" value={stats.descended}     icon={TrendingDown} color="text-rose-700 dark:text-rose-300"       />
          <KpiCard label="Calories"  value={stats.calories}      icon={Flame}        color="text-orange-700 dark:text-orange-300"     />
        </div>
      </div>

      {summary && sessionCount === 0 && (
        <EmptyState
          icon={<ArrowDownToLine className="size-8 opacity-40" />}
          title="No workouts in this period"
          description="Connected sources import on their own; a file can be imported under Log. Or pick a longer period."
          action={{ label: 'Import a file', onClick: () => navigate('/log?import=1') }}
        />
      )}

      {sessionCount > 0 && (
        <>
          {/* Activity breakdown */}
          {activityBreakdown.length > 0 && (
            <div>
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">By Activity Type</h2>
              <div className="rounded-xl border bg-card p-4">
                <ResponsiveContainer width="100%" height={Math.max(80, activityBreakdown.length * 32)}>
                  <BarChart
                    data={activityBreakdown}
                    layout="vertical"
                    margin={{ top: 0, right: 8, left: 0, bottom: 0 }}
                  >
                    <XAxis
                      type="number"
                      dataKey="hours"
                      tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
                      axisLine={false}
                      tickLine={false}
                      unit="h"
                    />
                    <YAxis
                      type="category"
                      dataKey="type"
                      width={110}
                      tick={{ fontSize: 10, fill: 'var(--color-foreground)' }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <RechartTooltip
                      cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }}
                      contentStyle={{
                        backgroundColor: 'var(--card)',
                        border: '1px solid var(--border)',
                        borderRadius: '8px',
                        fontSize: '12px',
                        color: 'var(--foreground)',
                      }}
                      formatter={(v: unknown, _name: unknown, props: { payload?: { sessions?: number } }) => [
                        `${String(v)}h · ${props.payload?.sessions ?? ''} sessions`,
                        'Training',
                      ]}
                    />
                    <Bar dataKey="hours" radius={[0, 3, 3, 0]}>
                      {activityBreakdown.map((entry, i) => (
                        <Cell key={i} fill={entry.color} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {/* Modality donut */}
          {modalityBreakdown.length > 0 && (
            <div>
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">By Training Modality</h2>
              <div className="rounded-xl border bg-card p-4">
                <div className="flex items-center gap-6">
                  <div className="relative shrink-0">
                    <ResponsiveContainer width={140} height={140}>
                      <PieChart>
                        <Pie
                          data={modalityBreakdown}
                          cx="50%"
                          cy="50%"
                          innerRadius={42}
                          outerRadius={64}
                          paddingAngle={2}
                          dataKey="pct"
                          animationBegin={200}
                          animationDuration={600}
                        >
                          {modalityBreakdown.map((entry, i) => (
                            <Cell key={i} fill={entry.color} stroke="transparent" />
                          ))}
                        </Pie>
                        <RechartTooltip
                          contentStyle={{
                            backgroundColor: 'var(--card)',
                            border: '1px solid var(--border)',
                            borderRadius: '8px',
                            fontSize: '12px',
                          }}
                          formatter={(v: unknown, name: unknown) => [`${String(v)}%`, String(name)]}
                        />
                      </PieChart>
                    </ResponsiveContainer>
                    {dominantModality && (
                      <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                        <span className="text-lg font-bold tabular-nums">{dominantModality.pct}%</span>
                        <span className="text-[9px] text-muted-foreground text-center max-w-[48px] leading-tight">{dominantModality.label}</span>
                      </div>
                    )}
                  </div>
                  <div className="flex flex-wrap gap-x-4 gap-y-1.5">
                    {modalityBreakdown.map((m) => (
                      <div key={m.id} className="flex items-center gap-1.5 text-xs">
                        <span className="size-2.5 rounded-sm shrink-0" style={{ background: m.color }} />
                        <span className="text-muted-foreground">{m.label}</span>
                        <span className="font-medium tabular-nums">{m.pct}%</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Weekly consistency */}
          <div>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Weekly Consistency (12 weeks)</h2>
            <div className="rounded-xl border bg-card p-4">
              <ResponsiveContainer width="100%" height={80}>
                <BarChart data={weeklyConsistency} margin={{ top: 4, right: 4, left: -28, bottom: 0 }}>
                  <XAxis
                    dataKey="label"
                    tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
                    axisLine={false}
                    tickLine={false}
                    interval={2}
                  />
                  <YAxis hide />
                  <RechartTooltip
                    cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }}
                    contentStyle={{
                      backgroundColor: 'var(--card)',
                      border: '1px solid var(--border)',
                      borderRadius: '8px',
                      fontSize: '12px',
                    }}
                    formatter={(v: unknown) => [`${String(v)} session${Number(v) !== 1 ? 's' : ''}`, 'Week']}
                  />
                  <Bar dataKey="count" radius={[2, 2, 0, 0]}>
                    {weeklyConsistency.map((entry, i) => (
                      <Cell key={i} fill={consistencyColor(entry.count)} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
              <div className="flex items-center gap-3 mt-2 text-[10px] text-muted-foreground">
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-emerald-500" /> 1–2</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-sky-400" /> 3–4</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-amber-400" /> 5–6</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-red-500" /> 7+</span>
              </div>
            </div>
          </div>
        </>
      )}
    </>
  )
}

// ── Load Tab ───────────────────────────────────────────────────────────────────

/** "3 workouts from the heart-rate series, 1 estimated from avg/max HR". */
function zoneFootnote(measured: number, estimated: number): string {
  const n = (k: number) => `${k} workout${k === 1 ? '' : 's'}`
  if (measured === 0) return `${n(estimated)}, estimated from avg/max HR`
  return estimated > 0
    ? `${n(measured)} from the heart-rate series, ${estimated} estimated from avg/max HR`
    : `${n(measured)} from the heart-rate series`
}

function LoadTab({ period, onPeriodChange }: { period: Period; onPeriodChange: (p: Period) => void }) {
  // Zone minutes over the period from the per-workout metrics cache — the
  // numbers the weekly load and PMC are built from. This used to estimate
  // every workout from its mean HR alone, ignoring the samples.
  const { data: summary } = useLoadSummary(period)
  const zoneData = useMemo(() => {
    const m = summary?.zones?.minutes
    if (!m) return null
    const colors = ['#10b981', '#38bdf8', '#f59e0b', '#f97316', '#ef4444']
    return m.map((minutes, i) => ({ zone: `Z${i + 1}`, minutes: Math.round(minutes), color: colors[i] }))
  }, [summary])

  return (
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-8">

      <VolumeSection period={period} onPeriodChange={onPeriodChange} />

      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Weekly Training Load</h2>
        <div className="rounded-xl border bg-card p-4">
          <WeeklyLoadChart />
        </div>
      </div>

      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Performance Management (CTL · ATL · Form)</h2>
        <div className="rounded-xl border bg-card p-4">
          <PMCChart />
        </div>
      </div>

      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">HR Zone Distribution</h2>
        <div className="rounded-xl border bg-card p-4">
          {zoneData ? (
            <div className="space-y-2">
              <div className="flex items-center gap-3 text-[11px] text-muted-foreground mb-3">
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-emerald-500" /> Z1 Recovery</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-sky-400" /> Z2 Aerobic</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-amber-400" /> Z3 Tempo</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-orange-400" /> Z4 Threshold</span>
                <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-red-500" /> Z5 VO2max</span>
              </div>
              <ResponsiveContainer width="100%" height={100}>
                <BarChart data={zoneData} margin={{ top: 0, right: 8, left: -20, bottom: 0 }}>
                  <XAxis
                    dataKey="zone"
                    tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis
                    tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
                    axisLine={false}
                    tickLine={false}
                    unit="m"
                  />
                  <RechartTooltip
                    cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }}
                    contentStyle={{
                      backgroundColor: 'var(--card)',
                      border: '1px solid var(--border)',
                      borderRadius: '8px',
                      fontSize: '12px',
                    }}
                    formatter={(v: unknown) => {
                      const mins = Number(v)
                      const h = Math.floor(mins / 60)
                      const m = mins % 60
                      return [h > 0 ? `${h}h ${m}m` : `${m}m`, 'Time']
                    }}
                  />
                  <Bar dataKey="minutes" radius={[3, 3, 0, 0]}>
                    {zoneData.map((entry, i) => (
                      <Cell key={i} fill={entry.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
              <p className="text-[10px] text-muted-foreground/60 mt-1">
                {zoneFootnote(summary?.zones?.workoutsMeasured ?? 0, summary?.zones?.workoutsEstimated ?? 0)}
              </p>
            </div>
          ) : (
            <div className="flex h-24 items-center justify-center">
              <p className="text-sm text-muted-foreground">No HR data available for this period</p>
            </div>
          )}
        </div>
      </div>

    </div>
  )
}

export function WorkoutAnalytics() {
  // URL-driven so Home cards and the /bio redirect can land on a tab.
  const [searchParams, setSearchParams] = useSearchParams()
  // `development` is the tab's name before 2026-10-13, when both clients
  // settled on Blocks (the phone's segment control cannot fit the long word).
  const rawTab = searchParams.get('tab')
  const tabParam = rawTab === 'development' ? 'blocks' : rawTab
  const activeTab: SubTab = tabParam && SUB_TAB_IDS.has(tabParam) ? (tabParam as SubTab) : 'program'
  function setActiveTab(tab: SubTab) {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (tab === 'program') next.delete('tab')
        else next.set('tab', tab)
        return next
      },
      { replace: true }
    )
  }
  const [period, setPeriod] = useState<Period>('30d')

  return (
    <motion.div
      key="workout-analytics"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <BarChart3 className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Analytics</h1>
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <TabSelector active={activeTab} onChange={setActiveTab} tabs={SUB_TABS} />
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'program'  && <ProgramTab />}
        {activeTab === 'progress' && (
          <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
            <ProgressionTab />
          </div>
        )}
        {activeTab === 'blocks'   && <DevelopmentTab />}
        {activeTab === 'load'     && <LoadTab period={period} onPeriodChange={setPeriod} />}
        {activeTab === 'recovery' && <RecoveryTab />}
      </div>
    </motion.div>
  )
}
