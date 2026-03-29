import { useEffect } from 'react'
import { fetchHealthSnapshot } from '@/api/health'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'

/**
 * Hydrates Zustand health stores from the SQLite backend on app startup.
 * Renders nothing — purely a side-effect component.
 */
export function HealthDataProvider({ children }: { children: React.ReactNode }) {
  const initBio = useBioStore((s) => s.init)
  const initPerformanceLogs = useProfileStore((s) => s.initPerformanceLogs)

  useEffect(() => {
    fetchHealthSnapshot()
      .then((snapshot) => {
        initBio(snapshot)
        initPerformanceLogs(snapshot.performanceLogs)
      })
      .catch(() => {
        // Backend not running — stores stay empty, user can still interact
      })
  }, [])

  return <>{children}</>
}
