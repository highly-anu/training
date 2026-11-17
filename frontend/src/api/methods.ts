import { useMutation, useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'

/**
 * An athlete's own methods and the builds that write them (docs/roadmap.md
 * item 21). The athlete reads *method*; the server keeps *package*.
 */

export interface Method {
  id: string
  name: string
  revision: number
  status: string
  updatedAt: string
  /** The active program is built from it: it cannot be deleted. */
  inUse: boolean
}

export type BuildStatus = 'queued' | 'running' | 'done' | 'failed' | 'cancelled'

export interface BuildProblem { stage?: string | null; code?: string | null; file?: string | null; message?: string | null }

export interface MethodBuild {
  id: string
  status: BuildStatus
  progress: { stage?: string; detail?: string; turns?: number; checks?: number; files?: number; problems?: number }
  result: { packageId: string; revision: number; name: string; summary: string } | null
  error: { code: string; message: string; detail?: string; problems?: BuildProblem[] } | null
  /** The athlete's words, shortened. */
  description: string
  /** The id of the method this build revises, when it is a revision. */
  revise: string | null
  createdAt: string
  updatedAt: string
}

export interface MethodsAnswer {
  /** Whether a build can start now. */
  available: boolean
  /** Why not: `not_enabled` for this athlete, `no_model_key` on the server. */
  reason: string | null
  methods: Method[]
  /** The open build first, then recent ones. */
  builds: MethodBuild[]
  limits: { daily: number; remaining: number; kept: number }
}

export interface BuildAnswers { days?: number; minutes?: number; level?: string; equipment?: string[] }

export type BuildRequest =
  | { description: string; answers: BuildAnswers; pastedText?: string; webSearch?: boolean }
  | { revise: { packageId: string; note: string }; answers?: BuildAnswers; webSearch?: boolean }

export const isOpen = (build: Pick<MethodBuild, 'status'> | null | undefined): boolean =>
  build?.status === 'queued' || build?.status === 'running'

export function useMethods() {
  return useQuery({
    queryKey: queryKeys.methods.all,
    queryFn: () => apiClient.get<MethodsAnswer>('/methods') as unknown as Promise<MethodsAnswer>,
    staleTime: 30_000,
    // A build may finish while the athlete is elsewhere in the app.
    refetchInterval: (query) => (isOpen(query.state.data?.builds[0]) ? 5000 : false),
  })
}

/** One build, asked again every two seconds while it is open. */
export function useMethodBuild(id: string | undefined) {
  return useQuery({
    queryKey: queryKeys.methods.build(id ?? ''),
    enabled: !!id,
    queryFn: async () =>
      ((await apiClient.get(`/methods/builds/${encodeURIComponent(id!)}`)) as unknown as { build: MethodBuild }).build,
    refetchInterval: (query) => (!query.state.data || isOpen(query.state.data) ? 2000 : false),
  })
}

/**
 * Everything that lists packages was read before this method existed (or
 * while it had other contents): the philosophies, Explore's documents, the
 * frameworks, archetypes and exercises, the vocabulary a package may bring.
 */
export function refreshAfterMethodChange(client: QueryClient): Promise<unknown> {
  return Promise.all([
    queryKeys.methods.all, queryKeys.philosophies.all, queryKeys.frameworks.all, queryKeys.archetypes.all,
    queryKeys.exercises.all, queryKeys.modalities.all, queryKeys.equipment.all, queryKeys.similarity.all,
    queryKeys.analytics.specs, ['explore'] as const,
  ].map((queryKey) => client.invalidateQueries({ queryKey })))
}

export function useStartBuild() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: async (body: BuildRequest) =>
      ((await apiClient.post('/methods/builds', body)) as unknown as { build: MethodBuild }).build,
    onSettled: () => client.invalidateQueries({ queryKey: queryKeys.methods.all }),
  })
}

export function useCancelBuild() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) =>
      ((await apiClient.post(`/methods/builds/${encodeURIComponent(id)}/cancel`)) as unknown as { build: MethodBuild }).build,
    onSuccess: (build) => {
      client.setQueryData(queryKeys.methods.build(build.id), build)
      void client.invalidateQueries({ queryKey: queryKeys.methods.all })
    },
  })
}

export function useDeleteMethod() {
  const client = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiClient.delete(`/methods/${encodeURIComponent(id)}`),
    onSuccess: () => refreshAfterMethodChange(client),
  })
}
