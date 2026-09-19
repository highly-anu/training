import { useMemo } from 'react'
import type { FeasibilitySignal } from '@/lib/feasibility'
import { blendExpectations, expectationSignals } from '@/lib/feasibility'
import { checkStyleCompatibility } from '@/lib/styleCompatibility'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useBuilderStore } from '@/store/builderStore'

/**
 * Pre-flight signals for the builder, derived from the selected philosophy's
 * framework `expectations` against the athlete's constraints.
 *
 * Goals are deprecated as a source; expectations now come from the chosen
 * training style, or from the weighted blend of a sequential group's phase
 * frameworks when no style has been picked.
 */
export function useFeasibility(): FeasibilitySignal[] {
  const {
    sourceMode,
    selectedPhilosophyIds,
    selectedFrameworkId,
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
      selectedFrameworkId,
    })
    if (!exp) return []

    const signals = expectationSignals(exp, constraints, numWeeks)

    // Surface an incompatible style as its own signal so it is visible on the
    // review step even if the user never revisits step 2.
    const chosen = selectedFrameworkId
      ? frameworks.find((f) => f.id === selectedFrameworkId)
      : undefined
    if (chosen) {
      for (const issue of checkStyleCompatibility(chosen, constraints).issues) {
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
    selectedFrameworkId,
    constraints,
    numWeeks,
  ])
}
