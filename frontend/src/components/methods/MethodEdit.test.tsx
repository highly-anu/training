// @vitest-environment jsdom
/**
 * A method's words edited where they are read: read-only without the page's
 * Edit switch, a field in place with it, saved at once through PATCH.
 */
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), delete: vi.fn(), put: vi.fn(), patch: vi.fn() }))
vi.mock('@/api/client', () => ({ apiClient: api }))

import { EditableText, MethodEditProvider } from './MethodEdit'
import { useProgramStore } from '@/store/programStore'

beforeEach(() => vi.clearAllMocks())
afterEach(cleanup)

function mount(id: string | null, node: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(<QueryClientProvider client={client}><MethodEditProvider id={id}>{node}</MethodEditProvider></QueryClientProvider>)
}

const name = (
  <EditableText value="Heavy day" label="Session name" edits={(n) => ({ sessions: { s1: { name: n } } })} />
)

describe('EditableText', () => {
  it('is only its text when the page is not being edited', () => {
    mount(null, name)
    expect(screen.getByText('Heavy day')).toBeTruthy()
    expect(screen.queryByRole('button')).toBeNull()
  })

  it('opens a field in place and saves the edit at once', async () => {
    api.patch.mockResolvedValue({ id: 'm1', name: 'M', revision: 2, changed: ['a.yaml'], programRenamed: false })
    mount('m1', name)
    fireEvent.click(screen.getByRole('button', { name: 'Edit session name' }))
    const field = screen.getByRole('textbox', { name: 'Session name' })
    expect(field).toHaveProperty('value', 'Heavy day')
    fireEvent.change(field, { target: { value: ' Stone day ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(api.patch).toHaveBeenCalledWith('/methods/m1', { sessions: { s1: { name: 'Stone day' } } }))
    await waitFor(() => expect(screen.queryByRole('textbox')).toBeNull())
  })

  it('saves nothing for the same text, an empty name or Cancel', () => {
    mount('m1', name)
    fireEvent.click(screen.getByRole('button', { name: 'Edit session name' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(screen.queryByRole('textbox')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Edit session name' }))
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '  ' } })
    expect(screen.getByRole('button', { name: 'Save' })).toHaveProperty('disabled', true)
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(api.patch).not.toHaveBeenCalled()
    expect(screen.getByText('Heavy day')).toBeTruthy()
  })

  it('lets an optional note be added, and emptied', async () => {
    api.patch.mockResolvedValue({ id: 'm1', name: 'M', revision: 2, changed: [], programRenamed: false })
    mount('m1', <EditableText value={null} label="Session notes" multiline placeholder="Add a note"
      edits={(notes) => ({ sessions: { s1: { notes } } })} />)
    expect(screen.getByText('Add a note')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Edit session notes' }))
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Go slow.' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(api.patch).toHaveBeenCalledWith('/methods/m1', { sessions: { s1: { notes: 'Go slow.' } } }))
  })

  it("says the server's reason when the edit is refused, and keeps the field", async () => {
    api.patch.mockRejectedValue(Object.assign(new Error('x'), {
      status: 422, body: { problems: [{ message: 'session s1: a name is 1 to 80 characters' }] } }))
    mount('m1', name)
    fireEvent.click(screen.getByRole('button', { name: 'Edit session name' }))
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Another' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect((await screen.findByRole('alert')).textContent).toBe('session s1: a name is 1 to 80 characters')
    expect(screen.getByRole('textbox')).toBeTruthy()
  })

  it('reads the program again when its names changed', async () => {
    const load = vi.spyOn(useProgramStore.getState(), 'loadFromServer').mockResolvedValue()
    api.patch.mockResolvedValue({ id: 'm1', name: 'M', revision: 2, changed: ['philosophy.yaml'], programRenamed: true })
    mount('m1', name)
    fireEvent.click(screen.getByRole('button', { name: 'Edit session name' }))
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Another' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(load).toHaveBeenCalled())
  })
})
