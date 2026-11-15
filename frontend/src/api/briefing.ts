import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'

/**
 * Before a session: today's numbers beside the earlier times the same session
 * was done (GET /sessions/briefing, src/briefing.py). What an item is — a
 * contract module, a named workout, an exercise — is the package's
 * briefing.yaml; every sentence is the server's.
 */
export type BriefingStatus = 'clean' | 'made' | 'missed' | 'logged' | 'unconfirmed'

export interface BriefingOccurrence {
  date: string
  dayText: string
  text: string
  status: BriefingStatus
  isDeload: boolean
  sessionKey?: string | null
  values: Record<string, number>
}

export interface BriefingItem {
  id: string
  title: string
  today: {
    text: string
    values: Record<string, number>
    lines: { exerciseId: string; name: string; text: string }[]
    conditional: boolean
  }
  history: BriefingOccurrence[]
  times: number
  metric?: { id: string; label: string; unit: string }
  cycle?: { step: number; of: number; text: string }
  suggestion?: { kind: string; text: string }
  standard?: { id?: string; name?: string; best?: string; target?: string }
  notes?: string
}

export interface SessionBriefing {
  headline: string | null
  items: BriefingItem[]
  pending: { sessionKey: string; date: string; text: string }[]
}

export async function fetchBriefing(sessionKey: string): Promise<SessionBriefing> {
  return apiClient.get(`/sessions/briefing?key=${encodeURIComponent(sessionKey)}`) as unknown as Promise<SessionBriefing>
}

export function useSessionBriefing(sessionKey: string, enabled = true) {
  return useQuery({
    queryKey: queryKeys.briefing(sessionKey),
    queryFn: () => fetchBriefing(sessionKey),
    enabled,
    staleTime: 60 * 1000,
    retry: false,
  })
}
