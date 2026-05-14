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
  const qs = exerciseId ? `?exercise_id=${encodeURIComponent(exerciseId)}` : ''
  return apiClient.get(`${BASE}/exercises${qs}`) as unknown as Promise<ExerciseHistoryResponse>
}

export async function fetchProgressionHistory(): Promise<ProgressionReviewSummary[]> {
  return apiClient.get(`${BASE}/history`) as unknown as Promise<ProgressionReviewSummary[]>
}
