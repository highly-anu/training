import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type {
  PlannedSession,
  ProgramHistoryDetail,
  ProgramHistoryEntry,
} from '@/api/types'

/**
 * Program history: which plan was in force when, and what it planned each day.
 *
 * The server keeps one program per athlete and overwrites it, so before this
 * existed a replaced plan was simply gone and a workout dated inside it could
 * never be matched. `src/program_history.py` archives every version with the
 * dates it was in force; these read that archive.
 */

const BASE = '/programs'

export async function fetchProgramHistory(): Promise<ProgramHistoryEntry[]> {
  return apiClient.get(`${BASE}/history`) as unknown as Promise<ProgramHistoryEntry[]>
}

export async function fetchProgramVersion(versionId: string): Promise<ProgramHistoryDetail> {
  return apiClient.get(
    `${BASE}/history/${encodeURIComponent(versionId)}`
  ) as unknown as Promise<ProgramHistoryDetail>
}

export async function fetchPlannedSessions(
  from?: string,
  to?: string
): Promise<{ from: string; to: string; sessions: PlannedSession[] }> {
  const qs = new URLSearchParams()
  if (from) qs.set('from', from)
  if (to) qs.set('to', to)
  const suffix = qs.toString() ? `?${qs}` : ''
  return apiClient.get(`${BASE}/planned-sessions${suffix}`) as unknown as Promise<{
    from: string
    to: string
    sessions: PlannedSession[]
  }>
}

export function useProgramHistory() {
  return useQuery({
    queryKey: queryKeys.programs.history,
    queryFn: fetchProgramHistory,
    staleTime: 60_000,
  })
}

export function useProgramVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: queryKeys.programs.version(versionId ?? ''),
    queryFn: () => fetchProgramVersion(versionId!),
    enabled: Boolean(versionId),
    staleTime: Infinity,      // an archived version is immutable
  })
}

export function usePlannedSessions(from?: string, to?: string) {
  return useQuery({
    queryKey: queryKeys.programs.plannedSessions(from, to),
    queryFn: () => fetchPlannedSessions(from, to),
    staleTime: 60_000,
  })
}
