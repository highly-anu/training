import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'

export interface SimilarityResult {
  score: number
  primary:   { label: string; detail: string; value: number }
  secondary: { label: string; detail: string; value: number }
}

/** {category -> {id_a -> {id_b -> SimilarityResult}}} */
export type SimilarityMatrix = Record<string, Record<string, Record<string, SimilarityResult>>>

export function useSimilarity() {
  return useQuery({
    queryKey: queryKeys.similarity.all,
    queryFn: () => apiClient.get<SimilarityMatrix>('/similarity') as unknown as Promise<SimilarityMatrix>,
    staleTime: Infinity,
  })
}

/** Return the top-N most similar items to `id` within `category`. */
export function getTopSimilar(
  matrix: SimilarityMatrix,
  category: string,
  id: string,
  n = 5,
): Array<{ id: string } & SimilarityResult> {
  const peers = matrix[category]?.[id]
  if (!peers) return []
  return Object.entries(peers)
    .map(([peerId, result]) => ({ id: peerId, ...result }))
    .sort((a, b) => b.score - a.score)
    .slice(0, n)
}
