import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import type { PhilosophyDescription, Session, TrainingPhase } from './types'

/**
 * Shared links (docs/roadmap.md item 25): a method, the program or one
 * session as `<web>/s/<token>`. The page's document needs no sign-in; signed
 * in, it also says which of the methods it needs the viewer has.
 */
export type ShareKind = 'package' | 'program' | 'session'

export interface ShareLink { token: string; kind: ShareKind; title: string | null; createdAt: string | null; url: string }

export interface SharedMethodRef { id: string; name: string; private: boolean }

export interface SharedSessionDoc {
  name: string
  session: Session
  day: string
  week: { week_number?: number; week_in_phase?: number; phase?: TrainingPhase; phase_name?: string; is_deload?: boolean }
  method?: { id: string; name: string }
  modalityDisplay?: { label?: string; short?: string; color?: string; icon?: unknown; family?: string }
}

export interface SharedProgramSummary {
  name: string | null
  weeks: number
  phases: { id: string | null; name: string | null; kind: string | null; weeks: number }[]
  tracks: { name: string | null; weight?: number }[]
  daysPerWeek: number | null
  sessionsPerWeek: number | null
}

export type MethodState = 'shipped' | 'have' | 'different' | 'missing'

export interface ShareAvailability {
  yours: boolean
  methods: { id: string; name: string; state: MethodState; savable: boolean }[]
  ready: boolean
  toSave: number
  room: number
  canSave: boolean
}

export interface ShareDocument {
  token: string
  kind: ShareKind
  title: string | null
  createdAt: string | null
  session?: SharedSessionDoc
  method?: { id: string; name: string; describe: PhilosophyDescription | null; shipped: boolean }
  program?: SharedProgramSummary
  methods?: SharedMethodRef[]
  availability?: ShareAvailability
  recipe?: Record<string, unknown> | null
}

export type ShareRequest =
  | { kind: 'package'; package_id: string }
  | { kind: 'program' }
  | { kind: 'session'; key: string; date?: string }

const MINE = ['shares', 'mine'] as const

export function useShare(token: string | undefined) {
  return useQuery<ShareDocument>({
    queryKey: ['shares', token],
    queryFn: () => apiClient.get(`/shares/${encodeURIComponent(token ?? '')}`) as unknown as Promise<ShareDocument>,
    enabled: !!token,
    retry: false,
    staleTime: 60_000,
  })
}

export function createShare(request: ShareRequest): Promise<ShareLink> {
  return apiClient.post('/shares', request) as unknown as Promise<ShareLink>
}

export function useCreateShare() {
  const qc = useQueryClient()
  return useMutation<ShareLink, Error, ShareRequest>({
    mutationFn: createShare,
    onSuccess: () => { void qc.invalidateQueries({ queryKey: MINE }) },
  })
}

export function useMyShares() {
  return useQuery<{ shares: ShareLink[]; limit: number }>({
    queryKey: MINE,
    queryFn: () => apiClient.get('/shares') as unknown as Promise<{ shares: ShareLink[]; limit: number }>,
    staleTime: 30_000,
  })
}

export function useRevokeShare() {
  const qc = useQueryClient()
  return useMutation<{ revoked: boolean }, Error, string>({
    mutationFn: (token) => apiClient.delete(`/shares/${encodeURIComponent(token)}`) as unknown as Promise<{ revoked: boolean }>,
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['shares'] }) },
  })
}
