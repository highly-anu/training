import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import type { PairedDevice } from './types'

/**
 * Connect IQ watch pairing. The watch mints a code with no account, shows it,
 * and polls; the signed-in athlete claims the code here, which binds the
 * watch's token to the account. Revoking forgets the token.
 */
const DEVICES_KEY = ['devices'] as const

export function useDevices() {
  return useQuery<PairedDevice[]>({
    queryKey: DEVICES_KEY,
    queryFn: () => apiClient.get('/devices') as unknown as Promise<PairedDevice[]>,
    staleTime: 30_000,
    retry: false,
  })
}

export function useClaimDevice() {
  const qc = useQueryClient()
  return useMutation<{ claimed: boolean }, Error, string>({
    mutationFn: (code) => apiClient.post('/devices/claim', { code: code.trim().toUpperCase() }) as unknown as Promise<{ claimed: boolean }>,
    onSuccess: () => { void qc.invalidateQueries({ queryKey: DEVICES_KEY }) },
  })
}

export function useRevokeDevice() {
  const qc = useQueryClient()
  return useMutation<{ revoked: boolean }, Error, string>({
    mutationFn: (token) => apiClient.delete(`/devices/${encodeURIComponent(token)}`) as unknown as Promise<{ revoked: boolean }>,
    onSuccess: () => { void qc.invalidateQueries({ queryKey: DEVICES_KEY }) },
  })
}
