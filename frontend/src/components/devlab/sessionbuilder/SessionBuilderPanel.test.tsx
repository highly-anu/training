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

describe('Dev Lab ▸ Session builder', () => {
  it('narrows the exercises as the search is typed', async () => {
    mount(<SessionBuilderPanel />)
    const search = await screen.findByRole('searchbox', { name: 'Search exercises' })
    const before = within(library()).getAllByRole('listitem').length
    fireEvent.change(search, { target: { value: 'back squat' } })
    await waitFor(() => expect(within(library()).getAllByRole('listitem').length).toBeLessThan(before))
    expect(within(library()).getAllByRole('listitem')[0].textContent).toContain(squat.name)
    fireEvent.change(search, { target: { value: 'zzzz' } })
    expect(await within(library()).findByText('No exercise matches.')).toBeTruthy()
  })

  it('adds an exercise as a block of its kind, in Main work', async () => {
    mount(<SessionBuilderPanel />)
    fireEvent.click(await screen.findByRole('button', { name: `Add ${squat.name}` }))
    const main = screen.getByRole('region', { name: 'Main work' })
    const block = within(main).getByRole('article')
    expect(within(block).getByText(squat.name)).toBeTruthy()
    expect((within(block).getByLabelText('Block') as HTMLSelectElement).value).toBe('sets')
    expect((within(block).getByLabelText('Sets') as HTMLInputElement).value).not.toBe('')
  })

  it('suggests exercises in a block\'s own field and takes one with Enter', async () => {
    mount(<SessionBuilderPanel />)
    fireEvent.click(await screen.findByRole('button', { name: `Add ${squat.name}` }))
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
  })

  it('shows the server\'s reading of the draft and saves it in the wire shape', async () => {
    mount(<SessionBuilderPanel />)
    fireEvent.click(await screen.findByRole('button', { name: `Add ${squat.name}` }))
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
    fireEvent.click(await screen.findByRole('button', { name: `Add ${squat.name}` }))
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
