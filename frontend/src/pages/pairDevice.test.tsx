// @vitest-environment jsdom
/**
 * The watch's pairing QR is a link: <web>/pair?code=ABC234.
 *
 * It used to land on NotFound (there was no /pair route), and a signed-out
 * phone lost the code anyway: ProtectedRoute bounced to /login and the login
 * page always went to "/". The link now survives sign-in, and the claim waits
 * for a tap, because claiming on load would let any printed QR bind its watch
 * to whoever scanned it.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useAuthStore } from '@/store/authStore'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { PairDevice } from './PairDevice'

const postMock = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue([]),
    post: (...args: unknown[]) => postMock(...args),
    put: vi.fn(),
    delete: vi.fn(),
  },
}))

function LoginProbe() {
  const loc = useLocation()
  return <p>login, then {String((loc.state as { from?: string } | null)?.from)}</p>
}

function mount(path: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/login" element={<LoginProbe />} />
          <Route path="/pair" element={<ProtectedRoute><PairDevice /></ProtectedRoute>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  postMock.mockReset()
  useAuthStore.setState({ user: { id: 'u1' } as never, isLoading: false })
})
afterEach(cleanup)

describe('/pair', () => {
  it('keeps the code through a sign-in', () => {
    useAuthStore.setState({ user: null, isLoading: false })
    mount('/pair?code=abc234')
    expect(screen.getByText('login, then /pair?code=abc234')).toBeInTheDocument()
  })

  it('shows the code and claims it only on a tap', async () => {
    postMock.mockResolvedValue({ claimed: true })
    mount('/pair?code=abc234')
    expect(screen.getByLabelText('Pairing code')).toHaveTextContent('ABC234')
    expect(postMock).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'Pair this watch' }))
    await waitFor(() => expect(postMock).toHaveBeenCalledWith('/devices/claim', { code: 'ABC234' }))
    expect(await screen.findByText('Paired')).toBeInTheDocument()
  })

  it('says why when the code has expired', async () => {
    postMock.mockRejectedValue(new Error('Invalid or expired code'))
    mount('/pair?code=ABC234')
    fireEvent.click(screen.getByRole('button', { name: 'Pair this watch' }))
    expect(await screen.findByText(/Invalid or expired code\. Codes last ten minutes/)).toBeInTheDocument()
  })

  it('offers Connections for a link without a valid code', () => {
    mount('/pair?code=nope')
    expect(screen.queryByRole('button', { name: 'Pair this watch' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open Connections' })).toHaveAttribute('href', '/settings?tab=connections')
  })
})
