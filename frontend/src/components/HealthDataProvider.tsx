import { useEffect } from 'react'
import { fetchHealthSnapshot } from '@/api/health'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { useAuthStore } from '@/store/authStore'

/**
 * Hydrates all Zustand stores from the server on login / user change.
 * Renders nothing — purely a side-effect component.
 */
export function HealthDataProvider({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  const initBio = useBioStore((s) => s.init)
  const initPerformanceLogs = useProfileStore((s) => s.initPerformanceLogs)
  const initSessionLogs = useProfileStore((s) => s.initSessionLogs)
  const loadProfile = useProfileStore((s) => s.loadFromServer)
  const loadProgram = useProgramStore((s) => s.loadFromServer)

  useEffect(() => {
    if (!user) return

    // Profile and program load in parallel
    loadProfile()
    loadProgram()

    // Health snapshot (workouts, bio, session logs, matches)
    fetchHealthSnapshot()
      .then((snapshot) => {
        initBio(snapshot)
        initPerformanceLogs(snapshot.performanceLogs)
        // Derive completion flags from per-session keys ("weekN-Day-si" → sessionLogs["weekN-Day"][si])
        const completionFlags: Record<string, boolean[]> = {}
        for (const [key, log] of Object.entries(snapshot.sessionLogs)) {
          if (!log.completedAt) continue
          const match = key.match(/^(.+)-(\d+)$/)
          if (match) {
            const dayKey = match[1]
            const idx = parseInt(match[2], 10)
            if (!completionFlags[dayKey]) completionFlags[dayKey] = []
            completionFlags[dayKey][idx] = true
          } else {
            // Legacy day-level key — restore at index 0
            completionFlags[key] = [true]
          }
        }
        initSessionLogs(completionFlags)
      })
      .catch(() => {
        // Backend not running — stores stay empty, app continues
      })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id])

  return <>{children}</>
}
