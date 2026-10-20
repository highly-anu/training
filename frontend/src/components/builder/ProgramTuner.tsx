import { useEffect, useMemo, useRef, useState } from 'react'
import { AlertTriangle, Check, Info, Layers } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useBuilderStore } from '@/store/builderStore'
// Goals removed - now philosophy-based only
import { useFrameworks } from '@/api/frameworks'
import { usePhilosophies } from '@/api/philosophies'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { sortPriorities } from '@/lib/prioritySort'
import { frameworkImpliedPriorities } from '@/lib/frameworkPriorities'
import { checkStyleCompatibility, blockingReason } from '@/lib/styleCompatibility'
import { blendExpectations } from '@/lib/feasibility'
import { builderTrack, mainFramework, trackWeeks, tracksOf } from '@/lib/tracks'
import { FrameworkDetailModal } from './FrameworkDetailModal'
import { PhaseSpine } from '@/components/shared/PhaseSpine'
import type { Framework, ModalityId } from '@/api/types'

const SECTION_LABEL = 'text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium'

export function ProgramTuner() {
  const {
    selectedGoalIds,
    selectedTrackId,
    selectedPhilosophyIds,
    sourcePriorities,
    sourceMode,
    priorityOverrides,
    numWeeks,
    eventDate,
    constraints,
    updateConstraints,
    setTrack,
    setPriorityOverrides,
    setNumWeeks,
    setEventDate,
  } = useBuilderStore()

  const { data: frameworks } = useFrameworks()
  const { data: philosophies } = usePhilosophies()
  const [detailFramework, setDetailFramework] = useState<Framework | null>(null)

  // The track the program will run, and every track the selection offers
  // (a blend may run any member's track).
  const picked = useMemo(
    () => builderTrack(philosophies, selectedPhilosophyIds, selectedTrackId, constraints.training_level),
    [philosophies, selectedPhilosophyIds, selectedTrackId, constraints.training_level],
  )
  const activeTrack = picked?.track
  const trackOptions = useMemo(() => {
    if (sourceMode !== 'philosophy' && sourceMode !== 'blend') return []
    return selectedPhilosophyIds.flatMap((pid) => {
      const phil = philosophies?.find((p) => p.id === pid)
      return tracksOf(phil).map((track) => ({ philosophy: phil!, track }))
    })
  }, [philosophies, selectedPhilosophyIds, sourceMode])

  // ── Blended priorities ─────────────────────────────────────────────────────
  // Use the priorities that ProgramSource computed (philosophy-based)
  const blendedPriorities = useMemo(() => {
    return sourcePriorities ?? {}
  }, [sourcePriorities])

  // Default priority sliders to goal/source priorities on first mount
  useEffect(() => {
    if (!priorityOverrides) {
      setPriorityOverrides({ ...blendedPriorities })
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // The framework that stands for the track (its longest phase's) — the one
  // its priorities and the reset button come from.
  const activeFw = mainFramework(activeTrack, frameworks) ?? null

  // When the user picks a different track, suggest its implied priorities.
  const isMounted = useRef(false)
  const prevTrackId = useRef(selectedTrackId)
  useEffect(() => {
    if (!isMounted.current) { isMounted.current = true; return }
    if (selectedTrackId === prevTrackId.current) return
    prevTrackId.current = selectedTrackId

    if (selectedTrackId === null) {
      setPriorityOverrides({ ...blendedPriorities })
    } else if (activeFw) {
      setPriorityOverrides(frameworkImpliedPriorities(activeFw, blendedPriorities))
    }
  }, [selectedTrackId, activeFw, blendedPriorities]) // eslint-disable-line react-hooks/exhaustive-deps

  // Expectations of the track: its framework's, or the weeks-weighted blend
  // of its phases' frameworks.
  const displayExpectations = useMemo(() => {
    if (!frameworks || !philosophies) return null
    return blendExpectations([], [], {}, {
      sourceMode: 'philosophy',
      frameworks,
      philosophies,
      selectedPhilosophyIds,
      selectedTrackId,
    })
  }, [frameworks, philosophies, selectedPhilosophyIds, selectedTrackId])

  // Framework-implied defaults for the reset button
  const fwDefaultPriorities = useMemo(() => {
    if (!activeFw?.sessions_per_week) return null
    return frameworkImpliedPriorities(activeFw, blendedPriorities)
  }, [activeFw, blendedPriorities])

  const activePriorities = priorityOverrides ?? blendedPriorities
  const sortedPriorities = sortPriorities(activePriorities)
  const totalRaw = Object.values(activePriorities).reduce((s, v) => s + (v ?? 0), 0) || 1

  function updatePriority(mod: ModalityId, rawValue: number) {
    setPriorityOverrides({ ...activePriorities, [mod]: rawValue })
  }

  // ── Duration + event date ──────────────────────────────────────────────────
  const defaultNumWeeks = useMemo(() => {
    // A multi-phase track runs all of its phases; a single repeatable block
    // takes its framework's ideal length.
    if (activeTrack && activeTrack.phases.length > 1) return trackWeeks(activeTrack)
    return displayExpectations?.ideal_weeks ?? trackWeeks(activeTrack) ?? 12
  }, [activeTrack, displayExpectations])

  const effectiveNumWeeks = numWeeks ?? defaultNumWeeks

  const weeksUntilEvent = useMemo(() => {
    if (!eventDate) return null
    const today = new Date()
    const event = new Date(eventDate)
    return Math.max(1, Math.round((event.getTime() - today.getTime()) / (7 * 24 * 60 * 60 * 1000)))
  }, [eventDate])

  const eventIsTight = weeksUntilEvent !== null && weeksUntilEvent < defaultNumWeeks

  // "Tight" state: which option did the user choose
  type TightChoice = 'fit' | 'full'
  const [tightChoice, setTightChoice] = useState<TightChoice>('fit')

  // Propagate tight choice to numWeeks
  useEffect(() => {
    if (!eventIsTight) return
    if (tightChoice === 'fit') {
      setNumWeeks(weeksUntilEvent!)
    } else {
      setNumWeeks(defaultNumWeeks)
    }
  }, [tightChoice, eventIsTight, weeksUntilEvent, defaultNumWeeks]) // eslint-disable-line react-hooks/exhaustive-deps

  // Reset the tight choice when the event date is removed, during render
  // rather than in an effect.
  const [prevEventDate, setPrevEventDate] = useState(eventDate)
  if (eventDate !== prevEventDate) {
    setPrevEventDate(eventDate)
    if (!eventDate) setTightChoice('fit')
  }

  // Reset label
  const resetLabel = 'Source default'

  return (
    <div className="space-y-8 max-w-3xl mx-auto px-8">

      {/* Header */}
      <div className="space-y-3">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
          Program configuration
        </p>
        <h2 className="text-2xl font-semibold leading-snug">
          Tune your program.
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          Choose a track, adjust modality priorities, and set program duration.
        </p>
      </div>

      {/* Program recommendations */}
      {displayExpectations && (
        <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
          <p className="text-[10px] uppercase tracking-widest text-primary/70 font-medium mb-2">
            {activeTrack && activeTrack.phases.length > 1 ? 'Full track recommendations' : 'Framework recommendations'}
          </p>
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-xs">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Ideal duration</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_weeks ?? 12} weeks
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Training days</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_days_per_week} days/week
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Session length</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_session_minutes} min
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Weekly workload</span>
              <span className="font-semibold text-foreground">
                {(displayExpectations.ideal_days_per_week * displayExpectations.ideal_session_minutes)} min/week
              </span>
            </div>
          </div>
        </div>
      )}

      {/* ── Track selection ── */}
      <section className="space-y-3">
        <div>
          <p className={SECTION_LABEL}>Periodization</p>
          <h2 className="text-sm font-semibold text-foreground mt-0.5">Training Track</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            {trackOptions.length > 1
              ? 'Each track is one way to follow this methodology, in its own phases. Choose one.'
              : 'The phases this methodology runs, in order.'}
          </p>
        </div>

        {trackOptions.length === 0 ? (
          <div className="rounded-xl border border-border/50 bg-muted/20 px-4 py-3 text-xs text-muted-foreground">
            No methodology selected — the framework will be auto-selected based on your constraints.
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3">
            {trackOptions.map(({ philosophy, track }) => {
              const isSelected = activeTrack?.id === track.id && picked?.philosophy.id === philosophy.id
              const trackFws = Array.from(new Set(track.phases.map((p) => p.framework_id)))
                .map((id) => frameworks?.find((f) => f.id === id))
                .filter((f): f is Framework => !!f)
              const issues = trackFws.flatMap((fw) => checkStyleCompatibility(fw, constraints).issues)
                .filter((issue, i, all) => all.findIndex((x) => x.label === issue.label) === i)
              const blocker = trackFws
                .map((fw) => blockingReason(checkStyleCompatibility(fw, constraints)))
                .find(Boolean)
              const selectable = trackFws.every((fw) => checkStyleCompatibility(fw, constraints).selectable)
              const isPrimary = (philosophy.primary_track_id ?? philosophy.tracks[0]?.id) === track.id
              const main = mainFramework(track, frameworks)

              return (
                <div
                  key={`${philosophy.id}/${track.id}`}
                  className={cn(
                    'relative flex flex-col gap-2 rounded-xl border p-4 transition-shadow bg-card',
                    !selectable && !isSelected ? 'opacity-55 border-border' : 'hover:shadow-md',
                    isSelected
                      ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                      : selectable && 'border-border hover:border-primary/50'
                  )}
                >
                  {isSelected && (
                    <span className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-primary">
                      <Check className="size-3 text-primary-foreground" />
                    </span>
                  )}

                  <button
                    onClick={() => {
                      setTrack(track.id)
                      // Let effectiveNumWeeks fall back to the track's length; the
                      // tight-event effect owns numWeeks when an event date is set.
                      if (!eventDate) setNumWeeks(null)
                    }}
                    disabled={!selectable && !isSelected}
                    title={blocker?.message}
                    className="flex items-start gap-2 pr-6 text-left disabled:cursor-not-allowed"
                  >
                    <Layers className="size-3.5 mt-0.5 shrink-0 text-muted-foreground" />
                    <div className="min-w-0">
                      <p className="text-xs font-semibold text-foreground">{track.name}</p>
                      <div className="flex flex-wrap gap-x-2">
                        {sourceMode === 'blend' && (
                          <span className="text-[9px] text-muted-foreground">{philosophy.name}</span>
                        )}
                        {isPrimary && (
                          <span className="text-[9px] text-primary font-medium">Primary for this methodology</span>
                        )}
                      </div>
                      {track.description && (
                        <p className="text-[10px] text-muted-foreground leading-relaxed mt-1 line-clamp-3">
                          {track.description}
                        </p>
                      )}
                    </div>
                  </button>

                  <PhaseSpine phases={track.phases} />

                  {issues.length > 0 && (
                    <div className="space-y-1">
                      {issues.map((issue) => (
                        <div
                          key={issue.label}
                          className={cn(
                            'flex items-start gap-1.5 text-[10px] leading-relaxed',
                            issue.severity === 'error'
                              ? 'text-destructive'
                              : 'text-amber-600 dark:text-amber-500'
                          )}
                        >
                          <AlertTriangle className="size-3 mt-px shrink-0" />
                          <span className="flex-1">{issue.message}</span>
                        </div>
                      ))}
                      {blocker?.constraintPatch && (
                        <button
                          onClick={() => updateConstraints(blocker.constraintPatch!)}
                          className="text-[10px] font-medium text-primary hover:underline"
                        >
                          {blocker.label} — apply
                        </button>
                      )}
                    </div>
                  )}

                  {main && (
                    <div className="flex justify-end">
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          setDetailFramework(main)
                        }}
                        className="flex-none flex items-center gap-1 text-[10px] font-medium rounded-md px-2 py-1 text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                      >
                        <Info className="size-3" />
                        Framework details
                      </button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}

        {selectedTrackId && (
          <button
            onClick={() => setTrack(null)}
            className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
          >
            Reset to the primary track
          </button>
        )}
      </section>

      {/* ── Priority weights ── */}
      <section className="space-y-3">
        <div className="flex items-baseline justify-between gap-4">
          <div>
            <p className={SECTION_LABEL}>Emphasis</p>
            <h2 className="text-sm font-semibold text-foreground mt-0.5">Training Priorities</h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              {sourceMode === 'blend'
                ? 'Blended from your philosophy mix. Adjust to fine-tune.'
                : sourceMode === 'philosophy'
                ? 'Derived from this philosophy\'s framework. Adjust to fine-tune.'
                : sourceMode === 'custom'
                ? 'Set by you. Adjust sliders to update.'
                : selectedGoalIds.length > 1
                ? 'Blended from your goal mix. Adjust to further fine-tune.'
                : 'Override the default emphasis for each domain.'}
            </p>
          </div>
          <div className="flex items-center gap-3 shrink-0">
            {fwDefaultPriorities && (
              <button
                onClick={() => setPriorityOverrides(fwDefaultPriorities)}
                className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
              >
                Framework default
              </button>
            )}
            <button
              onClick={() => {
                const base = sourcePriorities ?? blendedPriorities
                setPriorityOverrides({ ...base })
              }}
              className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
            >
              {resetLabel}
            </button>
          </div>
        </div>

        <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-3">
          {sortedPriorities.map(({ modality, weight }) => {
            const c = MODALITY_COLORS[modality]
            const pct = Math.round((weight / totalRaw) * 100)
            const rawVal = activePriorities[modality] ?? weight

            return (
              <div key={modality} className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-medium" style={{ color: c.hex }}>{c.label}</span>
                  <span className="text-muted-foreground font-medium">{pct}%</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex-1 h-1.5 rounded-full bg-border overflow-hidden">
                    <div
                      className="h-full rounded-full transition-all duration-150"
                      style={{ width: `${pct}%`, backgroundColor: c.hex }}
                    />
                  </div>
                  <input
                    type="range"
                    min={0}
                    max={100}
                    step={5}
                    value={Math.round(rawVal * 100)}
                    onChange={(e) => updatePriority(modality, parseInt(e.target.value) / 100)}
                    className="w-24 accent-primary"
                  />
                </div>
              </div>
            )
          })}
        </div>
      </section>

      <FrameworkDetailModal
        framework={detailFramework}
        open={detailFramework !== null}
        onClose={() => setDetailFramework(null)}
      />

      {/* ── Program duration ── */}
      <section className="space-y-3">
        <div>
          <p className={SECTION_LABEL}>Timeline</p>
          <h2 className="text-sm font-semibold text-foreground mt-0.5">Program Duration</h2>
        </div>

        {/* Event date — always shown first so the context is set before duration decisions */}
        <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-3">
          <div>
            <p className="text-xs font-medium text-foreground">
              Target event <span className="text-muted-foreground font-normal">(optional)</span>
            </p>
            <p className="text-[10px] text-muted-foreground mt-0.5">
              Set a date to auto-compute phase lengths and program fit.
            </p>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {[
              { label: '4 wks',  weeks: 4  },
              { label: '8 wks',  weeks: 8  },
              { label: '12 wks', weeks: 12 },
              { label: '16 wks', weeks: 16 },
              { label: '6 mo',   weeks: 26 },
              { label: '1 yr',   weeks: 52 },
            ].map(({ label, weeks }) => {
              const d = new Date()
              d.setDate(d.getDate() + weeks * 7)
              const iso = d.toISOString().split('T')[0]
              const active = eventDate === iso
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => setEventDate(active ? null : iso)}
                  className={cn(
                    'rounded-md border px-2.5 py-1 text-xs transition-colors',
                    active
                      ? 'border-primary bg-primary/10 text-primary font-medium'
                      : 'border-border text-muted-foreground hover:border-primary/50 hover:text-foreground'
                  )}
                >
                  {label}
                </button>
              )
            })}
          </div>
          <input
            type="date"
            className="flex h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            value={eventDate ?? ''}
            min={new Date().toISOString().split('T')[0]}
            onChange={(e) => setEventDate(e.target.value || null)}
          />
        </div>

        {eventDate && eventIsTight ? (
          <>
            <div className="rounded-xl border border-amber-500/30 bg-amber-500/5 px-4 py-3 text-xs text-amber-700 dark:text-amber-300">
              Your event is in <span className="font-semibold">{weeksUntilEvent}w</span>, but a full program is{' '}
              <span className="font-semibold">{defaultNumWeeks}w</span>. Choose how to handle this:
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <button
                onClick={() => setTightChoice('fit')}
                className={cn(
                  'text-left rounded-xl border p-4 transition-all',
                  tightChoice === 'fit'
                    ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                    : 'border-border bg-card hover:border-primary/40 hover:shadow-md'
                )}
              >
                <div className="flex items-center justify-between mb-1">
                  <p className="text-xs font-semibold text-foreground">
                    Fit to event — {weeksUntilEvent}w
                  </p>
                  {tightChoice === 'fit' && (
                    <span className="flex size-4 items-center justify-center rounded-full bg-primary">
                      <Check className="size-2.5 text-primary-foreground" />
                    </span>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Compress the program phases into {weeksUntilEvent} weeks. Peaks closest to your event date.
                </p>
              </button>

              <button
                onClick={() => setTightChoice('full')}
                className={cn(
                  'text-left rounded-xl border p-4 transition-all',
                  tightChoice === 'full'
                    ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                    : 'border-border bg-card hover:border-primary/40 hover:shadow-md'
                )}
              >
                <div className="flex items-center justify-between mb-1">
                  <p className="text-xs font-semibold text-foreground">
                    Full periodization — {defaultNumWeeks}w
                  </p>
                  {tightChoice === 'full' && (
                    <span className="flex size-4 items-center justify-center rounded-full bg-primary">
                      <Check className="size-2.5 text-primary-foreground" />
                    </span>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Run the complete program. The event falls within the program — use it as a mid-cycle check.
                </p>
              </button>
            </div>
          </>
        ) : eventDate && !eventIsTight ? (
          <div className="rounded-xl border border-border/50 bg-card/30 px-4 py-3 text-xs text-muted-foreground">
            Event in <span className="font-semibold text-foreground">{weeksUntilEvent}w</span> — the full{' '}
            {defaultNumWeeks}w program fits comfortably before your event date.{' '}
            <span className="text-muted-foreground">Duration locked to <span className="font-medium text-foreground">{defaultNumWeeks}w</span>.</span>
          </div>
        ) : (
          <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">Weeks to generate</span>
              <span className="font-semibold text-foreground text-sm">{effectiveNumWeeks}w</span>
            </div>
            <input
              type="range"
              min={2}
              max={Math.max(36, defaultNumWeeks + 8)}
              step={1}
              value={effectiveNumWeeks}
              onChange={(e) => setNumWeeks(parseInt(e.target.value))}
              className="w-full accent-primary"
            />
            <div className="flex justify-between text-[10px] text-muted-foreground">
              <span>2w</span>
              <span className="text-primary">{defaultNumWeeks}w (default)</span>
              <span>{Math.max(36, defaultNumWeeks + 8)}w</span>
            </div>
            {numWeeks !== null && numWeeks !== defaultNumWeeks && (
              <button
                onClick={() => setNumWeeks(null)}
                className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
              >
                Reset to {defaultNumWeeks}w
              </button>
            )}
          </div>
        )}
      </section>
    </div>
  )
}
