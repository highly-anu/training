import type { Framework, GoalProfile, PhaseEntry, Philosophy, Track, TrackImplement, WeekData } from '@/api/types'

/**
 * Tracks and phases on the client. A philosophy offers one or more tracks;
 * each is an ordered list of the philosophy's own phases, and each phase names
 * the framework that builds its weeks (src/phases.py is the server's half).
 *
 * Phase words — name, focus, description — come only from the philosophy that
 * owns the phase. Nothing here describes a phase by its kind.
 */

export function tracksOf(phil: Philosophy | undefined | null): Track[] {
  return phil?.tracks ?? []
}

/** The track a request that names none gets: the one written for the
 *  athlete's level (`track_for_level`, as the server picks it — Starting
 *  Strength's intermediate gets the Texas Method), else the primary. */
export function primaryTrack(phil: Philosophy | undefined | null, level?: string | null): Track | undefined {
  const tracks = tracksOf(phil)
  const byLevel = level ? phil?.track_for_level?.[level] : undefined
  return tracks.find((t) => t.id === byLevel) ?? tracks.find((t) => t.id === phil?.primary_track_id) ?? tracks[0]
}

export function findTrack(phil: Philosophy | undefined | null, trackId: string | null | undefined): Track | undefined {
  if (!trackId) return undefined
  return tracksOf(phil).find((t) => t.id === trackId)
}

/** The selected track, else the philosophy's primary track. */
export function resolveTrack(phil: Philosophy | undefined | null, trackId: string | null | undefined): Track | undefined {
  return findTrack(phil, trackId) ?? primaryTrack(phil)
}

export function trackWeeks(track: Track | undefined): number {
  return (track?.phases ?? []).reduce((sum, p) => sum + (p.weeks ?? 0), 0)
}

/** The framework of the track's longest phase — what stands for the track where
 * one framework must (priorities, a single expectations block). Mirrors
 * goals._main_framework on the server. */
export function mainFrameworkId(track: Track | undefined): string | undefined {
  let best: Track['phases'][number] | undefined
  for (const p of track?.phases ?? []) {
    if (!best || (p.weeks ?? 0) > (best.weeks ?? 0)) best = p
  }
  return best?.framework_id
}

export function mainFramework(track: Track | undefined, frameworks: Framework[] | undefined): Framework | undefined {
  const id = mainFrameworkId(track)
  return id ? frameworks?.find((f) => f.id === id) : undefined
}

/** (track, phase) that runs a framework — Explore's "Build with this framework". */
export function trackForFramework(
  phil: Philosophy | undefined | null,
  frameworkId: string,
): { track: Track; phaseId: string } | undefined {
  const primary = primaryTrack(phil)
  const ordered = [primary, ...tracksOf(phil).filter((t) => t !== primary)].filter(Boolean) as Track[]
  for (const track of ordered) {
    const phase = track.phases.find((p) => p.framework_id === frameworkId)
    if (phase) return { track, phaseId: phase.id }
  }
  return undefined
}

/** Display label for a week's phase: the philosophy's own name, else the kind. */
export function weekPhaseLabel(week: Pick<WeekData, 'phase' | 'phase_name'>): string {
  if (week.phase_name) return week.phase_name
  const kind = week.phase ?? ''
  return kind.charAt(0).toUpperCase() + kind.slice(1).replace(/_/g, ' ')
}

/**
 * The goal's entry for a week's phase: by id, else — for a program stored
 * before tracks — the first entry of the week's kind. Text is only ever read
 * from this entry, so an old program shows its own focus or nothing, never
 * another philosophy's words.
 */
export function phaseEntryFor(goal: GoalProfile | undefined | null, week: Pick<WeekData, 'phase' | 'phase_id'>): PhaseEntry | undefined {
  const seq = goal?.phase_sequence ?? []
  if (week.phase_id) {
    const byId = seq.find((e) => e.phase_id === week.phase_id)
    if (byId) return byId
  }
  return seq.find((e) => e.phase === week.phase)
}

/**
 * The builder's track: the named one from any selected philosophy (a blend
 * may run any member's track), else the first selected philosophy's primary
 * track. (The server defaults a blend to its heaviest member's primary track;
 * the builder only uses this for previews and feasibility.)
 */
export function builderTrack(
  philosophies: Philosophy[] | undefined,
  selectedPhilosophyIds: string[],
  trackId: string | null | undefined,
  level?: string | null,
): { philosophy: Philosophy; track: Track } | undefined {
  const selected = selectedPhilosophyIds
    .map((id) => philosophies?.find((p) => p.id === id))
    .filter(Boolean) as Philosophy[]
  if (trackId) {
    for (const phil of selected) {
      const t = findTrack(phil, trackId)
      if (t) return { philosophy: phil, track: t }
    }
  }
  const first = selected[0]
  const t = primaryTrack(first, level)
  return first && t ? { philosophy: first, track: t } : undefined
}

type EntryRequirements = NonNullable<Track['entry_requirements']>

/** Each implement any track asks for, at the most any asks (a pair of bells). */
export function mergedImplements(reqs: EntryRequirements[]): TrackImplement[] {
  const byKey = new Map<string, TrackImplement>()
  for (const r of reqs) {
    for (const imp of trackImplements(r)) {
      const seen = byKey.get(imp.countKey)
      if (!seen || imp.count > seen.count) byKey.set(imp.countKey, imp)
    }
  }
  return Array.from(byKey.values())
}

/** What a track asks the athlete to confirm they have; a build of the server
 *  that predates `implements` said only `kettlebell_count`. */
export function trackImplements(r: EntryRequirements | undefined): TrackImplement[] {
  if (!r) return []
  if (r.implements) return r.implements
  return r.kettlebell_count >= 2
    ? [{ equipment: 'kettlebell', count: r.kettlebell_count, countKey: 'kettlebell_count', number: 'two', plural: 'kettlebells' }]
    : []
}

/** How many of an implement the athlete has said they have (`<equipment>_count`). */
export function implementCount(constraints: object, countKey: string): number {
  const n = (constraints as Record<string, unknown>)[countKey]
  return typeof n === 'number' ? n : 0
}

/**
 * What every one of several tracks asks of the athlete before it runs, as one
 * track's requirements: the levels all of them are written for, every
 * movement any of them needs mastered at this level, the most bells, and
 * every lift any of them may start from a known weight. None when no track
 * asks anything.
 */
export function mergedEntryRequirements(
  tracks: (Track | undefined)[],
  level: string,
): EntryRequirements | undefined {
  const reqs = tracks.map((t) => t?.entry_requirements).filter((r): r is EntryRequirements => !!r)
  if (reqs.length === 0) return undefined
  if (reqs.length === 1) return reqs[0]
  const mastered = Array.from(new Set(reqs.flatMap((r) => r.mastered_exercises_by_level?.[level] ?? r.mastered_exercises)))
  const loads = new Map<string, { id: string; name: string }>()
  for (const r of reqs) for (const l of r.starting_loads ?? []) loads.set(l.id, l)
  return {
    training_levels: reqs.slice(1).reduce((acc, r) => acc.filter((lv) => r.training_levels.includes(lv)),
      reqs[0].training_levels),
    mastered_exercises: mastered,
    mastered_exercises_by_level: { [level]: mastered },
    exercise_names: Object.assign({}, ...reqs.map((r) => r.exercise_names ?? {})),
    implements: mergedImplements(reqs),
    kettlebell_count: Math.max(...reqs.map((r) => r.kettlebell_count)),
    starting_loads: Array.from(loads.values()),
  }
}
