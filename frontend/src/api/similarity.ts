import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'

export interface SimilarityResult {
  score: number
  primary:   { label: string; detail: string; value: number }
  secondary: { label: string; detail: string; value: number }
}

/**
 * One category from `GET /similarity` (`src/similarity._category`): every
 * pair's score once — the upper triangle of the matrix, row by row, in `ids`
 * order — and each item's nearest peers with their explanations.
 */
export interface SimilarityCategory {
  ids: string[]
  scores: number[]
  top: Record<string, Array<{ id: string } & SimilarityResult>>
}

/** {category -> SimilarityCategory} */
export type SimilarityMatrix = Record<string, SimilarityCategory>

export function useSimilarity() {
  return useQuery({
    queryKey: queryKeys.similarity.all,
    queryFn: () => apiClient.get<SimilarityMatrix>('/similarity') as unknown as Promise<SimilarityMatrix>,
    staleTime: Infinity,
  })
}

/** Where (i, j) of an n×n symmetric matrix sits in its upper triangle, row by row. */
export function pairIndex(i: number, j: number, n: number): number {
  const [a, b] = i < j ? [i, j] : [j, i]
  return a * n - (a * (a + 1)) / 2 + (b - a - 1)
}

/** The score of two items of one category (0 when either is unknown or they are the same). */
export function likenessScorer(
  category: SimilarityCategory | undefined,
): ((a: string, b: string) => number) | undefined {
  if (!category?.ids || !category.scores) return undefined
  const n = category.ids.length
  const index = new Map(category.ids.map((id, i) => [id, i]))
  return (a, b) => {
    const i = index.get(a)
    const j = index.get(b)
    if (i === undefined || j === undefined || i === j) return 0
    return category.scores[pairIndex(i, j, n)] ?? 0
  }
}

/** Return the top-N most similar items to `id` within `category`. */
export function getTopSimilar(
  matrix: SimilarityMatrix,
  category: string,
  id: string,
  n = 5,
): Array<{ id: string } & SimilarityResult> {
  return (matrix[category]?.top?.[id] ?? []).slice(0, n)
}
