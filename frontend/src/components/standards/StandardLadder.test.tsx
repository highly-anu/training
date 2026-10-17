// @vitest-environment jsdom
/**
 * One ladder for every standard on every screen: the rungs fill to the level
 * the server reached, in the colour of the modality the standard measures,
 * and the level is said in words. Before, Profile and Explore drew one flat
 * accent colour, the phone drew purple/blue/green per level, and Blocks a
 * status green — a level read as pass/fail on one screen and not the next.
 */
import { describe, it, expect, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { StandardLadder, StandardLevelBadge } from './StandardLadder'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { levelName, thresholdTexts } from '@/lib/standards'

afterEach(cleanup)

const FRAN = { entry: '12:00', intermediate: '8:00', advanced: '5:00', elite: '3:30' }

function rungs(container: HTMLElement) {
  return Array.from(container.querySelectorAll<HTMLElement>('[role="img"] > div > div'))
}

/** jsdom normalises an inline colour to rgb(); compare against the same. */
function rgb(hex: string) {
  const n = parseInt(hex.slice(1), 16)
  return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`
}

describe('StandardLadder', () => {
  it('fills to the level reached in the modality colour', () => {
    const { container } = render(<StandardLadder thresholds={FRAN} levelIndex={3} domain="mixed_modal_conditioning" />)
    const fills = rungs(container).map((r) => r.style.backgroundColor)
    const violet = rgb(MODALITY_COLORS.mixed_modal_conditioning.hex)
    expect(fills).toEqual([violet, violet, violet, ''])
    expect(screen.getByText('5:00')).toBeTruthy()
    expect(screen.getByText('elite')).toBeTruthy()
  })

  it('fills nothing below entry, and says there is no result when there is none', () => {
    const below = render(<StandardLadder thresholds={FRAN} levelIndex={0} domain="max_strength" />)
    expect(rungs(below.container).every((r) => r.style.backgroundColor === '')).toBe(true)
    cleanup()
    render(<StandardLadder thresholds={FRAN} domain="max_strength" />)
    expect(screen.getByRole('img').getAttribute('aria-label')).toBe('No result yet')
  })

  it('names a level, and below entry, in words', () => {
    render(<StandardLevelBadge level={null} domain="max_strength" />)
    expect(screen.getByText('Below entry')).toBeTruthy()
    expect(levelName('advanced')).toBe('Advanced')
  })

  it('falls back to number and unit for an older document without text', () => {
    expect(thresholdTexts(undefined, { entry: 1, intermediate: 1.5, advanced: 2, elite: 2.5 }, '×BW'))
      .toEqual({ entry: '1×BW', intermediate: '1.5×BW', advanced: '2×BW', elite: '2.5×BW' })
    expect(thresholdTexts(FRAN, { entry: 12 }, ' min').entry).toBe('12:00')
  })
})
