// @vitest-environment jsdom
/**
 * The glance pieces a reader has to understand without a legend: who a track
 * is written for, which days of a week train, and where a phase sits in the
 * track's weeks.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { TipProvider } from '@/components/shared/Tip'
import { LevelScale, PhaseTimeline, WeekDays } from './Glance'

afterEach(cleanup)

describe('LevelScale', () => {
  const ranks = (el: HTMLElement) => Array.from(el.children) as HTMLElement[]

  it('draws all four ranks whatever it serves, so it never changes size', () => {
    const { rerender } = render(<LevelScale levels={['novice']} />)
    for (const levels of [['novice'], ['novice', 'intermediate', 'advanced', 'elite'], []] as const) {
      rerender(<LevelScale levels={[...levels]} />)
      const all = ranks(screen.getByRole('img'))
      expect(all.map((r) => r.dataset.level)).toEqual(['novice', 'intermediate', 'advanced', 'elite'])
      // One chevron for novice, up to four for elite.
      expect(all.map((r) => r.querySelectorAll('path').length)).toEqual([1, 2, 3, 4])
      expect(all.filter((r) => r.dataset.serves === 'true')).toHaveLength(levels.length)
    }
  })

  it('says which levels it is written for and which not', () => {
    render(<LevelScale levels={['novice', 'intermediate']} />)
    const scale = screen.getByRole('img', { name: 'Written for Novice, Intermediate; not for Advanced, Elite' })
    expect(ranks(scale)[2].title).toBe('Advanced: not written for it')
  })
})

describe('WeekDays', () => {
  it("letters the source's own days and counts training against rest", () => {
    const days = [['max_strength'], null, ['max_strength'], null, ['max_strength', 'mobility'], null, null]
    render(<WeekDays phase={{ days, daysPerWeek: 3, sessionsPerWeek: 4 }} />)
    const week = screen.getByRole('img', { name: '3 training days, 4 rest: trains Monday, Wednesday, Friday' })
    expect(week.textContent).toContain('MTWTFSS')
    expect(week.textContent).toContain('3 training · 4 rest')
  })

  it('shows seven days with no weekday when the athlete places them', () => {
    render(<WeekDays phase={{ days: null, daysPerWeek: 4, sessionsPerWeek: 6 }} />)
    const week = screen.getByRole('img', { name: '4 training days, 3 rest, on the days you choose' })
    expect(week.textContent).not.toContain('M')
    expect(week.firstElementChild?.children).toHaveLength(7)
  })
})

describe('PhaseTimeline', () => {
  it('names each phase with its weeks and opens the one pressed', () => {
    const onSelect = vi.fn()
    render(
      <TipProvider>
        <PhaseTimeline onSelect={onSelect} selected="b" repeats phases={[
          { id: 'a', name: 'Base', kind: 'base', weeks: 4 },
          { id: 'b', name: 'Build', kind: 'build', weeks: 6 },
          { id: 'c', name: 'Taper', kind: 'taper', weeks: 1 },
        ]} />
      </TipProvider>,
    )
    expect(screen.getByText('11 weeks, then again')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Base, weeks 1–4' }).getAttribute('aria-pressed')).toBe('false')
    expect(screen.getByRole('button', { name: 'Build, weeks 5–10' }).getAttribute('aria-pressed')).toBe('true')
    fireEvent.click(screen.getByRole('button', { name: 'Taper, week 11' }))
    expect(onSelect).toHaveBeenCalledWith('c')
  })
})
