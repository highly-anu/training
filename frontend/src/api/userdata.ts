/**
 * API helpers for user-scoped profile and program data.
 * These endpoints are protected by JWT auth on the Flask backend.
 */
import { apiClient } from './client'
import type { CustomInjuryFlag, Day, DaySchedule, EquipmentId, HRConfig, InjuryFlagId, TrainingLevel, GeneratedProgram, WeeklyLoad, PMCEntry } from './types'

export interface ServerProfile {
  trainingLevel: TrainingLevel
  equipment: EquipmentId[]
  injuryFlags: InjuryFlagId[]
  customInjuryFlags: CustomInjuryFlag[]
  activeGoalId: string | null
  dateOfBirth: string | null
  weeklySchedule?: Record<Day, DaySchedule> | null
  hrConfig?: HRConfig | null
}

export interface ServerProgram {
  /** Opaque revision of the copy this was read from, echoed back on save so the
   *  server can reject a write based on a stale read (409) rather than letting
   *  it overwrite a program generated elsewhere since. */
  revision?: string | null
  /** Revision this edit was based on (sent, not stored). */
  baseRevision?: string | null
  currentProgram: GeneratedProgram | null
  programStartDate: string | null
  eventDate: string | null
  sourceGoalIds: string[]
  sourceGoalWeights: Record<string, number>
}

export async function fetchProfile(): Promise<ServerProfile | null> {
  try {
    return await (apiClient.get('/profile') as unknown as Promise<ServerProfile>)
  } catch {
    return null
  }
}

export async function saveProfile(profile: Partial<ServerProfile>): Promise<void> {
  try {
    await apiClient.put('/profile', profile)
  } catch {
    // best-effort fire-and-forget
  }
}

export async function fetchUserProgram(): Promise<ServerProgram | null> {
  try {
    return await (apiClient.get('/user/program') as unknown as Promise<ServerProgram | null>)
  } catch {
    return null
  }
}

/** Last program-save failure, or null when the most recent save succeeded. */
export let lastProgramSaveError: string | null = null

/**
 * Persist the program to the server.
 *
 * This used to swallow every error. A failed PUT then left the browser showing a
 * program the server had never received, while the phone and watch served the
 * previous one — three divergent states and no signal anywhere. One retry covers
 * a transient network blip; anything else is recorded and logged so it is
 * visible rather than silent.
 */
export async function saveUserProgram(program: ServerProgram): Promise<boolean> {
  const body = { ...program, baseRevision: program.revision ?? null }
  delete (body as { revision?: unknown }).revision

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = (await apiClient.put('/user/program', body)) as unknown as {
        revision?: string
      }
      // Track the new revision so the next save is based on it.
      program.revision = res?.revision ?? program.revision
      lastProgramSaveError = null
      return true
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      // stale_revision: the stored program moved on. Retrying would clobber it.
      if (message.includes('stale_revision')) {
        lastProgramSaveError = 'stale_revision'
        console.warn('[program] save rejected — the server has a newer program. Reload to pick it up.')
        return false
      }
      lastProgramSaveError = message
      if (attempt === 0) {
        await new Promise((r) => setTimeout(r, 800))
        continue
      }
      console.error('[program] save failed — the server still has the previous program:', message)
      return false
    }
  }
  return false
}

export async function fetchWeeklyLoad(): Promise<WeeklyLoad[]> {
  try {
    return await (apiClient.get('/health/load/weekly') as unknown as Promise<WeeklyLoad[]>)
  } catch {
    return []
  }
}

export async function fetchPMC(): Promise<PMCEntry[]> {
  try {
    return await (apiClient.get('/health/load/pmc') as unknown as Promise<PMCEntry[]>)
  } catch {
    return []
  }
}
