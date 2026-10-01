import { useEffect } from 'react'
import { fetchHealthSnapshot, fetchMatchSuggestions } from '@/api/health'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { parseSessionKey } from '@/lib/sessionKeys'
import { useAuthStore } from '@/store/authStore'

/**
 * Hydrates all Zustand stores from the server on login / user change.
 * Renders nothing — purely a side-effect component.
 */
export function HealthDataProvider({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  const initBio = useBioStore((s) => s.init)
  const mergeServerSuggestions = useBioStore((s) => s.mergeServerSuggestions)
  const initPerformanceLogs = useProfileStore((s) => s.initPerformanceLogs)
  const initSessionLogs = useProfileStore((s) => s.initSessionLogs)
  const loadProfile = useProfileStore((s) => s.loadFromServer)
  const loadProgram = useProgramStore((s) => s.loadFromServer)

  useEffect(() => {
    if (!user) return

    // Profile and program load in parallel
    loadProfile()
    // Pass the account id so the store can tell a re-load from an account
    // switch — nothing else clears it when the user changes.
    loadProgram(user.id)

    // Health snapshot (workouts, bio, session logs, matches)
    fetchHealthSnapshot()
      .then((snapshot) => {
        initBio(snapshot)
        initPerformanceLogs(snapshot.performanceLogs)
        // Derive completion flags from per-session keys ("weekN-Day-si" → sessionLogs["weekN-Day"][si])
        const completionFlags: Record<string, boolean[]> = {}
        for (const [key, log] of Object.entries(snapshot.sessionLogs)) {
          if (!log.completedAt) continue
          const parsed = parseSessionKey(key)
          if (parsed && parsed.sessionIndex != null) {
            if (!completionFlags[parsed.dayKey]) completionFlags[parsed.dayKey] = []
            completionFlags[parsed.dayKey][parsed.sessionIndex] = true
          } else {
            // Legacy day-level key — restore at index 0
            completionFlags[key] = [true]
          }
        }
        initSessionLogs(completionFlags)

        // Weak matches the server-side importers (Garmin webhook, iOS relay)
        // could not confirm alone. Merged after the snapshot so each one can
        // be paired with its workout; shown on Home and under Import.
        return fetchMatchSuggestions()
          .then((suggestions) => mergeServerSuggestions(suggestions))
          .catch(() => {})
      })
      .catch(() => {
        // Backend not running — stores stay empty, app continues
      })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id])

  return <>{children}</>
}
