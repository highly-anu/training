/**
 * GET /similarity's compact shape (src/similarity._category): the upper
 * triangle read back by pair, and the nearest peers as the server ranked them.
 */
import { describe, it, expect } from 'vitest'
import { pairIndex, likenessScorer, getTopSimilar, type SimilarityMatrix } from './similarity'

const result = (score: number) => ({
  score, primary: { label: 'p', detail: 'd', value: score }, secondary: { label: 's', detail: 'd', value: score },
})

// a–b 0.9, a–c 0.1, a–d 0.8, b–c 0.2, b–d 0.7, c–d 0.6
const matrix: SimilarityMatrix = {
  exercises: {
    ids: ['a', 'b', 'c', 'd'],
    scores: [0.9, 0.1, 0.8, 0.2, 0.7, 0.6],
    top: { a: [{ id: 'b', ...result(0.9) }, { id: 'd', ...result(0.8) }] },
  },
}

describe('similarity', () => {
  it('indexes the upper triangle row by row, either way round', () => {
    expect([pairIndex(0, 1, 4), pairIndex(0, 3, 4), pairIndex(1, 2, 4), pairIndex(2, 3, 4)]).toEqual([0, 2, 3, 5])
    expect(pairIndex(3, 2, 4)).toBe(pairIndex(2, 3, 4))
  })

  it('scores any two items, and nothing it does not know', () => {
    const score = likenessScorer(matrix.exercises)!
    expect(score('a', 'd')).toBe(0.8)
    expect(score('d', 'b')).toBe(0.7)
    expect(score('c', 'd')).toBe(0.6)
    expect(score('a', 'a')).toBe(0)
    expect(score('a', 'zz')).toBe(0)
    expect(likenessScorer(undefined)).toBeUndefined()
  })

  it('takes the nearest peers as the server ranked them', () => {
    expect(getTopSimilar(matrix, 'exercises', 'a', 1).map(p => p.id)).toEqual(['b'])
    expect(getTopSimilar(matrix, 'exercises', 'c')).toEqual([])
    expect(getTopSimilar(matrix, 'archetypes', 'a')).toEqual([])
  })
})
