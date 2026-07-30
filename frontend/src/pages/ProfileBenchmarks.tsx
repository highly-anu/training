import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { User, Dumbbell, AlertTriangle, Trophy, Calendar, LogOut, Heart, RotateCcw } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from '@/components/ui/select'
import { LevelBar } from '@/components/benchmarks/LevelBar'
import { useProfileStore } from '@/store/profileStore'
import { useAuthStore } from '@/store/authStore'
import { useBioStore } from '@/store/bioStore'
import { useBenchmarks } from '@/api/benchmarks'
import { useInjuryFlags } from '@/api/constraints'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { getEffectiveMaxHR, maxHRFromDOB, zoneBoundariesToBpm, DEFAULT_ZONE_BOUNDARIES } from '@/lib/hrZones'
import type { Day, DaySchedule, EquipmentId, InjuryFlagId, SessionType, TrainingLevel } from '@/api/types'

// ── Types ──────────────────────────────────────────────────────────────────────

type SubTab = 'equipment' | 'injuries' | 'benchmarks' | 'schedule' | 'heartrate'

interface SubTabItem {
  id: SubTab
  label: string
  Icon: React.ElementType
}

const SUB_TABS: SubTabItem[] = [
  { id: 'equipment',  label: 'Equipment',  Icon: Dumbbell      },
  { id: 'injuries',   label: 'Injuries',   Icon: AlertTriangle },
  { id: 'benchmarks', label: 'Benchmarks', Icon: Trophy        },
  { id: 'schedule',   label: 'Schedule',   Icon: Calendar      },
  { id: 'heartrate',  label: 'Heart Rate', Icon: Heart         },
]

// ── Equipment by category ──────────────────────────────────────────────────────

const EQUIPMENT_CATEGORIES = [
  {
    name: 'Strength',
    color: MODALITY_COLORS.max_strength.hex,
    items: ['barbell', 'rack', 'plates'] as EquipmentId[],
  },
  {
    name: 'Power & Kettlebell',
    color: MODALITY_COLORS.power.hex,
    items: ['kettlebell', 'dumbbell'] as EquipmentId[],
  },
  {
    name: 'Bodyweight & Gymnastics',
    color: MODALITY_COLORS.relative_strength.hex,
    items: ['pull_up_bar', 'rings', 'parallettes', 'dip_bar'] as EquipmentId[],
  },
  {
    name: 'Aerobic & Conditioning',
    color: MODALITY_COLORS.aerobic_base.hex,
    items: ['rower', 'assault_bike', 'ski_erg', 'jump_rope', 'pool'] as EquipmentId[],
  },
  {
    name: 'GPP & Durability',
    color: MODALITY_COLORS.durability.hex,
    items: ['ruck_pack', 'sandbag', 'sled', 'medicine_ball', 'box'] as EquipmentId[],
  },
  {
    name: 'Mobility & Prehab',
    color: MODALITY_COLORS.rehab.hex,
    items: ['resistance_band', 'foam_roller', 'ghd'] as EquipmentId[],
  },
  {
    name: 'General',
    color: '#6366f1',
    items: ['rope', 'open_space'] as EquipmentId[],
  },
]

// ── Equipment Overview ─────────────────────────────────────────────────────────

function EquipmentOverview() {
  const equipment = useProfileStore((s) => s.equipment)
  const setEquipment = useProfileStore((s) => s.setEquipment)

  const selectedSet = new Set(equipment)

  function toggleEquipment(id: EquipmentId) {
    const newEquip = selectedSet.has(id)
      ? equipment.filter((e) => e !== id)
      : [...equipment, id]
    setEquipment(newEquip)
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-3xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Profile settings
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            Available equipment.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Select all equipment you have access to. This filters archetypes and exercises during program generation.
          </p>
        </div>

        {EQUIPMENT_CATEGORIES.map((category) => (
          <div key={category.name} className="space-y-3">
            <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
              {category.name}
            </h3>
            <div className="grid grid-cols-2 gap-2">
              {category.items.map((eq) => {
                const isSelected = selectedSet.has(eq)
                return (
                  <button
                    key={eq}
                    onClick={() => toggleEquipment(eq)}
                    className={cn(
                      'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-left transition-all cursor-pointer',
                      isSelected
                        ? 'border-primary/40 bg-primary/10 shadow-sm'
                        : 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20'
                    )}
                    style={{
                      borderLeftColor: isSelected ? category.color : undefined,
                      borderLeftWidth: isSelected ? 2 : 1
                    }}
                  >
                    <div className="min-w-0 flex-1">
                      <p className="text-xs font-medium leading-snug truncate">
                        {eq.replace(/_/g, ' ')}
                      </p>
                      <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                        {isSelected ? 'Available' : 'Not selected'}
                      </p>
                    </div>
                  </button>
                )
              })}
            </div>
          </div>
        ))}

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          {selectedSet.size} items selected
        </p>

      </div>
    </div>
  )
}

// ── Injuries Overview ──────────────────────────────────────────────────────────

function InjuriesOverview() {
  const { data: flags = [], isLoading } = useInjuryFlags()
  const injuryFlags = useProfileStore((s) => s.injuryFlags)
  const toggleInjuryFlag = useProfileStore((s) => s.toggleInjuryFlag)

  const selectedSet = new Set(injuryFlags)

  if (isLoading) return <LoadingCard />

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Profile settings
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            Active injury flags.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Select any current injuries or movement limitations. The system will exclude contraindicated exercises and suggest alternatives.
          </p>
        </div>

        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            {flags.map((flag) => {
              const isSelected = selectedSet.has(flag.id as InjuryFlagId)
              return (
                <button
                  key={flag.id}
                  onClick={() => toggleInjuryFlag(flag.id as InjuryFlagId)}
                  className={cn(
                    'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-left transition-all cursor-pointer',
                    isSelected
                      ? 'border-destructive/40 bg-destructive/10 shadow-sm'
                      : 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20'
                  )}
                  style={{
                    borderLeftColor: isSelected ? '#ef4444' : undefined,
                    borderLeftWidth: isSelected ? 2 : 1
                  }}
                >
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-medium leading-snug truncate">
                      {flag.name}
                    </p>
                    <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                      {flag.excluded_movement_patterns?.length || 0} patterns excluded
                    </p>
                  </div>
                </button>
              )
            })}
          </div>
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          {selectedSet.size} active {selectedSet.size === 1 ? 'injury' : 'injuries'}
        </p>

      </div>
    </div>
  )
}

// ── Benchmarks Overview ────────────────────────────────────────────────────────

interface PrInputProps {
  benchId: string
  unit: string
}

function PrInput({ benchId, unit }: PrInputProps) {
  const logs = useProfileStore((s) => s.performanceLogs)
  const logPerformance = useProfileStore((s) => s.logPerformance)
  const removePerformanceLog = useProfileStore((s) => s.removePerformanceLog)

  const stored = logs[benchId]?.at(-1)?.value
  const [draft, setDraft] = useState(stored !== undefined ? String(stored) : '')

  useEffect(() => {
    setDraft(stored !== undefined ? String(stored) : '')
  }, [stored])

  function commit() {
    const n = parseFloat(draft)
    if (!isNaN(n) && n > 0) {
      logPerformance(benchId, n)
    } else if (draft.trim() === '') {
      removePerformanceLog(benchId)
    }
  }

  return (
    <div className="flex items-center gap-1">
      <input
        type="number"
        min={0}
        step="any"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => { if (e.key === 'Enter') { commit(); (e.target as HTMLInputElement).blur() } }}
        placeholder="—"
        className="w-16 h-7 rounded border border-border/30 bg-card/40 text-right text-xs text-foreground placeholder:text-muted-foreground/30 hover:border-input focus:border-primary focus:bg-card focus:outline-none px-2 transition-colors"
      />
      <span className="text-[10px] text-muted-foreground whitespace-nowrap">{unit}</span>
    </div>
  )
}

function BenchmarksOverview() {
  const { data: benchmarks = [], isLoading } = useBenchmarks()
  const logs = useProfileStore((s) => s.performanceLogs)

  if (isLoading) return <LoadingCard />

  const categories = ['strength', 'conditioning', 'cell'] as const
  const byCategory = {
    strength: benchmarks.filter(b => b.category === 'strength'),
    conditioning: benchmarks.filter(b => b.category === 'conditioning'),
    cell: benchmarks.filter(b => b.category === 'cell'),
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-3xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Performance tracking
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {benchmarks.length} benchmark standards.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Track your personal records against standardized benchmarks. Your PRs are saved to your profile and used to calculate training loads.
          </p>
        </div>

        {categories.map((cat) => (
          byCategory[cat].length > 0 && (
            <div key={cat} className="space-y-3">
              <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
                {cat}
              </h3>
              <div className="grid gap-3">
                {byCategory[cat].map((bench) => {
                  const userValue = logs[bench.id]?.at(-1)?.value
                  return (
                    <div key={bench.id} className="rounded-lg border border-border/30 bg-card/40 p-4 space-y-2.5">
                      <div className="flex items-center justify-between gap-3">
                        <p className="text-sm font-medium truncate">{bench.name}</p>
                        <PrInput benchId={bench.id} unit={bench.unit} />
                      </div>
                      <LevelBar
                        standards={bench.standards as Record<'entry' | 'intermediate' | 'advanced' | 'elite', number>}
                        unit={bench.unit}
                        lowerIsBetter={bench.lower_is_better ?? false}
                        userValue={userValue}
                      />
                    </div>
                  )
                })}
              </div>
            </div>
          )
        ))}

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          {Object.values(logs).length} PRs logged
        </p>

      </div>
    </div>
  )
}

// ── Schedule Overview ──────────────────────────────────────────────────────────

const DAYS: Day[] = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

function SessionButton({ type, onClick, label }: { type: SessionType; onClick: () => void; label: string }) {
  const config = {
    rest: { text: 'Rest', color: 'bg-muted/40 text-muted-foreground/50 border-muted-foreground/20' },
    short: { text: 'Short', color: 'bg-yellow-500/15 text-yellow-700 dark:text-yellow-300 border-yellow-500/30' },
    long: { text: 'Long', color: 'bg-sky-500/15 text-sky-700 dark:text-sky-300 border-sky-500/30' },
    mobility: { text: 'Mobility', color: 'bg-purple-500/15 text-purple-700 dark:text-purple-300 border-purple-500/30' },
  }

  const { text, color } = config[type]

  return (
    <button
      onClick={onClick}
      className={cn(
        'px-2 py-1 rounded text-[10px] font-medium uppercase tracking-wider transition-all border',
        color,
        'hover:opacity-80'
      )}
      title={`${label}: ${text} (click to cycle)`}
    >
      {text}
    </button>
  )
}

function getSessionSummary(sessions: SessionType[]): string {
  const times: Record<SessionType, string> = {
    rest: '',
    short: '30-45min',
    long: '60+ min',
    mobility: '15-20min',
  }

  const parts = sessions
    .map(s => s !== 'rest' ? times[s] : null)
    .filter((t): t is string => t !== null)

  if (parts.length === 0) return 'Rest day'
  if (parts.length === 1) return parts[0]
  return parts.join(' + ')
}

function ScheduleOverview() {
  const savedSchedule = useProfileStore((s) => s.weeklySchedule)
  const setWeeklySchedule = useProfileStore((s) => s.setWeeklySchedule)

  const defaultSchedule: Record<Day, DaySchedule> = {
    Monday: { session1: 'long', session2: 'rest', session3: 'rest', session4: 'rest' },
    Tuesday: { session1: 'short', session2: 'mobility', session3: 'rest', session4: 'rest' },
    Wednesday: { session1: 'long', session2: 'rest', session3: 'rest', session4: 'rest' },
    Thursday: { session1: 'short', session2: 'mobility', session3: 'rest', session4: 'rest' },
    Friday: { session1: 'long', session2: 'rest', session3: 'rest', session4: 'rest' },
    Saturday: { session1: 'long', session2: 'rest', session3: 'rest', session4: 'rest' },
    Sunday: { session1: 'rest', session2: 'rest', session3: 'rest', session4: 'rest' },
  }

  const [schedule, setSchedule] = useState<Record<Day, DaySchedule>>(savedSchedule || defaultSchedule)

  function cycleSession(day: Day, slot: keyof DaySchedule) {
    setSchedule((prev) => {
      const current = prev[day][slot]
      const next: SessionType =
        current === 'rest' ? 'short' :
        current === 'short' ? 'long' :
        current === 'long' ? 'mobility' : 'rest'
      return {
        ...prev,
        [day]: { ...prev[day], [slot]: next }
      }
    })
  }

  // Sync schedule changes to ProfileStore
  useEffect(() => {
    setWeeklySchedule(schedule)
  }, [schedule, setWeeklySchedule])

  const trainingDays = Object.values(schedule).filter(
    d => d.session1 !== 'rest' || d.session2 !== 'rest' || d.session3 !== 'rest' || d.session4 !== 'rest'
  ).length
  const totalSessions = Object.values(schedule).reduce(
    (sum, d) => {
      return sum +
        (d.session1 !== 'rest' ? 1 : 0) +
        (d.session2 !== 'rest' ? 1 : 0) +
        (d.session3 !== 'rest' ? 1 : 0) +
        (d.session4 !== 'rest' ? 1 : 0)
    },
    0
  )

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training schedule
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            Weekly availability.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Configure your weekly schedule with primary and optional secondary sessions.
            <span className="font-medium"> Short</span> = 30-45min,
            <span className="font-medium"> Long</span> = 60+ min,
            <span className="font-medium"> Mobility</span> = 15-20min.
            Click each session to cycle through types.
          </p>
        </div>

        <div className="space-y-2">
          {DAYS.map((day) => {
            const { session1, session2, session3, session4 } = schedule[day]
            const hasAnySession = session1 !== 'rest' || session2 !== 'rest' || session3 !== 'rest' || session4 !== 'rest'
            const primaryColor =
              session1 === 'long' ? MODALITY_COLORS.aerobic_base.hex :
              session1 === 'short' ? MODALITY_COLORS.power.hex :
              session1 === 'mobility' ? MODALITY_COLORS.mobility.hex : undefined

            const showSession2 = session1 !== 'rest' || session2 !== 'rest'
            const showSession3 = session2 !== 'rest' || session3 !== 'rest'
            const showSession4 = session3 !== 'rest' || session4 !== 'rest'

            return (
              <div
                key={day}
                className={cn(
                  'w-full rounded-lg border px-4 py-3 transition-all',
                  hasAnySession
                    ? 'border-primary/40 bg-primary/10 shadow-sm'
                    : 'border-border/30 bg-card/40'
                )}
                style={{
                  borderLeftColor: primaryColor,
                  borderLeftWidth: session1 !== 'rest' ? 3 : 1
                }}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className={cn(
                      'size-2 rounded-full transition-colors shrink-0',
                      hasAnySession ? 'bg-primary' : 'bg-muted-foreground/30'
                    )} />
                    <p className="text-sm font-medium w-20 shrink-0">{day}</p>
                    <div className="flex items-center gap-1.5 min-w-0 flex-wrap">
                      <div className="flex items-center gap-1">
                        <span className="text-[9px] text-muted-foreground/40 font-medium">1:</span>
                        <SessionButton
                          type={session1}
                          onClick={() => cycleSession(day, 'session1')}
                          label="Session 1"
                        />
                      </div>
                      {showSession2 && (
                        <div className="flex items-center gap-1">
                          <span className="text-[9px] text-muted-foreground/40 font-medium">2:</span>
                          <SessionButton
                            type={session2}
                            onClick={() => cycleSession(day, 'session2')}
                            label="Session 2"
                          />
                        </div>
                      )}
                      {showSession3 && (
                        <div className="flex items-center gap-1">
                          <span className="text-[9px] text-muted-foreground/40 font-medium">3:</span>
                          <SessionButton
                            type={session3}
                            onClick={() => cycleSession(day, 'session3')}
                            label="Session 3"
                          />
                        </div>
                      )}
                      {showSession4 && (
                        <div className="flex items-center gap-1">
                          <span className="text-[9px] text-muted-foreground/40 font-medium">4:</span>
                          <SessionButton
                            type={session4}
                            onClick={() => cycleSession(day, 'session4')}
                            label="Session 4"
                          />
                        </div>
                      )}
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground shrink-0">
                    {getSessionSummary([session1, session2, session3, session4])}
                  </p>
                </div>
              </div>
            )
          })}
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          {trainingDays} {trainingDays === 1 ? 'day' : 'days'} • {totalSessions} total {totalSessions === 1 ? 'session' : 'sessions'}
        </p>

      </div>
    </div>
  )
}

// ── HR Settings ───────────────────────────────────────────────────────────────

const ZONE_COLORS = ['#94a3b8', '#38bdf8', '#fbbf24', '#f97316', '#ef4444']
const ZONE_LABELS = ['Recovery', 'Aerobic', 'Tempo', 'Threshold', 'Max']

function HRSettingsOverview() {
  const dob = useProfileStore((s) => s.dateOfBirth ?? null)
  const hrConfig = useProfileStore((s) => s.hrConfig)
  const setHRConfig = useProfileStore((s) => s.setHRConfig)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)

  const formulaMax = maxHRFromDOB(dob)
  const effectiveMax = getEffectiveMaxHR(dob, hrConfig.maxHROverride ?? undefined)
  const boundaries = hrConfig.zoneBoundaries ?? DEFAULT_ZONE_BOUNDARIES
  void boundaries // used via localBoundaries below

  // Observed max from workout history
  const observedMax = importedWorkouts.reduce((best, w) => {
    const m = w.heartRate.max
    return m != null && m > best ? m : best
  }, 0) || null

  const [overrideInput, setOverrideInput] = useState(
    hrConfig.maxHROverride != null ? String(hrConfig.maxHROverride) : ''
  )
  const [localBoundaries, setLocalBoundaries] = useState<number[]>(boundaries)

  // Keep localBoundaries in sync when hrConfig changes from outside
  useEffect(() => {
    setLocalBoundaries(hrConfig.zoneBoundaries ?? DEFAULT_ZONE_BOUNDARIES)
  }, [hrConfig.zoneBoundaries])

  const localMax = overrideInput !== '' && !isNaN(Number(overrideInput))
    ? Number(overrideInput)
    : effectiveMax
  const localBpmBounds = zoneBoundariesToBpm(localMax, localBoundaries)

  function saveOverride() {
    const val = Number(overrideInput)
    if (!overrideInput || isNaN(val) || val < 100 || val > 250) return
    setHRConfig({ ...hrConfig, maxHROverride: val })
  }

  function clearOverride() {
    setOverrideInput('')
    setHRConfig({ ...hrConfig, maxHROverride: null })
  }

  function updateBoundary(idx: number, pct: number) {
    const next = [...localBoundaries]
    // Enforce minimum 3% gap between adjacent boundaries
    const min = idx === 0 ? 0.40 : localBoundaries[idx - 1] + 0.03
    const max = idx === localBoundaries.length - 1 ? 0.97 : localBoundaries[idx + 1] - 0.03
    next[idx] = Math.min(max, Math.max(min, pct))
    setLocalBoundaries(next)
    setHRConfig({ ...hrConfig, zoneBoundaries: next })
  }

  function resetToDefaults() {
    setLocalBoundaries(DEFAULT_ZONE_BOUNDARIES)
    setOverrideInput('')
    setHRConfig({})
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Profile settings
          </p>
          <h2 className="text-2xl font-semibold leading-snug">Heart rate zones.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Set your real max HR and adjust zone boundaries to match your physiology.
            Both the web app and iOS read from this configuration.
          </p>
        </div>

        {/* Max HR */}
        <div className="space-y-4">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
            Max Heart Rate
          </h3>

          <div className="rounded-lg border border-border bg-card p-4 space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div className="space-y-1">
                <p className="text-sm font-medium">
                  {effectiveMax} bpm
                  {hrConfig.maxHROverride != null
                    ? ' (manual override)'
                    : formulaMax
                      ? ` (formula: 220 − ${new Date().getFullYear() - new Date(dob!).getFullYear()})`
                      : ' (default fallback)'}
                </p>
                {observedMax && (
                  <p className="text-xs text-muted-foreground">
                    Observed max from workouts:&nbsp;
                    <span className={cn('font-medium', observedMax > effectiveMax ? 'text-amber-700 dark:text-amber-300' : 'text-foreground')}>
                      {observedMax} bpm
                    </span>
                    {observedMax > effectiveMax && (
                      <span className="ml-1 text-amber-700/70 dark:text-amber-300/70">— consider updating</span>
                    )}
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="number"
                min={100}
                max={250}
                placeholder="e.g. 187"
                value={overrideInput}
                onChange={(e) => setOverrideInput(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && saveOverride()}
                className="w-28 h-8 rounded-md border border-border bg-background px-3 text-sm tabular-nums focus:outline-none focus:ring-1 focus:ring-primary"
              />
              <Button size="sm" onClick={saveOverride} disabled={!overrideInput}>
                Save
              </Button>
              {hrConfig.maxHROverride != null && (
                <Button size="sm" variant="ghost" onClick={clearOverride} className="text-muted-foreground">
                  Clear override
                </Button>
              )}
            </div>
          </div>
        </div>

        {/* Zone boundaries */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
              Zone Boundaries
            </h3>
            <Button size="sm" variant="ghost" onClick={resetToDefaults} className="text-muted-foreground gap-1.5 h-7 text-xs">
              <RotateCcw className="size-3" /> Reset to defaults
            </Button>
          </div>

          <div className="space-y-3">
            {localBoundaries.map((boundary, idx) => {
              const zoneAbove = idx + 1
              return (
                <div key={idx} className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block size-2 rounded-sm" style={{ background: ZONE_COLORS[zoneAbove] }} />
                      <span className="text-muted-foreground">Z{zoneAbove}/Z{zoneAbove + 1} boundary</span>
                    </span>
                    <span className="tabular-nums font-medium">
                      {Math.round(boundary * 100)}% · {localBpmBounds[idx]} bpm
                    </span>
                  </div>
                  <input
                    type="range"
                    min={40}
                    max={97}
                    step={1}
                    value={Math.round(boundary * 100)}
                    onChange={(e) => updateBoundary(idx, Number(e.target.value) / 100)}
                    className="w-full accent-primary h-1.5"
                  />
                </div>
              )
            })}
          </div>
        </div>

        {/* Live zone preview */}
        <div className="space-y-3">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
            Zone Preview
          </h3>
          <div className="rounded-lg border border-border overflow-hidden">
            {ZONE_LABELS.map((label, i) => {
              const lo = i === 0 ? 0 : localBpmBounds[i - 1]
              const hi = i === 4 ? '∞' : localBpmBounds[i]
              return (
                <div
                  key={i}
                  className="flex items-center gap-3 px-4 py-2.5 border-b border-border last:border-0"
                >
                  <span
                    className="inline-block size-3 rounded-sm shrink-0"
                    style={{ background: ZONE_COLORS[i] }}
                  />
                  <span className="text-xs font-medium w-4">Z{i + 1}</span>
                  <span className="text-xs text-muted-foreground flex-1">{label}</span>
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {lo} – {hi} bpm
                  </span>
                </div>
              )
            })}
          </div>
        </div>

      </div>
    </div>
  )
}

// ── Tab Selector (like Explore) ───────────────────────────────────────────────

function TabSelector({
  active,
  onChange,
}: {
  active: SubTab
  onChange: (t: SubTab) => void
}) {
  return (
    <div className="flex items-center gap-1">
      {SUB_TABS.map((tab) => {
        const isActive = tab.id === active
        const Icon = tab.Icon
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1 text-xs rounded border transition-colors',
              isActive
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            <Icon className="size-3.5" />
            {tab.label}
          </button>
        )
      })}
    </div>
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

export function ProfileBenchmarks() {
  const navigate = useNavigate()
  const trainingLevel = useProfileStore((s) => s.trainingLevel)
  const setTrainingLevel = useProfileStore((s) => s.setTrainingLevel)
  const { user, savedAccounts, signOutCurrent, switchToAccount } = useAuthStore()

  const [activeTab, setActiveTab] = useState<SubTab>('equipment')
  const [switching, setSwitching] = useState(false)

  return (
    <motion.div
      key="profile"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <User className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Profile</h1>

        {/* Sub-tab selector (like Explore) */}
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <TabSelector active={activeTab} onChange={setActiveTab} />
        </div>

        {/* Account & Level */}
        <div className="ml-auto flex items-center gap-3">
          {user && savedAccounts.length > 1 ? (
            <Select
              value={user.email ?? ''}
              onValueChange={async (val) => {
                if (val === '__add__') { navigate('/login'); return }
                if (val === user.email) return
                setSwitching(true)
                try { await switchToAccount(val) } finally { setSwitching(false) }
              }}
              disabled={switching}
            >
              <SelectTrigger className="w-48 h-8 text-xs font-mono">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {savedAccounts.map((a) => (
                  <SelectItem key={a.email} value={a.email} className="text-xs font-mono">
                    {a.email}
                  </SelectItem>
                ))}
                <SelectSeparator />
                <SelectItem value="__add__" className="text-xs text-muted-foreground">
                  Add account →
                </SelectItem>
              </SelectContent>
            </Select>
          ) : user ? (
            <span className="text-xs font-mono text-muted-foreground">
              {user.email}
            </span>
          ) : null}

          <Select value={trainingLevel} onValueChange={(v) => setTrainingLevel(v as TrainingLevel)}>
            <SelectTrigger className="w-32 h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="novice">Novice</SelectItem>
              <SelectItem value="intermediate">Intermediate</SelectItem>
              <SelectItem value="advanced">Advanced</SelectItem>
              <SelectItem value="elite">Elite</SelectItem>
            </SelectContent>
          </Select>

          {user && (
            <Button
              variant="ghost"
              size="sm"
              onClick={signOutCurrent}
              className="h-8 text-xs text-muted-foreground hover:text-destructive"
            >
              <LogOut className="size-3.5" />
            </Button>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'equipment'  && <EquipmentOverview />}
        {activeTab === 'injuries'   && <InjuriesOverview />}
        {activeTab === 'benchmarks' && <BenchmarksOverview />}
        {activeTab === 'schedule'   && <ScheduleOverview />}
        {activeTab === 'heartrate'  && <HRSettingsOverview />}
      </div>
    </motion.div>
  )
}
