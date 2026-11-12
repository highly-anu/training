import { describe, it, expect } from 'vitest'
import { rememberScroll } from './useScrollRestore'

describe('rememberScroll', () => {
  it('keeps the latest place per history entry', () => {
    const store = new Map<string, number>()
    rememberScroll('a|', 120, store)
    rememberScroll('a|', 480, store)
    expect(store.get('a|')).toBe(480)
    expect(store.size).toBe(1)
  })

  it('forgets the entry used longest ago past the cap', () => {
    const store = new Map<string, number>()
    rememberScroll('a|', 1, store, 2)
    rememberScroll('b|', 2, store, 2)
    rememberScroll('a|', 3, store, 2) // a is now the newest
    rememberScroll('c|', 4, store, 2)
    expect([...store.keys()]).toEqual(['a|', 'c|'])
  })
})
