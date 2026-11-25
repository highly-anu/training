import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { refreshAfterMethodChange } from './methods'
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
  recipe?: ShareRecipe | null
}

export type ShareRequest =
  | { kind: 'package'; package_id: string }
  | { kind: 'program' }
  | { kind: 'session'; key: string; date?: string }

const MINE = ['shares', 'mine'] as const

export function useShare(token: string | undefined, viewer?: string | null) {
  return useQuery<ShareDocument>({
    // Asked again once someone signs in: the answer then says what they have.
    queryKey: ['shares', token, viewer ?? null],
    queryFn: () => apiClient.get(`/shares/${encodeURIComponent(token ?? '')}`) as unknown as Promise<ShareDocument>,
    enabled: !!token,
    retry: false,
    staleTime: 60_000,
  })
}

/** generate's body as the server wrote it for the viewer (src/sharing.recipe_for). */
export interface ShareRecipe {
  num_weeks?: number
  philosophy_id?: string
  philosophy_ids?: string[]
  philosophy_weights?: Record<string, number>
  lanes?: { philosophy_id: string; track_id: string | null; weight: number; start_phase?: string }[]
  track_id?: string
  start_phase?: string
  contract_options?: Record<string, string>
}

export interface SaveShareResult { ok: boolean; installed: { id: string; name: string }[] }

/** Why a save was refused, as the route says it. */
export interface SaveShareRefusal {
  error?: 'different' | 'too_many_packages' | 'not_installable' | 'not_enabled' | 'not_found' | 'store_unavailable'
  busy?: boolean
  olderEngine?: boolean
  name?: string
  methods?: { id: string; name: string }[]
  problems?: { message: string }[]
}

export function useSaveShare(token: string) {
  const qc = useQueryClient()
  return useMutation<SaveShareResult, Error & { status?: number; body?: SaveShareRefusal }, { replace?: boolean } | void>({
    mutationFn: (opts) => apiClient.post(`/shares/${encodeURIComponent(token)}/save`, { replace: !!opts?.replace }) as unknown as Promise<SaveShareResult>,
    onSuccess: () => {
      // Every list of methods was read before this one existed.
      void refreshAfterMethodChange(qc)
      void qc.invalidateQueries({ queryKey: ['shares', token] })
    },
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
