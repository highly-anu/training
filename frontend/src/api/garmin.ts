/**
 * Garmin Connect hooks — the same shape as `oauth.ts` (Strava), with one
 * deliberate difference: there is no "sync now".
 *
 * Garmin is push-driven. Once connected, activities arrive at the backend's
 * webhook on their own, so the only manual action worth offering is asking
 * Garmin to replay history — which it also delivers through that same webhook.
 */
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import type { GarminStatus } from './types'

export interface GarminBackfillResult {
  requestedWindows: number
  days: number
  errors: string[]
}

const GARMIN_STATUS_KEY = ['oauth', 'garmin', 'status']

export function useGarminStatus() {
  return useQuery<GarminStatus>({
    queryKey: GARMIN_STATUS_KEY,
    queryFn: () => apiClient.get('/oauth/garmin/status') as Promise<GarminStatus>,
    staleTime: 30_000,
    retry: false, // the API server may simply be down; don't hammer it
  })
}

export function useGarminAuthorize() {
  return useMutation<string, Error>({
    mutationFn: async () => {
      const data = await (apiClient.get('/oauth/garmin/authorize') as Promise<{ auth_url: string }>)
      return data.auth_url
    },
    onSuccess: (authUrl) => {
      window.location.href = authUrl
    },
  })
}

export function useGarminDisconnect() {
  const queryClient = useQueryClient()
  return useMutation<unknown, Error>({
    mutationFn: () => apiClient.delete('/oauth/garmin/disconnect') as Promise<unknown>,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: GARMIN_STATUS_KEY })
    },
  })
}

/**
 * Ask Garmin to resend history. It answers immediately and delivers the
 * activities to the webhook over the following minutes, so a success here
 * means "requested", not "imported".
 */
export function useGarminBackfill() {
  const queryClient = useQueryClient()
  return useMutation<GarminBackfillResult, Error, { days?: number }>({
    mutationFn: (body) =>
      apiClient.post('/oauth/garmin/backfill', body) as Promise<GarminBackfillResult>,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: GARMIN_STATUS_KEY })
    },
  })
}
