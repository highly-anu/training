import type { Framework, ModalityId } from '@/api/types'

/**
 * Derive a priority vector implied by a framework, filtered through what a goal actually trains.
 *
 * Algorithm:
 *   1. Split framework's sessions_per_week into:
 *      - active  : mods with positive goal priority  (framework knows about them)
 *      - ignored : mods with zero goal priority      (not relevant for this goal)
 *   2. Among active mods, redistribute their share of the goal priority using the
 *      framework's session counts as the ratio (not the goal's existing weights).
 *   3. Goal mods absent from the framework keep their existing goal weight unchanged.
 *
 * The result always sums to 1.0.
 *
 * Example — ultra_endurance + polarized_80_20:
 *   fw sessions : aerobic_base:4, anaerobic_intervals:1, max_strength:1
 *   goal prios  : aerobic_base:0.6, durability:0.2, strength_endurance:0.1, mobility:0.1
 *   → active_fw = { aerobic_base:4 }  (others have zero goal priority → ignored)
 *   → implied   = { aerobic_base:0.6, durability:0.2, SE:0.1, mobility:0.1 }
 *     (only one active fw mod so ratio is trivially 1.0 × 0.6)
 *
 * Example — mixed goal + concurrent_training:
 *   fw sessions : max_strength:2, aerobic_base:2, mixed_modal:1
 *   goal prios  : max_strength:0.5, aerobic_base:0.3, mobility:0.2
 *   → active_fw = { max_strength:2, aerobic_base:2 },  active_total=4
 *   → fw_covered_prio = 0.5+0.3 = 0.8
 *   → implied max_strength  = (2/4)×0.8 = 0.40   (was 0.50 — framework equalises them)
 *   → implied aerobic_base  = (2/4)×0.8 = 0.40   (was 0.30 — raised by framework)
 *   → implied mobility      = 0.20               (unchanged, not in framework)
 */
export function frameworkImpliedPriorities(
  fw: Framework,
  goalPriorities: Partial<Record<ModalityId, number>>,
): Partial<Record<ModalityId, number>> {
  const fwSessions = fw.sessions_per_week ?? {}
  const activeFw: Partial<Record<ModalityId, number>> = {}

  for (const [mod, cnt] of Object.entries(fwSessions)) {
    if ((goalPriorities[mod as ModalityId] ?? 0) > 0) {
      activeFw[mod as ModalityId] = cnt ?? 0
    }
  }

  const activeFwTotal = Object.values(activeFw).reduce((s, v) => s + (v ?? 0), 0)

  // No framework overlap with goal — return goal priorities unchanged
  if (activeFwTotal === 0) return { ...goalPriorities }

  // Weight of goal modalities covered by the framework
  const fwCoveredPrio = Object.keys(activeFw).reduce(
    (s, m) => s + (goalPriorities[m as ModalityId] ?? 0),
    0,
  )

  const result: Partial<Record<ModalityId, number>> = {}

  // Framework-covered mods: redistribute fwCoveredPrio using fw session counts as ratio
  for (const [mod, cnt] of Object.entries(activeFw)) {
    result[mod as ModalityId] = ((cnt ?? 0) / activeFwTotal) * fwCoveredPrio
  }

  // Goal-only mods (not in framework): keep their original goal weight
  for (const [mod, w] of Object.entries(goalPriorities)) {
    if ((w ?? 0) > 0 && !(mod in fwSessions)) {
      result[mod as ModalityId] = w ?? 0
    }
  }

  return result
}
