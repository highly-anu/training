import { LoadingState } from '@/components/shared/states'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  const isLoading = useAuthStore((s) => s.isLoading)
  const location = useLocation()

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <LoadingState shape="lines" count={3} label="Signing in" className="w-48" />
      </div>
    )
  }

  if (!user) {
    // Hand the login page where the athlete was going, so a scanned watch QR
    // (/pair?code=…) is still there after signing in.
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  }

  return <>{children}</>
}
