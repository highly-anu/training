import { useMemo } from 'react'
import type { GeneratedProgram } from '@/api/types'
import { laneSegments } from '@/hooks/usePhaseCalendar'
import { PhaseBar } from './PhaseBar'

const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

/**
 * A composed program's tracks (src/composition.py): each with its share of
 * the week, the days it keeps, its own phases across the program, and what
 * gave way so it fits beside the others — the server's words, nothing
 * recomputed here. Nothing for one track.
 */
export function CompositionTracks({ program, currentWeek = 0 }: {
  program: Pick<GeneratedProgram, 'goal' | 'weeks' | 'composition' | 'compromises'>
  currentWeek?: number
}) {
  const { goal, composition, weeks } = program
  const rows = useMemo(() => (goal?.tracks ?? []).map((t) => ({
    track: t,
    lane: composition?.lanes.find((l) => l.key === t.lane_key),
    segments: laneSegments(weeks, t.lane_key, t.phase_sequence),
  })), [goal, composition, weeks])
  if (rows.length < 2) return null
  const total = program.weeks.length || 1
  return (
    <div className="space-y-4">
      {rows.map(({ track, lane, segments }) => {
        const cuts = (program.compromises ?? []).filter((c) => c.startsWith(`${track.name}: `)
          && /to fit beside/.test(c))
        return (
          <div key={track.lane_key} className="rounded-xl border bg-card p-4 space-y-2">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="text-xs font-semibold">{track.name}</p>
              <p className="text-[10px] text-muted-foreground">
                {Math.round(track.weight * 100)}%
                {lane ? ` · ${lane.days} of ${program.composition?.days.length ?? lane.days} days` : ''}
                {lane?.reserved_days?.length ? ` · keeps ${lane.reserved_days.map((d) => DAY_SHORT[d - 1]).join(', ')}` : ''}
              </p>
            </div>
            <PhaseBar segments={segments} totalWeeks={total} currentWeek={currentWeek} />
            {cuts.map((c) => (
              <p key={c} className="text-[11px] text-amber-700 dark:text-amber-300 leading-relaxed">
                {c.slice(track.name.length + 2)}
              </p>
            ))}
          </div>
        )
      })}
    </div>
  )
}
