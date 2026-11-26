// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import type { ReactNode } from 'react'
import recorded from '@/mocks/fixtures/manual-sessions.json'
import exercisesFixture from '@/mocks/fixtures/exercises.json'
import { useSessionBuilderStore } from '@/store/sessionBuilderStore'
import { TipProvider } from '@/components/shared/Tip'
import { SessionBuilderPanel } from './SessionBuilderPanel'

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() }))
vi.mock('@/api/client', () => ({ apiClient: api }))

const EXERCISES = exercisesFixture as unknown as { id: string; name: string }[]
const squat = EXERCISES.find((e) => e.id === 'back_squat')!

function mount(node: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}><MemoryRouter><TipProvider>{node}</TipProvider></MemoryRouter></QueryClientProvider>,
  )
}

beforeEach(() => {
  useSessionBuilderStore.getState().reset()
  api.get.mockImplementation((url: string) => Promise.resolve(
    url === '/exercises' ? EXERCISES : url === '/manual/sessions' ? recorded.list : url === '/modalities' ? [] : {}))
  api.post.mockImplementation((url: string) => Promise.resolve(
    url === '/manual/preview' ? recorded.preview : { session: recorded.list.sessions[0] }))
  api.put.mockResolvedValue({ session: recorded.list.sessions[0] })
  api.delete.mockResolvedValue({ removed: true })
})
afterEach(() => { cleanup(); vi.clearAllMocks() })

const library = () => screen.getByRole('region', { name: 'Exercises' })
const openLibrary = async () => {
  fireEvent.click(await screen.findByRole('button', { name: 'Browse exercises' }))
  return library()
}
/** Type an exercise into a combobox and take the first suggestion with Enter. */
function pick(combo: HTMLElement, text: string) {
  fireEvent.change(combo, { target: { value: text } })
  fireEvent.keyDown(combo, { key: 'Enter' })
}
/** The session's first block, from the field an empty session starts with. */
const start = async (text = 'back squat') => pick(await screen.findByRole('combobox', { name: 'The first exercise' }), text)
/** Open a Radix menu from its button, as the keyboard does. */
const openMenu = (button: HTMLElement) => { button.focus(); fireEvent.keyDown(button, { key: 'Enter' }) }

describe('Dev Lab ▸ Session builder', () => {
  it('starts as a name and one exercise field: no library, parts, notes or Add block', async () => {
    mount(<SessionBuilderPanel />)
    await screen.findByRole('combobox', { name: 'The first exercise' })
    expect(screen.queryByRole('region', { name: 'Exercises' })).toBeNull()
    for (const part of ['Start', 'Main work', 'Finisher', 'Cool-down']) expect(screen.queryByRole('heading', { name: part })).toBeNull()
    expect(screen.queryByLabelText('Notes for the whole session')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Add block' })).toBeNull()
  })

  it('opens the library on demand with the focus in its search, and Escape puts it away', async () => {
    mount(<SessionBuilderPanel />)
    const browse = await screen.findByRole('button', { name: 'Browse exercises' })
    expect(browse.getAttribute('aria-expanded')).toBe('false')
    fireEvent.click(browse)
    const search = screen.getByRole('searchbox', { name: 'Search exercises' })
    expect(document.activeElement).toBe(search)
    expect(browse.getAttribute('aria-expanded')).toBe('true')
    fireEvent.keyDown(search, { key: 'Escape' })
    expect(screen.queryByRole('region', { name: 'Exercises' })).toBeNull()
    expect(document.activeElement).toBe(browse)
  })

  it('narrows the exercises as the search is typed', async () => {
    mount(<SessionBuilderPanel />)
    await openLibrary()
    const search = screen.getByRole('searchbox', { name: 'Search exercises' })
    const before = within(library()).getAllByRole('listitem').length
    fireEvent.change(search, { target: { value: 'back squat' } })
    await waitFor(() => expect(within(library()).getAllByRole('listitem').length).toBeLessThan(before))
    expect(within(library()).getAllByRole('listitem')[0].textContent).toContain(squat.name)
    fireEvent.change(search, { target: { value: 'zzzz' } })
    expect(await within(library()).findByText('No exercise matches.')).toBeTruthy()
  })

  it('walks the library with the arrow keys as one tab stop, and adds with a press', async () => {
    mount(<SessionBuilderPanel />)
    const lib = await openLibrary()
    const search = screen.getByRole('searchbox', { name: 'Search exercises' })
    const cards = () => within(lib).getAllByRole('button', { name: /^Add / })
    expect(cards().filter((c) => c.tabIndex === 0)).toHaveLength(1)
    fireEvent.keyDown(search, { key: 'ArrowDown' })
    expect(document.activeElement).toBe(cards()[0])
    fireEvent.keyDown(cards()[0], { key: 'ArrowDown' })
    expect(document.activeElement).toBe(cards()[1])
    expect(cards()[1].tabIndex).toBe(0)
    expect(cards()[0].tabIndex).toBe(-1)
    fireEvent.keyDown(cards()[1], { key: 'ArrowUp' })
    fireEvent.keyDown(cards()[0], { key: 'ArrowUp' })
    expect(document.activeElement).toBe(search)
    // Enter and Space on a button are its click.
    fireEvent.click(within(lib).getByRole('button', { name: `Add ${squat.name}` }))
    const block = screen.getByRole('article')
    expect(within(block).getByText(squat.name)).toBeTruthy()
    expect((within(block).getByLabelText('Block') as HTMLSelectElement).value).toBe('sets')
    expect((within(block).getByLabelText('Part') as HTMLSelectElement).value).toBe('main')
  })

  it('puts the focus on the new exercise\'s first number, and each number is one tab stop', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    const block = screen.getByRole('article')
    const sets = within(block).getByLabelText('Sets') as HTMLInputElement
    await waitFor(() => expect(document.activeElement).toBe(sets))
    const was = Number(sets.value)
    fireEvent.keyDown(sets, { key: 'ArrowUp' })
    expect(Number((within(block).getByLabelText('Sets') as HTMLInputElement).value)).toBe(was + 1)
    expect((within(block).getByRole('button', { name: 'More: Sets' }) as HTMLButtonElement).tabIndex).toBe(-1)
  })

  it('suggests exercises in a block\'s own field and takes one with Enter', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    const block = screen.getByRole('article')
    fireEvent.change(within(block).getByLabelText('Block'), { target: { value: 'amrap' } })
    expect(within(block).getByText(squat.name)).toBeTruthy()
    const combo = within(block).getByRole('combobox', { name: /Add an exercise to/ })
    fireEvent.change(combo, { target: { value: 'pull' } })
    const options = within(await within(block).findByRole('listbox')).getAllByRole('option')
    expect(options.length).toBeGreaterThan(0)
    const picked = options[0].textContent ?? ''
    fireEvent.keyDown(combo, { key: 'Enter' })
    expect(within(block).getAllByRole('listitem')).toHaveLength(2)
    expect(picked).toContain(within(block).getAllByRole('listitem')[1].querySelector('span')?.textContent ?? '∅')
    // The focus follows to the exercise just added.
    await waitFor(() => expect(within(block).getAllByRole('listitem')[1].contains(document.activeElement)).toBe(true))
  })

  it('offers the next block only once every block has its exercise', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    const add = screen.getByRole('button', { name: 'Add block' })
    openMenu(add)
    fireEvent.click(await screen.findByRole('menuitem', { name: /^AMRAP/ }))
    await waitFor(() => expect(screen.getAllByRole('article')).toHaveLength(2))
    const second = screen.getAllByRole('article')[1]
    const combo = within(second).getByRole('combobox', { name: /Add an exercise to/ })
    await waitFor(() => expect(document.activeElement).toBe(combo))
    expect(screen.queryByRole('button', { name: 'Add block' })).toBeNull()
    pick(combo, 'pull')
    expect(await screen.findByRole('button', { name: 'Add block' })).toBeTruthy()
  })

  it('draws a part\'s heading only once a block is in another part than Main work', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    openMenu(screen.getByRole('button', { name: 'Add block' }))
    fireEvent.click(await screen.findByRole('menuitem', { name: /^Practice/ }))
    await waitFor(() => expect(screen.getAllByRole('article')).toHaveLength(2))
    expect(screen.queryByRole('heading', { name: 'Main work' })).toBeNull()
    const part = within(screen.getAllByRole('article')[1]).getByLabelText('Part')
    fireEvent.change(part, { target: { value: 'prep' } })
    expect(screen.getByRole('heading', { name: 'Start' })).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Main work' })).toBeTruthy()
    expect(screen.queryByRole('heading', { name: 'Finisher' })).toBeNull()
    // The block moved to the top and kept the focus on the choice that moved it.
    const moved = screen.getAllByRole('article')[0]
    expect((within(moved).getByLabelText('Block') as HTMLSelectElement).value).toBe('practice')
    await waitFor(() => expect(document.activeElement).toBe(within(moved).getByLabelText('Part')))
  })

  it('keeps the focus in the builder when a block is deleted', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    openMenu(screen.getByRole('button', { name: /move or delete/ }))
    expect((await screen.findByRole('menuitem', { name: 'Move earlier' })).getAttribute('aria-disabled')).toBe('true')
    fireEvent.click(screen.getByRole('menuitem', { name: 'Delete block' }))
    const first = await screen.findByRole('combobox', { name: 'The first exercise' })
    await waitFor(() => expect(document.activeElement).toBe(first))
  })

  it('shows a note only when it is asked for or already written', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    const block = screen.getByRole('article')
    expect(within(block).queryByLabelText('Note')).toBeNull()
    fireEvent.click(within(block).getByRole('button', { name: 'Add a note' }))
    const note = within(block).getByLabelText('Note')
    await waitFor(() => expect(document.activeElement).toBe(note))
    fireEvent.change(note, { target: { value: 'Slow down' } })
    expect(useSessionBuilderStore.getState().draft.blocks[0].note).toBe('Slow down')
    fireEvent.click(screen.getByRole('button', { name: 'Add a session note' }))
    expect(screen.getByLabelText('Notes for the whole session')).toBeTruthy()
  })

  it('builds and saves a session from the keyboard alone', async () => {
    mount(<SessionBuilderPanel />)
    const name = await screen.findByPlaceholderText('Squat day')
    fireEvent.change(name, { target: { value: 'Heavy day' } })
    fireEvent.keyDown(name, { key: 'Enter' })
    const first = screen.getByRole('combobox', { name: 'The first exercise' })
    await waitFor(() => expect(document.activeElement).toBe(first))
    pick(first, 'back squat')
    await waitFor(() => expect(document.activeElement).toBe(screen.getByLabelText('Sets')))
    fireEvent.keyDown(document.activeElement!, { key: 'Enter', metaKey: true })
    await waitFor(() => expect(api.post.mock.calls.some(([url]) => url === '/manual/sessions')).toBe(true))
    const [, body] = api.post.mock.calls.find(([url]) => url === '/manual/sessions')!
    expect(body.session.name).toBe('Heavy day')
    expect(body.session.blocks[0]).toMatchObject({ kind: 'sets', stage: 'main' })
  })

  it('shows the server\'s reading of the draft and saves it in the wire shape', async () => {
    mount(<SessionBuilderPanel />)
    await start()
    fireEvent.change(screen.getByPlaceholderText('Squat day'), { target: { value: 'Heavy day' } })
    const preview = screen.getByRole('region', { name: 'Preview' })
    await within(preview).findByText(/About \d+ min/)
    expect(within(preview).getByText('Week by week')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Save session' }))
    await waitFor(() => expect(api.post.mock.calls.some(([url]) => url === '/manual/sessions')).toBe(true))
    const [, body] = api.post.mock.calls.find(([url]) => url === '/manual/sessions')!
    expect(body.session.name).toBe('Heavy day')
    expect(body.session.blocks[0]).toMatchObject({ kind: 'sets', stage: 'main' })
    expect(body.session.blocks[0].movements[0].exercise_id).toBe('back_squat')
    expect(JSON.stringify(body)).not.toContain('uid')
    await screen.findByRole('button', { name: 'Save changes' })
  })

  it('says a refused save at the block it names', async () => {
    api.post.mockImplementation((url: string) => (url === '/manual/preview' ? Promise.resolve(recorded.preview)
      : Promise.reject(Object.assign(new Error('x'), { status: 422, body: { error: 'invalid',
        problems: [{ block: 0, movement: 0, field: 'sets', message: 'How many sets?' }] } }))))
    mount(<SessionBuilderPanel />)
    await start()
    fireEvent.click(screen.getByRole('button', { name: 'Save session' }))
    const block = screen.getByRole('article')
    expect(await within(block).findByText('How many sets?')).toBeTruthy()
  })

  it('lists the saved sessions and opens one to edit', async () => {
    mount(<SessionBuilderPanel />)
    const saved = await screen.findByRole('region', { name: 'Saved sessions' })
    const first = recorded.list.sessions[0]
    fireEvent.click(await within(saved).findByRole('button', { name: `Edit ${first.name}` }))
    expect((screen.getByPlaceholderText('Squat day') as HTMLInputElement).value).toBe(first.name)
    expect(screen.getAllByRole('article').length).toBe(first.blocks.length)
    expect(screen.getByRole('button', { name: 'Save changes' })).toBeTruthy()
  })
})
