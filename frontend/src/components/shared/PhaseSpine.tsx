import { useMemo } from 'react'
import type { Framework, Phase } from '@/api/types'
import { PhaseBar } from '@/components/program/PhaseBar'
import { trackSegments } from '@/hooks/usePhaseCalendar'
import { PHASE_COLORS } from '@/lib/phaseColors'

/**
 * A track's phases in order: the bar, then one line per phase with its own
 * name, length, framework and focus. Used by the builder's track picker and
 * Explore's philosophy card, so a phase reads the same in both.
 */
export function PhaseSpine({ phases, frameworks, showFrameworks = false }: {
  phases: Phase[]
  frameworks?: Framework[]
  showFrameworks?: boolean
}) {
  const segments = useMemo(() => trackSegments(phases), [phases])
  const totalWeeks = segments.reduce((n, s) => n + s.weeks, 0)
  if (!phases.length) return null
  return (
    <div className="space-y-1.5">
      <PhaseBar segments={segments} totalWeeks={totalWeeks} currentWeek={0} />
      <ul className="space-y-1">
        {phases.map((p) => {
          const c = PHASE_COLORS[p.kind]
          const fw = showFrameworks ? frameworks?.find((f) => f.id === p.framework_id) : undefined
          return (
            <li key={p.id} className="flex items-baseline gap-2 text-[10px]">
              <span className="w-24 shrink-0 font-medium truncate" style={{ color: c?.hex }}>{p.name}</span>
              <span className="w-10 shrink-0 font-mono text-muted-foreground">
                {p.weeks}wk{p.repeatable ? ' ↻' : ''}
              </span>
              <span className="min-w-0 text-muted-foreground">
                {fw && <span className="text-foreground/80">{fw.name}</span>}
                {fw && p.focus && ' — '}
                {p.focus}
              </span>
            </li>
          )
        })}
      </ul>
    </div>
  )
}
