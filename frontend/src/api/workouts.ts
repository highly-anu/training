import { apiClient } from './client'
import type { ImportedWorkout } from './types'

/**
 * Server-side parsing of workout exports. The import page used to build its
 * own `fetch` with a hand-made Supabase header; this goes through the shared
 * client (JWT interceptor, unwrapped responses, normalised errors).
 */

// Axios replaces the client's JSON content type when the body is FormData so
// the browser can set the multipart boundary; uploads also get no timeout.
const UPLOAD = { headers: { 'Content-Type': 'multipart/form-data' }, timeout: 0 }

function formFor(file: File): FormData {
  const fd = new FormData()
  fd.append('workout_file', file)
  return fd
}

/** `.fit`, and exports small enough to parse in one request. */
export async function parseWorkoutFile(file: File): Promise<ImportedWorkout[]> {
  return apiClient.post('/workouts/parse', formFor(file), UPLOAD) as unknown as Promise<ImportedWorkout[]>
}

/** Large Apple Health exports: queue the parse and poll it. */
export async function startAsyncParse(file: File): Promise<string> {
  const res = await (apiClient.post('/workouts/parse/async', formFor(file), UPLOAD) as unknown as Promise<{ jobId: string }>)
  return res.jobId
}

export interface ParseJobStatus {
  status: 'queued' | 'running' | 'done' | 'error' | string
  progress?: number
  stage?: string
  error?: string
  result?: ImportedWorkout[]
}

export async function pollParseJob(
  jobId: string,
  onProgress: (progress: number, stage: string) => void,
): Promise<ImportedWorkout[]> {
  const MAX_POLLS = 600  // 10 minutes at 1s intervals
  for (let i = 0; i < MAX_POLLS; i++) {
    await new Promise<void>((r) => setTimeout(r, 1000))
    const status = await (apiClient.get(`/workouts/parse/status/${encodeURIComponent(jobId)}`) as unknown as Promise<ParseJobStatus>)
    onProgress(status.progress ?? 0, status.stage ?? 'Processing…')
    if (status.status === 'done') return status.result ?? []
    if (status.status === 'error') throw new Error(status.error ?? 'Parse failed')
  }
  throw new Error('Import timed out after 10 minutes')
}
