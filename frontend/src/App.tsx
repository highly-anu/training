import { useEffect } from 'react'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
import { ThemeProvider } from 'next-themes'
import { MotionConfig } from 'framer-motion'
import { RootLayout } from '@/components/layout/RootLayout'
import { Dashboard } from '@/pages/Dashboard'
import { ProgramBuilder } from '@/pages/ProgramBuilder'
import { ProgramView } from '@/pages/ProgramView'
import { ProgramHistoryDetail } from '@/pages/ProgramHistoryDetail'
import { SessionDetail } from '@/pages/SessionDetail'
import { ProfileBenchmarks } from '@/pages/ProfileBenchmarks'
import { Settings } from '@/pages/Settings'
import { Explore } from '@/pages/Explore'
import { Log } from '@/pages/Log'
import { WorkoutDetail } from '@/pages/WorkoutDetail'
import { WorkoutAnalytics } from '@/pages/WorkoutAnalytics'
import { DevLab } from '@/pages/DevLab'
import { LoginPage } from '@/pages/LoginPage'
import { NotFound } from '@/pages/NotFound'
import { PairDevice } from '@/pages/PairDevice'
import { LegacyRedirect } from '@/components/layout/LegacyRedirect'
import { HealthDataProvider } from '@/components/HealthDataProvider'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { DEVLAB_ENABLED } from '@/lib/featureFlags'
import { useAuthStore } from '@/store/authStore'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

function AuthInit({ children }: { children: React.ReactNode }) {
  const init = useAuthStore((s) => s.init)
  useEffect(() => {
    const unsub = init()
    return unsub
  }, [init])
  return <>{children}</>
}

export default function App() {
  return (
    <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false} themes={['light', 'dark', 'military', 'zen']}>
      {/* reducedMotion="user" honours prefers-reduced-motion: transform/layout
          animations (x, y, scale, rotate, height) are dropped, while opacity and
          colour transitions still play. Page transitions degrade to clean
          cross-fades and feedback survives. See docs/frontend-design.md §9.10. */}
      <MotionConfig reducedMotion="user">
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            <AuthInit>
              <HealthDataProvider>
                <Routes>
                  <Route path="/login" element={<LoginPage />} />
                  <Route element={
                    <ProtectedRoute>
                      <RootLayout />
                    </ProtectedRoute>
                  }>
                    {/* Train */}
                    <Route index element={<Dashboard />} />
                    <Route path="program" element={<ProgramView />} />
                    {/* The builder is a flow under Program, not a destination. */}
                    <Route path="program/new" element={<ProgramBuilder />} />
                    {/* Before the :week/:day route, or "history" is read as a week. */}
                    <Route path="program/history" element={<LegacyRedirect to="/program" params={{ tab: 'history' }} />} />
                    <Route path="program/history/:versionId" element={<ProgramHistoryDetail />} />
                    <Route path="program/:week/:day" element={<SessionDetail />} />
                    <Route path="log" element={<Log />} />
                    <Route path="log/:workoutId" element={<WorkoutDetail />} />
                    {/* Insight */}
                    <Route path="analytics" element={<WorkoutAnalytics />} />
                    {/* Library */}
                    <Route path="explore" element={<Explore />} />
                    {/* You */}
                    <Route path="profile" element={<ProfileBenchmarks />} />
                    <Route path="settings" element={<Settings />} />
                    {/* The watch's pairing QR: <web>/pair?code=… */}
                    <Route path="pair" element={<PairDevice />} />
                    {/* Dev */}
                    {DEVLAB_ENABLED && <Route path="dev" element={<DevLab />} />}
                    {/* Old addresses. Query and router state survive the hop. */}
                    <Route path="builder" element={<LegacyRedirect to="/program/new" />} />
                    <Route path="import" element={<LegacyRedirect to="/log" />} />
                    <Route path="import/:workoutId" element={<LegacyRedirect to={(p) => `/log/${encodeURIComponent(p.workoutId ?? '')}`} />} />
                    <Route path="bio" element={<LegacyRedirect to="/analytics" params={{ tab: 'recovery' }} />} />
                    <Route path="exercises" element={<LegacyRedirect to="/explore" params={{ topic: 'exercises' }} />} />
                    <Route path="philosophies" element={<LegacyRedirect to="/explore" params={{ topic: 'philosophies' }} />} />
                    <Route path="*" element={<NotFound />} />
                  </Route>
                </Routes>
              </HealthDataProvider>
            </AuthInit>
          </BrowserRouter>
          <ReactQueryDevtools initialIsOpen={false} />
        </QueryClientProvider>
      </MotionConfig>
    </ThemeProvider>
  )
}
