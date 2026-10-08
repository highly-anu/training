import { describe, expect, it } from 'vitest'
import { pairingCode, safeReturnPath } from './returnPath'

describe('safeReturnPath', () => {
  it('keeps an in-app path with its query', () => {
    expect(safeReturnPath('/pair?code=ABC234')).toBe('/pair?code=ABC234')
    expect(safeReturnPath('/settings?tab=connections')).toBe('/settings?tab=connections')
  })

  it('never leaves the site', () => {
    expect(safeReturnPath('https://evil.example/pair')).toBe('/')
    expect(safeReturnPath('//evil.example/pair')).toBe('/')
    expect(safeReturnPath('/\\evil.example')).toBe('/')
    expect(safeReturnPath('javascript:alert(1)')).toBe('/')
  })

  it('goes Home for nothing, a non-string or the login page', () => {
    expect(safeReturnPath(undefined)).toBe('/')
    expect(safeReturnPath({ pathname: '/pair' })).toBe('/')
    expect(safeReturnPath('/login')).toBe('/')
    expect(safeReturnPath('/login?next=/x')).toBe('/')
  })
})

describe('pairingCode', () => {
  it('normalises a code the watch shows', () => {
    expect(pairingCode(' abc234 ')).toBe('ABC234')
  })

  it('refuses anything else', () => {
    expect(pairingCode(null)).toBeNull()
    expect(pairingCode('')).toBeNull()
    expect(pairingCode('ABC23')).toBeNull()      // too short
    expect(pairingCode('ABCO23')).toBeNull()     // O is not in the alphabet
    expect(pairingCode('ABC2345')).toBeNull()    // too long
  })
})
