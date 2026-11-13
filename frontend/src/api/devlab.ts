import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { ModelMap, PortabilityReport } from '@/api/types'

/**
 * What each package brings in its own folder and what it still needs outside
 * it, with the gaps no package can close yet (src/portability.py). Local dev
 * or AUTHORING_ENABLED only; package files change only between deploys.
 */
export function usePortability() {
  return useQuery({
    queryKey: queryKeys.dev.portability,
    queryFn: () => apiClient.get('/dev/portability') as unknown as Promise<PortabilityReport>,
    staleTime: Infinity,
    retry: false,
  })
}

/**
 * How the model's parts act on each other, each interaction anchored in the
 * code, and which engine each track runs on (src/model_map.py,
 * tools/model_map.json). Local dev or AUTHORING_ENABLED only.
 */
export function useModelMap() {
  return useQuery({
    queryKey: queryKeys.dev.modelMap,
    queryFn: () => apiClient.get('/dev/model-map') as unknown as Promise<ModelMap>,
    staleTime: Infinity,
    retry: false,
  })
}
