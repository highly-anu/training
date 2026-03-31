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
      })
      .catch(() => {
        // Backend not running — stores stay empty, app continues
      })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id])

  return <>{children}</>
}
