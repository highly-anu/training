import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
import { ThemeProvider } from 'next-themes'
import { RootLayout } from '@/components/layout/RootLayout'
import { Dashboard } from '@/pages/Dashboard'
import { ProgramBuilder } from '@/pages/ProgramBuilder'
import { ProgramView } from '@/pages/ProgramView'
import { SessionDetail } from '@/pages/SessionDetail'
import { ExerciseCatalog } from '@/pages/ExerciseCatalog'
import { ProfileBenchmarks } from '@/pages/ProfileBenchmarks'
import { Philosophies } from '@/pages/Philosophies'
import { WorkoutImport } from '@/pages/WorkoutImport'
import { WorkoutDetail } from '@/pages/WorkoutDetail'
import { BioLog } from '@/pages/BioLog'
import { DevLab } from '@/pages/DevLab'
import { HealthDataProvider } from '@/components/HealthDataProvider'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

export default function App() {
  return (
    <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false} themes={['light', 'dark', 'military', 'zen']}>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <HealthDataProvider>
          <Routes>
            <Route element={<RootLayout />}>
              <Route index element={<Dashboard />} />
              <Route path="builder" element={<ProgramBuilder />} />
              <Route path="program" element={<ProgramView />} />
              <Route path="program/:week/:day" element={<SessionDetail />} />
              <Route path="exercises" element={<ExerciseCatalog />} />
              <Route path="profile" element={<ProfileBenchmarks />} />
              <Route path="philosophies" element={<Philosophies />} />
              <Route path="import" element={<WorkoutImport />} />
              <Route path="import/:workoutId" element={<WorkoutDetail />} />
              <Route path="bio" element={<BioLog />} />
              <Route path="dev" element={<DevLab />} />
            </Route>
          </Routes>
          </HealthDataProvider>
        </BrowserRouter>
        <ReactQueryDevtools initialIsOpen={false} />
      </QueryClientProvider>
    </ThemeProvider>
  )
}
