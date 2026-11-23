// @vitest-environment jsdom
/**
 * The session browser: a searched, narrowed list beside the session picked,
 * drawn in blocks; on a narrow screen the list alone, a session in a sheet.
 * The document is the server's (mocks/fixtures/philosophy-describe.json).
 */
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, within } from '@testing-library/react'
import fixture from '@/mocks/fixtures/philosophy-describe.json'
import type { DescribedSessionGroup, PhilosophyDescription } from '@/api/types'
import { TipProvider } from '@/components/shared/Tip'
import { SessionBrowser } from './SessionBrowser'

const doc = fixture as unknown as PhilosophyDescription

function screenIs(wide: boolean) {
  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: wide, media: query, addEventListener: () => {}, removeEventListener: () => {},
  }))
}

beforeEach(() => screenIs(true))
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

function mount(props: Partial<Parameters<typeof SessionBrowser>[0]> = {}) {
  const onSelect = vi.fn()
  render(
    <TipProvider>
      <SessionBrowser groups={doc.groups} sessions={doc.sessions} selectedId={null} onSelect={onSelect} {...props} />
    </TipProvider>,
  )
  return onSelect
}

const row = (name: string) => screen.getAllByText(name).map((el) => el.closest('button[data-session]')).find(Boolean) as HTMLElement
const rows = () => Array.from(document.querySelectorAll('[data-session]')).map((el) => el.getAttribute('data-session'))
const detail = () => screen.getByRole('article')

describe('SessionBrowser, beside the list', () => {
  it('lists every session under its group and opens the first beside it', () => {
    mount()
    expect(rows()).toEqual(['w1', 'h1', 'h2', 'e1', 'c1', 'loose', 't1'])
    expect(screen.getByRole('region', { name: 'Heavy' })).toBeTruthy()
    expect(screen.getByText('7 sessions')).toBeTruthy()
    expect(within(detail()).getByRole('heading', { name: 'W1' })).toBeTruthy()
    expect(row('W1').getAttribute('aria-current')).toBe('true')
  })

  it('gives a group of one no heading, its name under the session where they differ', () => {
    mount()
    expect(screen.queryByRole('heading', { name: /Swings/ })).toBeNull()
    expect(within(row('C1')).getByText('Swings')).toBeTruthy()
    expect(screen.getByRole('heading', { name: /Heavy/ })).toBeTruthy()
  })

  it('asks for the session a row names, and draws the one it is given', () => {
    const onSelect = mount({ selectedId: 'h2' })
    const open = within(detail())
    expect(open.getByRole('heading', { name: 'H2' })).toBeTruthy()
    expect(open.getByText(/30 min/)).toBeTruthy()
    expect(open.getByText('Needs kettlebell')).toBeTruthy()
    // Its blocks, the server's words.
    expect(open.getByText('Swing')).toBeTruthy()
    fireEvent.click(row('E1'))
    expect(onSelect).toHaveBeenCalledWith('e1')
  })

  it('leads a session with its own icon, a test with a flask', () => {
    mount({ selectedId: 'c1' })
    expect(within(row('C1')).getByRole('img', { name: 'Kettlebell' })).toBeTruthy()
    expect(within(row('T1')).getByLabelText('Test')).toBeTruthy()
    expect(within(row('E1')).getByLabelText('Aerobic Base')).toBeTruthy()
  })

  it('searches names and movements, and says when nothing matches', async () => {
    mount()
    const field = screen.getByRole('searchbox', { name: 'Search sessions' })
    fireEvent.change(field, { target: { value: 'swing' } })
    await screen.findByText('3 of 7')
    expect(rows()).toEqual(['h2', 'c1', 'loose'])
    fireEvent.change(field, { target: { value: 'zzz' } })
    await screen.findByText('No session matches')
    fireEvent.click(screen.getByRole('button', { name: 'Clear' }))
    await screen.findByText('7 sessions')
  })

  it('narrows to a level', () => {
    mount()
    fireEvent.click(screen.getByRole('button', { name: 'Novice' }))
    expect(rows()).not.toContain('h2')
    expect(rows()).toContain('h1')
    expect(screen.getByRole('button', { name: 'Novice' }).getAttribute('aria-pressed')).toBe('true')
  })

  it('narrows to a group, offering only the groups that hold several', () => {
    const rest: DescribedSessionGroup = { ...doc.groups[2], id: 'rest', name: 'Rest', sessions: ['e1', 'c1'] }
    mount({ groups: [doc.groups[1], rest, doc.groups[5]] })
    const pills = within(screen.getByRole('group', { name: 'Group' }))
    expect(pills.queryByRole('button', { name: /Tests/ })).toBeNull()
    fireEvent.click(pills.getByRole('button', { name: /Rest/ }))
    expect(rows()).toEqual(['e1', 'c1'])
    fireEvent.click(pills.getByRole('button', { name: 'All' }))
    expect(rows()).toEqual(['h1', 'h2', 'e1', 'c1', 't1'])
  })

  it('moves down and up the list with the arrow keys', () => {
    const onSelect = mount({ selectedId: 'h1' })
    fireEvent.keyDown(row('H1'), { key: 'ArrowDown' })
    expect(onSelect).toHaveBeenLastCalledWith('h2')
    fireEvent.keyDown(row('H1'), { key: 'ArrowUp' })
    expect(onSelect).toHaveBeenLastCalledWith('w1')
  })

  it("puts a caller's fields and footer in the open session", () => {
    mount({
      selectedId: 'h1',
      editing: { name: (s) => <input aria-label="Session name" defaultValue={s.name} />, note: (s) => <em>note of {s.id}</em> },
      detailFooter: (s) => <a href={`#${s.id}`}>Open as an archetype</a>,
    })
    const open = within(detail())
    expect(open.getByRole('textbox', { name: 'Session name' })).toHaveProperty('value', 'H1')
    expect(open.getByText('note of h1')).toBeTruthy()
    expect(open.getByRole('link', { name: 'Open as an archetype' }).getAttribute('href')).toBe('#h1')
  })

  it("says a session's own note", () => {
    mount({ selectedId: 'h1' })
    expect(within(detail()).getByText('Five heavy sets.')).toBeTruthy()
  })
})

describe('SessionBrowser, on a narrow screen', () => {
  beforeEach(() => screenIs(false))

  it('shows the list alone until a session is picked', () => {
    const onSelect = mount()
    expect(rows()).toHaveLength(7)
    expect(screen.queryByRole('article')).toBeNull()
    fireEvent.click(row('H2'))
    expect(onSelect).toHaveBeenCalledWith('h2')
  })

  it('opens the session in a sheet, and closing it lets the session go', () => {
    const onSelect = mount({ selectedId: 'h2' })
    const sheet = within(screen.getByRole('dialog'))
    expect(sheet.getByRole('heading', { name: 'H2', level: 4 })).toBeTruthy()
    fireEvent.click(sheet.getByRole('button', { name: 'Close' }))
    expect(onSelect).toHaveBeenCalledWith(null)
  })
})
