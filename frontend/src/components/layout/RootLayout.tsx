import { useLocation, useOutlet } from 'react-router-dom'
import { AnimatePresence } from 'framer-motion'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'
import { ProgramSaveBanner } from './ProgramSaveBanner'
import { RouteErrorBoundary } from './RouteErrorBoundary'
import { useUiStore } from '@/store/uiStore'
import { cn } from '@/lib/utils'

export function RootLayout() {
  const sidebarOpen = useUiStore((s) => s.sidebarOpen)
  // The outlet is keyed by path, so the page leaving runs its exit before the
  // next one enters (un-keyed, AnimatePresence never saw a child leave). The
  // query is not part of the key: `?tab=` changes a page, it does not replace it.
  const { pathname } = useLocation()
  const outlet = useOutlet()

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      {/* Desktop Sidebar */}
      <div
        className={cn(
          'hidden md:flex flex-col transition-[width] duration-(--motion-base)',
          sidebarOpen ? 'w-56' : 'w-0 overflow-hidden'
        )}
      >
        <Sidebar />
      </div>

      {/* Mobile Sidebar Overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-40 md:hidden"
          onClick={() => useUiStore.getState().setSidebarOpen(false)}
        >
          <div className="absolute inset-0 bg-background/80 backdrop-blur-sm" />
          <div className="absolute left-0 top-0 h-full w-56 z-50">
            <Sidebar />
          </div>
        </div>
      )}

      {/* Main content */}
      <div className="flex flex-1 flex-col overflow-hidden">
        <TopBar />
        <ProgramSaveBanner />
        <main className="flex-1 overflow-hidden flex flex-col">
          <AnimatePresence mode="wait">
            <div key={pathname} className="contents">
              <RouteErrorBoundary resetKey={pathname}>{outlet}</RouteErrorBoundary>
            </div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  )
}
