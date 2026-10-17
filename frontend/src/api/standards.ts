import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { BenchmarkStandard, StandardResultInput, StandardResults, StandardSuggestion } from './types'
import { useProfileStore } from '@/store/profileStore'
import benchmarksData from '@/data/static/benchmarks.json'

/**
 * The standards' ladders for this athlete. `GET /api/standards?sex=` serves
 * the female or male tables; the bundled JSON (male values, the same shape —
 * `scripts/dump_static_data.py`) is the fallback when the API is unreachable.
 */
export function useStandards() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.standards.all, sex],
    queryFn: async () => {
      try {
        return await (apiClient.get(`/standards?sex=${sex}`) as unknown as Promise<BenchmarkStandard[]>)
      } catch {
        return benchmarksData as BenchmarkStandard[]
      }
    },
    staleTime: Infinity,
  })
}

/**
 * The athlete's results: per standard the current and best result with the
 * level the server worked out, and every entry. No client computes a level.
 */
export function useStandardResults() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.standards.results, sex],
    queryFn: () => apiClient.get('/standards/results') as unknown as Promise<StandardResults>,
    staleTime: 60_000,
  })
}

function useRefreshResults() {
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: queryKeys.standards.results })
    void qc.invalidateQueries({ queryKey: queryKeys.analytics.program })
    void qc.invalidateQueries({ queryKey: queryKeys.analytics.development })
  }
}

/**
 * Log one result (or a bodyweight). `text` is what the athlete typed — "4:58"
 * for a time — or, for a ×BW standard, `kg` and `reps`; the server parses and
 * converts. Refreshes everything that reads results.
 */
export function useLogResult() {
  const refresh = useRefreshResults()
  return useMutation<{ saved: string; id: number; valueText: string }, Error, StandardResultInput & { benchmarkId: string }>({
    mutationFn: (body) =>
      apiClient.post('/standards/results', { ...body, loggedAt: new Date().toISOString() }) as unknown as Promise<{ saved: string; id: number; valueText: string }>,
    onSuccess: refresh,
  })
}

/** Correct one result: its value, its day or its note. */
export function useUpdateResult() {
  const refresh = useRefreshResults()
  return useMutation<{ updated: number }, Error, StandardResultInput & { id: number }>({
    mutationFn: ({ id, ...body }) =>
      apiClient.patch(`/standards/results/${id}`, body) as unknown as Promise<{ updated: number }>,
    onSuccess: refresh,
  })
}

/** Delete one result — never the standard's whole history. */
export function useDeleteResult() {
  const refresh = useRefreshResults()
  return useMutation<{ deleted: number }, Error, number>({
    mutationFn: (id) => apiClient.delete(`/standards/results/${id}`) as unknown as Promise<{ deleted: number }>,
    onSuccess: refresh,
  })
}

/**
 * Results logged sessions suggest, waiting for a decision: a test slot's
 * outcome, or a single that beats the current result. Not results until
 * confirmed (src/standard_results.py).
 */
export function useStandardSuggestions() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.standards.suggestions, sex],
    queryFn: async () => {
      const res = await (apiClient.get('/standards/suggestions') as unknown as Promise<{ suggestions: StandardSuggestion[] }>)
      return res.suggestions
    },
    staleTime: 60_000,
  })
}

type Decision = { id: number; action: 'confirm' | 'dismiss' | 'reopen'; text?: string }

/**
 * Save (confirm, optionally correcting the value as typed), "Not a test"
 * (dismiss) or undo a dismissal. Refreshes the suggestions and everything
 * that reads results.
 */
export function useDecideSuggestion() {
  const qc = useQueryClient()
  const refresh = useRefreshResults()
  return useMutation<{ suggestion: StandardSuggestion | null }, Error, Decision>({
    mutationFn: ({ id, action, text }) =>
      apiClient.post(`/standards/suggestions/${id}/${action}`, { via: 'web', ...(text ? { text } : {}) }) as unknown as
        Promise<{ suggestion: StandardSuggestion | null }>,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: queryKeys.standards.suggestions })
      refresh()
    },
  })
}
