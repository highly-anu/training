import { likenessScorer, type SimilarityCategory } from '@/api/similarity'

export const MIN_COMPARE = 2
export const MAX_COMPARE = 3

/** `?compare=a,b[,c]` → distinct ids in order, at most three. */
export function parseCompare(raw: string | null): string[] {
  const ids: string[] = []
  for (const part of (raw ?? '').split(',')) {
    const id = part.trim()
    if (id && !ids.includes(id)) ids.push(id)
  }
  return ids.slice(0, MAX_COMPARE)
}

/** Every id not in `ids`, the most alike to them first (mean likeness to the
 *  ones already chosen, from GET /similarity); in `all`'s order without it. */
export function nearestTo(ids: string[], all: string[], category?: SimilarityCategory): string[] {
  const rest = all.filter((id) => !ids.includes(id))
  const score = likenessScorer(category)
  if (!score || !ids.length) return rest
  const mean = (id: string) => ids.reduce((s, x) => s + score(id, x), 0) / ids.length
  return [...rest].sort((a, b) => mean(b) - mean(a))
}

/** The grid every row shares: a label column, then one column per philosophy. */
export function gridStyle(n: number) {
  return { gridTemplateColumns: `minmax(7rem, 9rem) repeat(${n}, minmax(11rem, 1fr))` }
}
