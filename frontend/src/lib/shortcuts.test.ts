// @vitest-environment jsdom
import { describe, it, expect } from 'vitest'
import { SHORTCUTS, isTyping, keysFor, readKey } from './shortcuts'

describe('readKey', () => {
  it('goes to a section on g then its letter', () => {
    const first = readKey(null, 'g')
    expect(first).toEqual({ prefix: 'g' })
    expect(readKey(first.prefix, 'p')).toEqual({ action: { type: 'go', to: '/program' }, prefix: null })
  })

  it('drops the prefix on a key that completes nothing', () => {
    expect(readKey('g', 'x')).toEqual({ prefix: null })
  })

  it('does not read a section letter without its g', () => {
    expect(readKey(null, 'p')).toEqual({ prefix: null })
  })

  it('steps the week and opens the list on one key', () => {
    expect(readKey(null, '[').action).toEqual({ type: 'week', delta: -1 })
    expect(readKey(null, ']').action).toEqual({ type: 'week', delta: 1 })
    expect(readKey(null, '?').action).toEqual({ type: 'help' })
  })
})

describe('the table', () => {
  it('has no two shortcuts on the same keys', () => {
    const keys = SHORTCUTS.map((s) => s.keys)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('names the keys for a route', () => {
    expect(keysFor('/')).toBe('g t')
    expect(keysFor('/nowhere')).toBeUndefined()
  })
})

describe('isTyping', () => {
  const el = (html: string) => {
    const host = document.createElement('div')
    host.innerHTML = html
    return host.firstElementChild
  }

  it('is true in a field', () => {
    expect(isTyping(el('<input type="text">'))).toBe(true)
    expect(isTyping(el('<input type="number">'))).toBe(true)
    expect(isTyping(el('<textarea></textarea>'))).toBe(true)
    expect(isTyping(el('<div role="combobox"></div>'))).toBe(true)
  })

  it('is false on a button, a checkbox and the page', () => {
    expect(isTyping(el('<button></button>'))).toBe(false)
    expect(isTyping(el('<input type="checkbox">'))).toBe(false)
    expect(isTyping(document.body)).toBe(false)
    expect(isTyping(null)).toBe(false)
  })
})
