/**
 * The manual program builder's draft (docs/roadmap.md item 24.4): a track of
 * phases, each a few template weeks of seven days that repeat through the
 * phase, a day holding up to two sessions — the athlete's own or any other in
 * view. Every edit is a pure function.
 *
 * The wire shape is the server's (src/manual_builder.py `read_track`); a
 * draft adds a `uid` to each phase, for React keys. The server describes the
 * track (minutes, lighter weeks, the numbers week by week); nothing here
 * words a prescription.
 */

import type { SessionBlock } from '@/api/types'

export interface ManualDay { sessions: string[]; light?: boolean }

export interface ManualPhase {
  id?: string
  name: string
  kind: string
  weeks: number
  template: ManualDay[][]
}

export interface ManualTrack {
  id?: string
  name: string
  description?: string | null
  deload_every?: number | null
  phases: ManualPhase[]
}

export interface DraftPhase extends ManualPhase { uid: string }
export interface DraftTrack extends Omit<ManualTrack, 'phases'> { phases: DraftPhase[] }

export interface TrackProblem { phase: number | null; week: number | null; day: number | null; field: string | null; message: string }

export const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'] as const
export const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const
export const MAX_DAY_SESSIONS = 2

let counter = 0
export function uid(): string {
  counter += 1
  return `p${Date.now().toString(36)}-${counter}`
}

const restDay = (): ManualDay => ({ sessions: [] })
export const emptyWeek = (): ManualDay[] => DAYS.map(restDay)

export const newPhase = (name = 'Phase 1', kind = 'build', weeks = 4): DraftPhase =>
  ({ uid: uid(), name, kind, weeks, template: [emptyWeek()] })

export const emptyTrack = (): DraftTrack => ({ name: '', deload_every: null, phases: [newPhase()] })

// ─── Phases ──────────────────────────────────────────────────────────────────

const mapPhase = (track: DraftTrack, phaseUid: string, fn: (phase: DraftPhase) => DraftPhase): DraftTrack =>
  ({ ...track, phases: track.phases.map((p) => (p.uid === phaseUid ? fn(p) : p)) })

export function addPhase(track: DraftTrack, limit = 8): DraftTrack {
  if (track.phases.length >= limit) return track
  const last = track.phases[track.phases.length - 1]
  const phase = newPhase(`Phase ${track.phases.length + 1}`, last?.kind ?? 'build', last?.weeks ?? 4)
  // A new phase starts from the week before it, which is what most programs repeat.
  return { ...track, phases: [...track.phases, last ? { ...phase, template: copyWeeks(last.template) } : phase] }
}

export const updatePhase = (track: DraftTrack, phaseUid: string, patch: Partial<Pick<DraftPhase, 'name' | 'kind' | 'weeks'>>): DraftTrack =>
  mapPhase(track, phaseUid, (p) => ({ ...p, ...patch }))

export function removePhase(track: DraftTrack, phaseUid: string): DraftTrack {
  if (track.phases.length <= 1) return track
  return { ...track, phases: track.phases.filter((p) => p.uid !== phaseUid) }
}

export function nudgePhase(track: DraftTrack, phaseUid: string, by: -1 | 1): DraftTrack {
  const at = track.phases.findIndex((p) => p.uid === phaseUid)
  const to = at + by
  if (at < 0 || to < 0 || to >= track.phases.length) return track
  const phases = [...track.phases]
  ;[phases[at], phases[to]] = [phases[to], phases[at]]
  return { ...track, phases }
}

// ─── Weeks ───────────────────────────────────────────────────────────────────

const copyDay = (day: ManualDay): ManualDay => ({ sessions: [...day.sessions], ...(day.light ? { light: true } : {}) })
const copyWeeks = (weeks: ManualDay[][]): ManualDay[][] => weeks.map((w) => w.map(copyDay))

const mapWeeks = (track: DraftTrack, phaseUid: string, fn: (weeks: ManualDay[][]) => ManualDay[][]): DraftTrack =>
  mapPhase(track, phaseUid, (p) => ({ ...p, template: fn(p.template) }))

export const addWeek = (track: DraftTrack, phaseUid: string, limit = 8): DraftTrack =>
  mapWeeks(track, phaseUid, (weeks) => (weeks.length >= limit ? weeks : [...weeks, emptyWeek()]))

export const duplicateWeek = (track: DraftTrack, phaseUid: string, week: number, limit = 8): DraftTrack =>
  mapWeeks(track, phaseUid, (weeks) => (weeks.length >= limit || !weeks[week] ? weeks
    : [...weeks.slice(0, week + 1), weeks[week].map(copyDay), ...weeks.slice(week + 1)]))

export const clearWeek = (track: DraftTrack, phaseUid: string, week: number): DraftTrack =>
  mapWeeks(track, phaseUid, (weeks) => weeks.map((w, i) => (i === week ? emptyWeek() : w)))

export const removeWeek = (track: DraftTrack, phaseUid: string, week: number): DraftTrack =>
  mapWeeks(track, phaseUid, (weeks) => (weeks.length <= 1 ? weeks : weeks.filter((_, i) => i !== week)))

// ─── Days ────────────────────────────────────────────────────────────────────

export interface Cell { week: number; day: number }

const mapDay = (track: DraftTrack, phaseUid: string, cell: Cell, fn: (day: ManualDay) => ManualDay): DraftTrack =>
  mapWeeks(track, phaseUid, (weeks) => weeks.map((w, wi) => (wi !== cell.week ? w
    : w.map((d, di) => (di !== cell.day ? d : tidy(fn(d)))))))

/** A rest day is never light. */
const tidy = (day: ManualDay): ManualDay => (day.sessions.length && day.light ? { sessions: day.sessions, light: true } : { sessions: day.sessions })

export const dayAt = (track: DraftTrack, phaseUid: string, cell: Cell): ManualDay | undefined =>
  track.phases.find((p) => p.uid === phaseUid)?.template[cell.week]?.[cell.day]

/** Whether a day can take this session: it has room and does not hold it already. */
export function canPlace(day: ManualDay | undefined, sessionId: string): boolean {
  return !!day && day.sessions.length < MAX_DAY_SESSIONS && !day.sessions.includes(sessionId)
}

/** Put a session on a day, after the one already there. A full day is left as it is. */
export function placeSession(track: DraftTrack, phaseUid: string, cell: Cell, sessionId: string): DraftTrack {
  if (!canPlace(dayAt(track, phaseUid, cell), sessionId)) return track
  return mapDay(track, phaseUid, cell, (d) => ({ ...d, sessions: [...d.sessions, sessionId] }))
}

export const removeSession = (track: DraftTrack, phaseUid: string, cell: Cell, index: number): DraftTrack =>
  mapDay(track, phaseUid, cell, (d) => ({ ...d, sessions: d.sessions.filter((_, i) => i !== index) }))

/** Move a placed session to another day of the phase; nothing moves when that day cannot take it. */
export function moveSession(track: DraftTrack, phaseUid: string, from: Cell, index: number, to: Cell): DraftTrack {
  if (from.week === to.week && from.day === to.day) return track
  const sessionId = dayAt(track, phaseUid, from)?.sessions[index]
  if (!sessionId || !canPlace(dayAt(track, phaseUid, to), sessionId)) return track
  return placeSession(removeSession(track, phaseUid, from, index), phaseUid, to, sessionId)
}

export const toggleLight = (track: DraftTrack, phaseUid: string, cell: Cell): DraftTrack =>
  mapDay(track, phaseUid, cell, (d) => ({ ...d, light: !d.light }))

// ─── Reading the draft ───────────────────────────────────────────────────────

export const totalWeeks = (track: Pick<ManualTrack, 'phases'>): number =>
  track.phases.reduce((n, p) => n + (Number(p.weeks) || 0), 0)

/** The first week of the program each phase starts on (1-based). */
export function phaseStarts(track: Pick<ManualTrack, 'phases'>): number[] {
  let at = 1
  return track.phases.map((p) => { const start = at; at += Number(p.weeks) || 0; return start })
}

/** Which template week a week of the phase runs (they repeat). */
export const templateWeekOf = (phase: Pick<ManualPhase, 'template'>, weekInPhase: number): number =>
  (weekInPhase - 1) % Math.max(1, phase.template.length)

/** The weeks of a phase that are lighter: every `deloadEvery`th, counted within the phase. */
export function lighterWeeks(phase: Pick<ManualPhase, 'weeks'>, deloadEvery: number | null | undefined): number[] {
  if (!deloadEvery || deloadEvery < 2) return []
  const out: number[] = []
  for (let w = deloadEvery; w <= (Number(phase.weeks) || 0); w += deloadEvery) out.push(w)
  return out
}

/** How the laid weeks fill the phase, in a sentence. */
export function repeatLine(phase: Pick<ManualPhase, 'weeks' | 'template'>): string {
  const rows = phase.template.length
  const weeks = Number(phase.weeks) || 0
  if (rows === 1) return weeks === 1 ? 'This week is the whole phase.' : `This week repeats for the ${weeks} weeks of the phase.`
  if (rows > weeks) return `The phase is ${weeks} ${weeks === 1 ? 'week' : 'weeks'}: only the first ${weeks === 1 ? 'one' : weeks} of these run.`
  if (rows === weeks) return 'One row for each week of the phase.'
  return `These ${rows} weeks repeat, in order, for the ${weeks} weeks of the phase.`
}

export const sessionsInWeek = (week: ManualDay[]): number => week.filter((d) => d.sessions.length > 0).length

/** Every session id the track places. */
export const placedSessions = (track: Pick<ManualTrack, 'phases'>): Set<string> =>
  new Set(track.phases.flatMap((p) => p.template.flatMap((w) => w.flatMap((d) => d.sessions))))

export const isBlank = (track: Pick<ManualTrack, 'phases'>): boolean => placedSessions(track).size === 0

// ─── To and from the server ──────────────────────────────────────────────────

export function toWire(track: DraftTrack): ManualTrack {
  return {
    ...(track.id ? { id: track.id } : {}),
    name: track.name.trim(),
    ...(track.description?.trim() ? { description: track.description.trim() } : {}),
    deload_every: track.deload_every || null,
    phases: track.phases.map(({ uid: _uid, ...phase }) => ({
      ...phase, name: phase.name.trim(), template: phase.template.map((w) => w.map(tidy)),
    })),
  }
}

export function fromWire(track: ManualTrack): DraftTrack {
  return {
    id: track.id, name: track.name ?? '', description: track.description ?? undefined,
    deload_every: track.deload_every ?? null,
    phases: (track.phases ?? []).map((p) => ({
      id: p.id, name: p.name ?? '', kind: p.kind, weeks: p.weeks, uid: uid(),
      template: (p.template ?? []).map((w) => DAYS.map((_, d) => tidy({ sessions: [...(w[d]?.sessions ?? [])], light: !!w[d]?.light }))),
    })),
  }
}

export const duplicateOf = (track: ManualTrack): DraftTrack => {
  const copy = fromWire(track)
  return { ...copy, id: undefined, name: `${track.name} copy`, phases: copy.phases.map((p) => ({ ...p, id: undefined })) }
}

/** The problems of one cell of one phase, by the phase's place in the track. */
export const problemsAt = (problems: TrackProblem[], phase: number, cell?: Cell): TrackProblem[] =>
  problems.filter((p) => p.phase === phase && (cell ? p.week === cell.week && p.day === cell.day : p.day === null))
export const trackProblems = (problems: TrackProblem[]): TrackProblem[] => problems.filter((p) => p.phase === null)

// ─── The sessions a program may lay on a day ─────────────────────────────────

/** A session as the shelf and the grid show it: one of the athlete's, or any other in view. */
export interface ShelfSession {
  id: string
  name: string
  modality: string
  minutes: number
  /** The session as blocks (src/session_blocks.py), where the server sent them. */
  preview: SessionBlock[]
  /** Built by the athlete in the session builder. */
  own: boolean
  /** The method it belongs to, by id and name; absent on one of the athlete's. */
  from?: { id: string; name: string }
}

interface OwnSession { id: string; name: string; modality: string; minutes: number; preview: SessionBlock[] }
interface LibraryArchetype {
  id: string; name: string; modality: string; _package?: string
  duration_estimate_minutes?: number; blocks?: SessionBlock[]
}

/** The athlete's sessions first, then every other session in view, by method and name. */
export function shelfSessions(
  own: OwnSession[], archetypes: LibraryArchetype[], methods: { id: string; name: string }[], ownPackage?: string,
): ShelfSession[] {
  const mine = new Set(own.map((s) => s.id))
  const names = new Map(methods.map((m) => [m.id, m.name]))
  const library = archetypes
    .filter((a) => a.id && !mine.has(a.id) && a._package !== ownPackage)
    .map((a): ShelfSession => ({
      id: a.id, name: a.name, modality: a.modality, minutes: a.duration_estimate_minutes ?? 0, preview: a.blocks ?? [], own: false,
      from: a._package ? { id: a._package, name: names.get(a._package) ?? a._package.replace(/_/g, ' ') } : undefined,
    }))
    .sort((a, b) => (a.from?.name ?? '').localeCompare(b.from?.name ?? '') || a.name.localeCompare(b.name))
  return [...own.map((s): ShelfSession => ({ id: s.id, name: s.name, modality: s.modality, minutes: s.minutes, preview: s.preview, own: true })),
    ...library]
}

/** The methods the library's sessions come from, by name. */
export function libraryMethods(sessions: ShelfSession[]): { id: string; name: string }[] {
  const seen = new Map<string, string>()
  for (const s of sessions) if (!s.own && s.from) seen.set(s.from.id, s.from.name)
  return [...seen].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name))
}

/** The library's sessions a search leaves: every word in the name, the method or a movement; one method when chosen. */
export function searchLibrary(sessions: ShelfSession[], query: string, method: string | null): ShelfSession[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean)
  return sessions.filter((s) => {
    if (s.own) return false
    if (method && s.from?.id !== method) return false
    if (words.length === 0) return true
    const hay = [s.name, s.from?.name ?? '', ...s.preview.flatMap((b) => b.movements.map((m) => m.name))].join(' ').toLowerCase()
    return words.every((w) => hay.includes(w))
  })
}
