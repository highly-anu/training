import { useMutation, useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { apiClient } from './client'
import { refreshAfterMethodChange } from './methods'
import type { SessionBlock } from './types'
import type { BuilderProblem, ManualSession } from '@/lib/sessionBuilder'

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
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.sessions }), refreshAfterMethodChange(client)]),
  })
}

export function useDeleteManualSession() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiClient.delete(`/manual/sessions/${id}`) as unknown as Promise<{ removed: boolean }>,
    onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: manualKeys.sessions }), refreshAfterMethodChange(client)]),
  })
}
