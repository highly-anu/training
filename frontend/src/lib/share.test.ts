import { afterEach, describe, expect, it, vi } from 'vitest'
import { appLink, shareLink } from './share'

afterEach(() => vi.unstubAllGlobals())

describe('shareLink', () => {
  it('uses the share sheet where there is one', async () => {
    const share = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { share, clipboard: { writeText: vi.fn() } })
    expect(await shareLink('https://x/s/t', 'Fran')).toBe('shared')
    expect(share).toHaveBeenCalledWith({ url: 'https://x/s/t', title: 'Fran' })
  })

  it('says nothing and copies nothing when the sheet is closed', async () => {
    const writeText = vi.fn()
    vi.stubGlobal('navigator', { share: vi.fn().mockRejectedValue(Object.assign(new Error('x'), { name: 'AbortError' })), clipboard: { writeText } })
    expect(await shareLink('u', 't')).toBe('cancelled')
    expect(writeText).not.toHaveBeenCalled()
  })

  it('copies the link where there is no sheet, or the sheet failed', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    expect(await shareLink('u', 't')).toBe('copied')
    vi.stubGlobal('navigator', { share: vi.fn().mockRejectedValue(new Error('not allowed')), clipboard: { writeText } })
    expect(await shareLink('u2', 't')).toBe('copied')
    expect(writeText).toHaveBeenLastCalledWith('u2')
  })

  it('fails when it can do neither, so the button shows the link', async () => {
    vi.stubGlobal('navigator', {})
    expect(await shareLink('u', 't')).toBe('failed')
    vi.stubGlobal('navigator', { clipboard: { writeText: vi.fn().mockRejectedValue(new Error('denied')) } })
    expect(await shareLink('u', 't')).toBe('failed')
  })
})

describe('appLink', () => {
  it('is the app\'s own scheme with the token', () => {
    expect(appLink('a b')).toBe('trainingcompanion://share?token=a%20b')
  })
})
