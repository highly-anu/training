import type { TraceEngine, WeekTrace } from '@/api/types'

// What built a week, in words: shared by the Schedule step, the pipeline flow
// and the page (EngineWeek.tsx holds the components).

export const ENGINE_LABEL: Record<TraceEngine, string> = {
  scheduler: 'Modality scheduler',
  week_templates: 'Week templates',
  training_contract: 'Training contract',
  composition: 'Composition',
}

/** What built the week: the trace says so; a trace recorded before it did is read by its shape. */
export function engineOf(week: Pick<WeekTrace, 'engine' | 'scheduler' | 'lane_weeks'>): TraceEngine {
  if (week.engine) return week.engine
  if (week.lane_weeks) return 'composition'
  if (week.scheduler?.contract) return 'training_contract'
  if (week.scheduler?.week_template) return 'week_templates'
  return 'scheduler'
}

export function words(id: string | null | undefined): string {
  return (id ?? '').replace(/_/g, ' ')
}

/** A sentence for what placed the week (the Schedule step's card and the flow agree on it). */
export function placedBy(engine: TraceEngine): string {
  if (engine === 'training_contract') {
    return "Placed by the training contract: each module's movements, weekly exposures and recovery spacing are fixed, so no priorities are allocated and no framework is chosen."
  }
  if (engine === 'week_templates') {
    return "Written by the source's week: each day is a category, and its workout the next of the category's named workouts the athlete can do as written."
  }
  if (engine === 'composition') {
    return 'Several tracks on one week: each runs its own phases on its own engine, the contracts placed first, then the templates into the minutes left.'
  }
  return 'Allocated by the modality scheduler from the framework\'s sessions a week.'
}
