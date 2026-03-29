import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import type { ImportedWorkout } from './types'

export interface StravaAthlete {
  id: string
  name: string
  profile?: string | null
}

export interface StravaStatus {
  connected: boolean
  configured: boolean
  athlete?: StravaAthlete
  last_sync_at?: string | null
}

export interface StravaSyncResult {
  activities: ImportedWorkout[]
  count: number
}

export function useStravaStatus() {
  return useQuery<StravaStatus>({
    queryKey: ['oauth', 'strava', 'status'],
    queryFn: () => apiClient.get('/oauth/strava/status') as Promise<StravaStatus>,
    staleTime: 30_000,
    retry: false, // don't retry on error (API server may be down)
  })
}

export function useStravaAuthorize() {
  return useMutation<string, Error>({
    mutationFn: async () => {
      const data = (await (apiClient.get('/oauth/strava/authorize') as Promise<{ auth_url: string }>))
      return data.auth_url
    },
    onSuccess: (authUrl) => {
      window.location.href = authUrl
    },
  })
}

export function useStravaSyncMutation() {
  const queryClient = useQueryClient()
  return useMutation<StravaSyncResult, Error, { since_timestamp?: number }>({
    mutationFn: (body) =>
      apiClient.post('/oauth/strava/sync', body) as Promise<StravaSyncResult>,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['oauth', 'strava', 'status'] })
    },
  })
}

export function useStravaDisconnect() {
  const queryClient = useQueryClient()
  return useMutation<unknown, Error>({
    mutationFn: () => apiClient.delete('/oauth/strava/disconnect') as Promise<unknown>,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['oauth', 'strava', 'status'] })
    },
  })
}
