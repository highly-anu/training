import { useMutation, useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { apiClient } from './client'
import { refreshAfterMethodChange } from './methods'
import type { SessionBlock } from './types'
import type { BuilderProblem, ManualSession } from '@/lib/sessionBuilder'
import type { ManualDay, ManualTrack, TrackProblem } from '@/lib/programBuilder'

/**
 * Sessions composed by hand (docs/roadmap.md item 24; src/manual_builder.py).
 * The server keeps them as one package of the athlete's and derives what is
 * drawn: the blocks, the minutes, the equipment, the first weeks in words.
 */

export interface DescribedSession extends ManualSession {
  id: string
  archetypeId: string
  minutes: number
  equipment: string[]
  /** The session as every client draws it (src/session_blocks.py). */
  preview: SessionBlock[]
  /** What moves, week by week, in the server's words. */
  forecast: { role: string; exercise: string; weeks: (string | null)[] }[]
}

export interface ManualSessionsAnswer {
  packageId: string
  sessions: DescribedSession[]
  limits: { sessions: number; blocks: number; movements: number }
}

export interface PreviewAnswer { ok: boolean; problems: BuilderProblem[]; session: DescribedSession | null }

export const manualKeys = {
  all: ['manual'] as const,
  sessions: ['manual', 'sessions'] as const,
  preview: (body: string) => ['manual', 'preview', body] as const,
  tracks: ['manual', 'tracks'] as const,
  trackPreview: (body: string) => ['manual', 'tracks', 'preview', body] as const,
}

export function useManualSessions() {
  return useQuery({
    queryKey: manualKeys.sessions,
    queryFn: () => apiClient.get('/manual/sessions') as unknown as Promise<ManualSessionsAnswer>,
  })
}

/** The draft as the server reads it; asked again as the draft changes. */
export function useManualPreview(session: ManualSession, enabled: boolean) {
  const body = JSON.stringify(session)
  return useQuery({
    queryKey: manualKeys.preview(body),
    queryFn: () => apiClient.post('/manual/preview', { session }) as unknown as Promise<PreviewAnswer>,
    enabled,
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  })
}

/** Why a save or delete was refused: the problems, else one sentence. */
export function manualRefusal(error: unknown): { problems: BuilderProblem[]; message: string } {
  const e = (error ?? {}) as { status?: number; body?: { error?: string; detail?: string; problems?: BuilderProblem[]; busy?: boolean } }
  if (e.body?.problems?.length) return { problems: e.body.problems, message: e.body.problems[0].message }
  if (e.body?.error === 'in_track') return { problems: [], message: e.body.detail ?? 'A program of yours has this session on a day. Take it off there first.' }
  if (e.body?.error === 'in_use') return { problems: [], message: 'Your program has this session on a day. Remove it there first.' }
  if (e.body?.busy) return { problems: [], message: 'The server is busy with another save. Try again in a moment.' }
  if (e.body?.error === 'not_enabled') return { problems: [], message: 'Building sessions is not turned on for this account.' }
  return { problems: [], message: e.body?.detail ?? 'The session could not be saved. Try again.' }
}

export function useSaveManualSession() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (session: ManualSession) => (session.id
      ? apiClient.put(`/manual/sessions/${session.id}`, { session })
      : apiClient.post('/manual/sessions', { session })) as unknown as Promise<{ session: DescribedSession }>,
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.all }), refreshAfterMethodChange(client)]),
  })
}

export function useDeleteManualSession() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiClient.delete(`/manual/sessions/${id}`) as unknown as Promise<{ removed: boolean }>,
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.all }), refreshAfterMethodChange(client)]),
  })
}

// ─── Programs laid out by hand (roadmap 24.4) ────────────────────────────────

export interface DescribedDay {
  day: string
  light: boolean
  minutes: number
  sessions: { id: string; name: string; modality: string; minutes: number }[]
}

export interface DescribedPhase {
  id: string
  name: string
  kind: string
  weeks: number
  template: ManualDay[][]
  weeksDescribed: DescribedDay[][]
  firstWeek: number
  lastWeek: number
  /** The weeks of the program (1-based) that run light. */
  lighterWeeks: number[]
  sessionsPerWeek: number
  minutesPerWeek: number
}

export interface DescribedTrack extends Omit<ManualTrack, 'phases'> {
  id: string
  phases: DescribedPhase[]
  totalWeeks: number
  frameworkId: string
  equipment: string[]
  /** What moves, week of the program by week, in the server's words. */
  forecast: { session: string; exercise: string; weeks: { week: number; text: string | null; light: boolean }[] }[]
  /** The generate constraints that build the program as laid. */
  startWith: { days_per_week: number; session_time_minutes: number }
}

export interface ManualTracksAnswer {
  packageId: string
  tracks: DescribedTrack[]
  kinds: { id: string; label: string; excludesMaxEffort: boolean }[]
  limits: { tracks: number; phases: number; templateWeeks: number; daySessions: number; phaseWeeks: number }
}

export interface TrackPreviewAnswer { ok: boolean; problems: TrackProblem[]; track: DescribedTrack | null }

export function useManualTracks() {
  return useQuery({
    queryKey: manualKeys.tracks,
    queryFn: () => apiClient.get('/manual/tracks') as unknown as Promise<ManualTracksAnswer>,
  })
}

export function useManualTrackPreview(track: ManualTrack, enabled: boolean) {
  const body = JSON.stringify(track)
  return useQuery({
    queryKey: manualKeys.trackPreview(body),
    queryFn: () => apiClient.post('/manual/tracks/preview', { track }) as unknown as Promise<TrackPreviewAnswer>,
    enabled,
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  })
}

/** Why a program's save or delete was refused: the problems, else one sentence. */
export function trackRefusal(error: unknown): { problems: TrackProblem[]; message: string } {
  const e = (error ?? {}) as { body?: { error?: string; detail?: string; problems?: TrackProblem[]; busy?: boolean } }
  if (e.body?.problems?.length) return { problems: e.body.problems, message: e.body.problems[0].message }
  if (e.body?.error === 'in_use') return { problems: [], message: 'Your program runs on this. Start another program first.' }
  if (e.body?.busy) return { problems: [], message: 'The server is busy with another save. Try again in a moment.' }
  if (e.body?.error === 'not_enabled') return { problems: [], message: 'Building programs is not turned on for this account.' }
  return { problems: [], message: e.body?.detail ?? 'The program could not be saved. Try again.' }
}

export function useSaveManualTrack() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (track: ManualTrack) => (track.id
      ? apiClient.put(`/manual/tracks/${track.id}`, { track })
      : apiClient.post('/manual/tracks', { track })) as unknown as Promise<{ track: DescribedTrack }>,
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.tracks }), refreshAfterMethodChange(client)]),
  })
}

export function useDeleteManualTrack() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiClient.delete(`/manual/tracks/${id}`) as unknown as Promise<{ removed: boolean }>,
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.tracks }), refreshAfterMethodChange(client)]),
  })
}
