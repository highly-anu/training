// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { SubTabs, nextTab, tabDomId } from './SubTabs'

afterEach(cleanup)

const IDS = ['a', 'b', 'c'] as const
const TABS = IDS.map((id) => ({ id, label: id.toUpperCase() }))

describe('nextTab', () => {
  it('moves with the arrows and wraps', () => {
    expect(nextTab(IDS, 'a', 'ArrowRight')).toBe('b')
    expect(nextTab(IDS, 'c', 'ArrowRight')).toBe('a')
    expect(nextTab(IDS, 'a', 'ArrowLeft')).toBe('c')
  })
  it('jumps to the ends', () => {
    expect(nextTab(IDS, 'b', 'Home')).toBe('a')
    expect(nextTab(IDS, 'b', 'End')).toBe('c')
  })
  it('leaves every other key alone', () => {
    expect(nextTab(IDS, 'b', 'Enter')).toBeNull()
    expect(nextTab(IDS, 'b', 'ArrowDown')).toBeNull()
  })
})

describe('<SubTabs>', () => {
  it('is a tablist with one tab in the tab order', () => {
    render(<SubTabs id="t" label="Sections" tabs={TABS} active="b" onChange={() => {}} />)
    expect(screen.getByRole('tablist', { name: 'Sections' })).toBeTruthy()
    const tabs = screen.getAllByRole('tab')
    expect(tabs.map((t) => t.getAttribute('aria-selected'))).toEqual(['false', 'true', 'false'])
    expect(tabs.map((t) => t.tabIndex)).toEqual([-1, 0, -1])
    expect(tabs[1].id).toBe(tabDomId('t', 'b'))
  })

  it('selects on click and on an arrow key', () => {
    const onChange = vi.fn()
    render(<SubTabs id="t" label="Sections" tabs={TABS} active="b" onChange={onChange} />)
    fireEvent.click(screen.getByRole('tab', { name: 'A' }))
    expect(onChange).toHaveBeenLastCalledWith('a')
    fireEvent.keyDown(screen.getByRole('tab', { name: 'B' }), { key: 'ArrowRight' })
    expect(onChange).toHaveBeenLastCalledWith('c')
  })
})
