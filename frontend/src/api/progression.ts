import { format } from 'date-fns'
import { apiClient } from './client'
import type {
  ProgressionReview,
  ExerciseHistoryResponse,
  ProgressionReviewSummary,
} from '@/api/types'

const BASE = '/progression'

export async function fetchProgressionReview(
  period: 'weekly' | 'biweekly' = 'weekly',
): Promise<ProgressionReview> {
  return apiClient.get(`${BASE}/review?period=${period}`) as unknown as Promise<ProgressionReview>
}

export async function fetchExerciseHistory(
  exerciseId?: string,
): Promise<ExerciseHistoryResponse> {
  // The athlete's own date decides what is "so far"; the server's is UTC.
  const params = new URLSearchParams({ today: format(new Date(), 'yyyy-MM-dd') })
  if (exerciseId) params.set('exercise_id', exerciseId)
  const qs = `?${params.toString()}`
  return apiClient.get(`${BASE}/exercises${qs}`) as unknown as Promise<ExerciseHistoryResponse>
}

export async function fetchProgressionHistory(): Promise<ProgressionReviewSummary[]> {
  return apiClient.get(`${BASE}/history`) as unknown as Promise<ProgressionReviewSummary[]>
}
