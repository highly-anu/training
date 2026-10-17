import { QueryClient } from '@tanstack/react-query'

/**
 * The app's one query client. A module of its own so code outside the React
 * tree — a store's fire-and-forget save — can refresh what it changed: a
 * session-log save that produced a standard's suggestion refreshes "To
 * confirm" (api/health.saveSessionLog).
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})
