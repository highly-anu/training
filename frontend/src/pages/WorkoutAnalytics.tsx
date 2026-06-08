import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  BarChart3,
  Activity,
  Timer,
  Footprints,
  MountainSnow,
  Flame,
  ArrowDownToLine,
  FileText,
  ChevronRight,
} from 'lucide-react'
import { format, parseISO, subDays, startOfWeek, endOfWeek } from 'date-fns'
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
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { computeHRZones, getEffectiveMaxHR, DEFAULT_ZONE_BOUNDARIES } from '@/lib/hrZones'
import { Badge } from '@/components/ui/badge'
import type { ImportedWorkout, ModalityId } from '@/api/types'

// ── Types ──────────────────────────────────────────────────────────────────────

type SubTab = 'overview' | 'load' | 'activity'
type Period = '7d' | '30d' | '3m' | '1y' | 'all'

const SUB_TABS: { id: SubTab; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'load',     label: 'Load'     },
  { id: 'activity', label: 'Activity' },
]

const PERIODS: { id: Period; label: string; days: number | null }[] = [
  { id: '7d',  label: '7d',   days: 7   },
  { id: '30d', label: '30d',  days: 30  },
  { id: '3m',  label: '3m',   days: 90  },
  { id: '1y',  label: '1y',   days: 365 },
  { id: 'all', label: 'All',  days: null },
]

// ── Helpers ────────────────────────────────────────────────────────────────────

function formatActivityType(raw: string): string {
  return raw.replace(/HKWorkoutActivityType/g, '').replace(/([a-z])([A-Z])/g, '$1 $2').trim() || raw
}

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

function useFilteredWorkouts(period: Period): ImportedWorkout[] {
  const workouts = useBioStore((s) => s.importedWorkouts)
  return useMemo(() => {
    const entry = PERIODS.find((p) => p.id === period)
    if (!entry?.days) return workouts
    const cutoff = subDays(new Date(), entry.days)
    return workouts.filter((w) => {
      try { return parseISO(w.date) >= cutoff }
      catch { return false }
    })
  }, [workouts, period])
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

function OverviewTab({ period, onPeriodChange }: { period: Period; onPeriodChange: (p: Period) => void }) {
  const filtered = useFilteredWorkouts(period)
  const allWorkouts = useBioStore((s) => s.importedWorkouts)

  const stats = useMemo(() => {
    const totalMin = filtered.reduce((s, w) => s + w.durationMinutes, 0)
    const distanceKm = filtered.reduce((s, w) => {
      const v = w.distance?.value ?? 0
      const unit = w.distance?.unit ?? 'km'
      return s + (unit === 'm' ? v / 1000 : v)
    }, 0)
    const elevationM = filtered.reduce((s, w) => s + (w.elevation?.gain ?? 0), 0)
    const calories = filtered.reduce((s, w) => s + (w.calories ?? 0), 0)
    const hasDistance = filtered.some((w) => w.distance != null)
    const hasElevation = filtered.some((w) => w.elevation != null)
    const hasCals = filtered.some((w) => w.calories != null)
    return {
      sessions: filtered.length,
      hours: totalMin > 0 ? fmtHours(totalMin) : null,
      distance: hasDistance && distanceKm > 0 ? fmtDist(distanceKm) : null,
      elevation: hasElevation && elevationM > 0 ? fmtElev(elevationM) : null,
      calories: hasCals && calories > 0 ? `${Math.round(calories).toLocaleString()} kcal` : null,
    }
  }, [filtered])

  // Activity type breakdown (top 8 by training minutes)
  const activityBreakdown = useMemo(() => {
    const map = new Map<string, { minutes: number; sessions: number; modalityId: ModalityId | null }>()
    for (const w of filtered) {
      const key = formatActivityType(w.activityType)
      const existing = map.get(key) ?? { minutes: 0, sessions: 0, modalityId: w.inferredModalityId ?? null }
      map.set(key, { minutes: existing.minutes + w.durationMinutes, sessions: existing.sessions + 1, modalityId: existing.modalityId })
    }
    return Array.from(map.entries())
      .map(([type, d]) => ({
        type,
        hours: Math.round((d.minutes / 60) * 10) / 10,
        sessions: d.sessions,
        modalityId: d.modalityId,
        color: d.modalityId ? MODALITY_COLORS[d.modalityId]?.hex ?? '#94a3b8' : '#94a3b8',
      }))
      .sort((a, b) => b.hours - a.hours)
      .slice(0, 8)
  }, [filtered])

  // Modality breakdown (donut data)
  const modalityBreakdown = useMemo(() => {
    const map = new Map<string, number>()
    for (const w of filtered) {
      const key = w.inferredModalityId ?? '__unclassified__'
      map.set(key, (map.get(key) ?? 0) + w.durationMinutes)
    }
    const total = filtered.reduce((s, w) => s + w.durationMinutes, 0) || 1
    return Array.from(map.entries())
      .map(([id, minutes]) => ({
        id,
        label: id === '__unclassified__' ? 'Unclassified' : (MODALITY_COLORS[id as ModalityId]?.label ?? id),
        pct: Math.round((minutes / total) * 100),
        color: id === '__unclassified__' ? '#475569' : (MODALITY_COLORS[id as ModalityId]?.hex ?? '#94a3b8'),
      }))
      .sort((a, b) => b.pct - a.pct)
  }, [filtered])

  // 12-week consistency (regardless of period)
  const weeklyConsistency = useMemo(() => {
    const now = new Date()
    const weeks: { label: string; count: number }[] = []
    const weekOpts = { weekStartsOn: 1 } as const  // Monday-anchored weeks
    for (let i = 11; i >= 0; i--) {
      const anchor = subDays(now, i * 7)
      const weekStart = startOfWeek(anchor, weekOpts)
      const weekEnd = endOfWeek(anchor, weekOpts)
      const count = allWorkouts.filter((w) => {
        try {
          const d = parseISO(w.date)
          return d >= weekStart && d <= weekEnd
        } catch { return false }
      }).length
      weeks.push({ label: i === 0 ? 'This wk' : format(weekStart, 'MMM d'), count })
    }
    return weeks
  }, [allWorkouts])

  function consistencyColor(count: number): string {
    if (count === 0) return 'var(--color-muted)'
    if (count <= 2) return '#10b981'
    if (count <= 4) return '#38bdf8'
    if (count <= 6) return '#f59e0b'
    return '#ef4444'
  }

  const dominantModality = modalityBreakdown[0]

  return (
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-8">
      {/* Period selector */}
      <div className="flex items-center gap-3">
        <span className="text-xs text-muted-foreground">Period</span>
        <PeriodSelector active={period} onChange={onPeriodChange} />
        {filtered.length > 0 && (
          <span className="text-xs text-muted-foreground ml-auto">{filtered.length} workout{filtered.length !== 1 ? 's' : ''}</span>
        )}
      </div>

      {/* KPI row */}
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Totals</h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
          <KpiCard label="Sessions"  value={stats.sessions > 0 ? String(stats.sessions) : null} icon={Activity}     color="text-primary"        />
          <KpiCard label="Time"      value={stats.hours}         icon={Timer}        color="text-sky-400"        />
          <KpiCard label="Distance"  value={stats.distance}      icon={Footprints}   color="text-emerald-400"    />
          <KpiCard label="Ascended"  value={stats.elevation}     icon={MountainSnow} color="text-amber-400"      />
          <KpiCard label="Calories"  value={stats.calories}      icon={Flame}        color="text-orange-400"     />
        </div>
      </div>

      {filtered.length === 0 && (
        <div className="rounded-xl border border-dashed border-border p-12 flex flex-col items-center gap-3 text-center text-muted-foreground">
          <ArrowDownToLine className="size-8 opacity-40" />
          <p className="text-sm">No workouts in this period.</p>
          <p className="text-xs">Import files on the Import tab or select a longer period.</p>
        </div>
      )}

      {filtered.length > 0 && (
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
                      cursor={{ fill: 'rgba(255,255,255,0.04)' }}
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
                    cursor={{ fill: 'rgba(255,255,255,0.04)' }}
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
    </div>
  )
}

// ── Load Tab ───────────────────────────────────────────────────────────────────

function LoadTab({ period }: { period: Period }) {
  const filtered = useFilteredWorkouts(period)
  const dateOfBirth = useProfileStore((s) => s.dateOfBirth)
  const hrConfig = useProfileStore((s) => s.hrConfig)
  const maxHR = getEffectiveMaxHR(dateOfBirth, hrConfig?.maxHROverride)

  // Aggregate zone distribution across all filtered workouts with HR data
  const zoneData = useMemo(() => {
    const totals = { z1: 0, z2: 0, z3: 0, z4: 0, z5: 0 }
    let covered = 0
    for (const w of filtered) {
      const avg = w.heartRate.avg
      if (avg == null) continue
      const zones = computeHRZones(maxHR, [], avg, DEFAULT_ZONE_BOUNDARIES, w.heartRate.max ?? undefined)
      const dur = w.durationMinutes
      totals.z1 += (zones.z1 / 100) * dur
      totals.z2 += (zones.z2 / 100) * dur
      totals.z3 += (zones.z3 / 100) * dur
      totals.z4 += (zones.z4 / 100) * dur
      totals.z5 += (zones.z5 / 100) * dur
      covered += dur
    }
    if (covered === 0) return null
    return [
      { zone: 'Z1', minutes: Math.round(totals.z1), color: '#10b981' },
      { zone: 'Z2', minutes: Math.round(totals.z2), color: '#38bdf8' },
      { zone: 'Z3', minutes: Math.round(totals.z3), color: '#f59e0b' },
      { zone: 'Z4', minutes: Math.round(totals.z4), color: '#f97316' },
      { zone: 'Z5', minutes: Math.round(totals.z5), color: '#ef4444' },
    ]
  }, [filtered, maxHR])

  return (
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-8">

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
                    cursor={{ fill: 'rgba(255,255,255,0.04)' }}
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
              <p className="text-[10px] text-muted-foreground/60 mt-1">Estimated from avg/max HR — based on {filtered.filter((w) => w.heartRate.avg != null).length} workouts with HR data</p>
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

// ── Activity Tab ───────────────────────────────────────────────────────────────

type SortKey = 'date' | 'duration' | 'distance' | 'hr'

function ActivityTab({ period }: { period: Period }) {
  const navigate = useNavigate()
  const filtered = useFilteredWorkouts(period)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const pendingMatches = useBioStore((s) => s.pendingMatches)
  const [typeFilter, setTypeFilter] = useState<string | null>(null)
  const [sourceFilter, setSourceFilter] = useState<string | null>(null)
  const [sortKey, setSortKey] = useState<SortKey>('date')

  const activityTypes = useMemo(() => {
    const set = new Set(filtered.map((w) => formatActivityType(w.activityType)))
    return Array.from(set).sort()
  }, [filtered])

  const sources = useMemo(() => {
    const set = new Set(filtered.map((w) => w.source))
    return Array.from(set).sort()
  }, [filtered])

  const sourceLabel = (s: string) =>
    s === 'fit_file' ? 'FIT'
    : s === 'strava' ? 'Strava'
    : s === 'apple_health' || s === 'apple_watch_live' ? 'Apple Health'
    : s

  const displayed = useMemo(() => {
    let list = filtered
    if (typeFilter) list = list.filter((w) => formatActivityType(w.activityType) === typeFilter)
    if (sourceFilter) list = list.filter((w) => w.source === sourceFilter)
    return [...list].sort((a, b) => {
      if (sortKey === 'date')     return b.date.localeCompare(a.date)
      if (sortKey === 'duration') return b.durationMinutes - a.durationMinutes
      if (sortKey === 'distance') {
        const toKm = (w: ImportedWorkout) => w.distance ? (w.distance.unit === 'm' ? w.distance.value / 1000 : w.distance.value) : 0
        return toKm(b) - toKm(a)
      }
      if (sortKey === 'hr')       return (b.heartRate.avg ?? 0) - (a.heartRate.avg ?? 0)
      return 0
    })
  }, [filtered, typeFilter, sourceFilter, sortKey])

  function matchStatus(id: string): 'matched' | 'pending' | 'unmatched' {
    const m = workoutMatches.find((m) => m.importedWorkoutId === id)
    if (m && m.matchConfidence !== 'rejected') return 'matched'
    if (pendingMatches.some((p) => p.importedWorkout.id === id)) return 'pending'
    return 'unmatched'
  }

  const SORT_OPTIONS: { key: SortKey; label: string }[] = [
    { key: 'date',     label: 'Date'     },
    { key: 'duration', label: 'Duration' },
    { key: 'distance', label: 'Distance' },
    { key: 'hr',       label: 'Avg HR'   },
  ]

  return (
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-5">

      {/* Filters + sort */}
      <div className="space-y-2.5">
        {activityTypes.length > 1 && (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-muted-foreground shrink-0">Type</span>
            <button
              type="button"
              onClick={() => setTypeFilter(null)}
              className={cn('px-2.5 py-0.5 rounded-full border text-xs transition-colors', typeFilter === null ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
            >
              All
            </button>
            {activityTypes.map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTypeFilter(t === typeFilter ? null : t)}
                className={cn('px-2.5 py-0.5 rounded-full border text-xs transition-colors', typeFilter === t ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
              >
                {t}
              </button>
            ))}
          </div>
        )}
        {sources.length > 1 && (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-muted-foreground shrink-0">Source</span>
            <button
              type="button"
              onClick={() => setSourceFilter(null)}
              className={cn('px-2.5 py-0.5 rounded-full border text-xs transition-colors', sourceFilter === null ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
            >
              All
            </button>
            {sources.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setSourceFilter(s === sourceFilter ? null : s)}
                className={cn('px-2.5 py-0.5 rounded-full border text-xs transition-colors', sourceFilter === s ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
              >
                {sourceLabel(s)}
              </button>
            ))}
          </div>
        )}
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground shrink-0">Sort</span>
          {SORT_OPTIONS.map((o) => (
            <button
              key={o.key}
              type="button"
              onClick={() => setSortKey(o.key)}
              className={cn('px-2.5 py-0.5 rounded-full border text-xs transition-colors', sortKey === o.key ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
            >
              {o.label}
            </button>
          ))}
        </div>
      </div>

      {/* List */}
      {displayed.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border p-12 flex flex-col items-center gap-3 text-center text-muted-foreground">
          <ArrowDownToLine className="size-8 opacity-40" />
          <p className="text-sm">No workouts match these filters.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {displayed.map((w) => {
            const ms = matchStatus(w.id)
            const fmtDate = (() => { try { return format(parseISO(w.startTime), 'EEE, MMM d') } catch { return w.date } })()
            const distText = w.distance ? (() => {
              const v = w.distance.unit === 'm' ? w.distance.value / 1000 : w.distance.value
              return `${v.toFixed(1)} km`
            })() : null
            const modalityId = w.inferredModalityId
            const modalityColor = modalityId ? MODALITY_COLORS[modalityId] : null

            return (
              <div
                key={w.id}
                role="button"
                tabIndex={0}
                onClick={() => navigate(`/import/${encodeURIComponent(w.id)}`, { state: { workout: w } })}
                onKeyDown={(e) => e.key === 'Enter' && navigate(`/import/${encodeURIComponent(w.id)}`, { state: { workout: w } })}
                className="flex items-center gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 cursor-pointer hover:bg-card/60 transition-colors"
              >
                <FileText className="size-4 shrink-0 text-muted-foreground" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="text-sm font-medium">{formatActivityType(w.activityType)}</p>
                    {modalityColor && (
                      <Badge
                        variant="outline"
                        className={cn('text-[10px] shrink-0', modalityColor.border, modalityColor.text)}
                      >
                        {modalityColor.label}
                      </Badge>
                    )}
                    {ms === 'matched' && (
                      <Badge variant="outline" className="text-[10px] border-emerald-500/40 text-emerald-500 shrink-0">
                        matched
                      </Badge>
                    )}
                    {ms === 'pending' && (
                      <Badge variant="outline" className="text-[10px] border-amber-500/40 text-amber-500 shrink-0">
                        pending
                      </Badge>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {fmtDate}
                    {' · '}{w.durationMinutes} min
                    {distText && ` · ${distText}`}
                    {w.heartRate.avg != null && ` · ${Math.round(w.heartRate.avg)} bpm`}
                    {w.elevation?.gain ? ` · ↑${Math.round(w.elevation.gain)}m` : ''}
                  </p>
                </div>
                <ChevronRight className="size-4 shrink-0 text-muted-foreground/50" />
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

export function WorkoutAnalytics() {
  const [activeTab, setActiveTab] = useState<SubTab>('overview')
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
        {activeTab === 'overview'  && <OverviewTab  period={period} onPeriodChange={setPeriod} />}
        {activeTab === 'load'      && <LoadTab      period={period} />}
        {activeTab === 'activity'  && <ActivityTab  period={period} />}
      </div>
    </motion.div>
  )
}
