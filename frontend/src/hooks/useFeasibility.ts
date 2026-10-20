import { useMemo } from 'react'
import type { FeasibilitySignal } from '@/lib/feasibility'
import { blendExpectations, expectationSignals } from '@/lib/feasibility'
import { checkStyleCompatibility } from '@/lib/styleCompatibility'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useBuilderStore } from '@/store/builderStore'
import { builderTrack } from '@/lib/tracks'

/**
 * Pre-flight signals for the builder, derived from the selected philosophy's
 * framework `expectations` against the athlete's constraints.
 *
 * Goals are deprecated as a source; expectations come from the chosen track:
 * its framework when it has one phase, else the weeks-weighted blend of its
 * phases' frameworks.
 */
export function useFeasibility(): FeasibilitySignal[] {
  const {
    sourceMode,
    selectedPhilosophyIds,
    selectedTrackId,
    constraints,
    numWeeks,
  } = useBuilderStore()

  const { data: philosophies } = usePhilosophies()
  const { data: frameworks } = useFrameworks()

  return useMemo(() => {
    if (!philosophies || !frameworks) return []
    if (sourceMode !== 'philosophy' && sourceMode !== 'blend') return []
    if (!selectedPhilosophyIds.length) return []

    const exp = blendExpectations([], [], {}, {
      sourceMode: 'philosophy',
      philosophies,
      frameworks,
      selectedPhilosophyIds,
      selectedTrackId,
      trainingLevel: constraints.training_level,
    })
    if (!exp) return []

    const signals = expectationSignals(exp, constraints, numWeeks)

    // Surface a track whose frameworks do not fit the constraints as its own
    // signal so it is visible on the review step even if the user never
    // revisits step 2. Every phase's framework is checked, once.
    const picked = builderTrack(philosophies, selectedPhilosophyIds, selectedTrackId, constraints.training_level)
    const seen = new Set<string>()
    const phaseFrameworks = (picked?.track.phases ?? [])
      .map((p) => frameworks.find((f) => f.id === p.framework_id))
      .filter((f): f is NonNullable<typeof f> => !!f && !seen.has(f.id) && !!seen.add(f.id))
    const seenIssue = new Set<string>()
    for (const chosen of phaseFrameworks) {
      for (const issue of checkStyleCompatibility(chosen, constraints).issues) {
        if (seenIssue.has(issue.label)) continue
        seenIssue.add(issue.label)
        signals.push({
          code: issue.severity === 'error' ? 'STYLE_INCOMPATIBLE' : 'STYLE_MISMATCH',
          severity: issue.severity,
          label: issue.label,
          message: issue.message,
          suggestion:
            issue.severity === 'error'
              ? 'Adjust your constraints, or go back and pick a different training style.'
              : undefined,
          quickFix: issue.constraintPatch
            ? { label: issue.label, constraintPatch: issue.constraintPatch }
            : undefined,
        })
      }
    }

    return signals
  }, [
    philosophies,
    frameworks,
    sourceMode,
    selectedPhilosophyIds,
    selectedTrackId,
    constraints,
    numWeeks,
  ])
}
