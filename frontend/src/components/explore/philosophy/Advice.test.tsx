// @vitest-environment jsdom
/**
 * A per-level `advice` (Ido's Floreio versions) reaches the page as
 * `adviceByLevel`; rendered raw as `advice`, the object crashed Explore.
 */
import { describe, it, expect, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { Advice } from './Advice'

afterEach(cleanup)

describe('Advice', () => {
  it('shows one text', () => {
    render(<Advice advice="Repeat after a week away." />)
    expect(screen.getByText('Repeat after a week away.')).toBeTruthy()
  })

  it("shows each level's sentence after its name", () => {
    render(<Advice advice={null} byLevel={[{ level: 'novice', text: 'Then intermediate.' },
                                           { level: 'intermediate', text: 'Then advanced.' }]} />)
    expect(screen.getByText('Novice:')).toBeTruthy()
    expect(screen.getByText('Then advanced.', { exact: false })).toBeTruthy()
  })

  it('renders nothing without advice', () => {
    const { container } = render(<Advice advice={null} byLevel={null} />)
    expect(container.textContent).toBe('')
  })
})
