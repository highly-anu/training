/**
 * API helpers for user-scoped profile and program data.
 * These endpoints are protected by JWT auth on the Flask backend.
 */
import { apiClient } from './client'
import type { CustomInjuryFlag, Day, DaySchedule, EquipmentId, InjuryFlagId, TrainingLevel, GeneratedProgram } from './types'

export interface ServerProfile {
  trainingLevel: TrainingLevel
  equipment: EquipmentId[]
  injuryFlags: InjuryFlagId[]
  customInjuryFlags: CustomInjuryFlag[]
  activeGoalId: string | null
  dateOfBirth: string | null
  weeklySchedule?: Record<Day, DaySchedule> | null
}

export interface ServerProgram {
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

export async function saveUserProgram(program: ServerProgram): Promise<void> {
  try {
    await apiClient.put('/user/program', program)
  } catch {
    // best-effort fire-and-forget
  }
}
