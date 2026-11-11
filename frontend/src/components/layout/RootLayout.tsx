import { Shortcuts } from './Shortcuts'
import { useLocation, useOutlet } from 'react-router-dom'
import { AnimatePresence } from 'framer-motion'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'
import { ProgramSaveBanner } from './ProgramSaveBanner'
import { RouteErrorBoundary } from './RouteErrorBoundary'
import { useUiStore } from '@/store/uiStore'
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet'

export function RootLayout() {
  const mobileNavOpen = useUiStore((s) => s.mobileNavOpen)
  const setMobileNavOpen = useUiStore((s) => s.setMobileNavOpen)
  // The outlet is keyed by path, so the page leaving runs its exit before the
  // next one enters (un-keyed, AnimatePresence never saw a child leave). The
  // query is not part of the key: `?tab=` changes a page, it does not replace it.
  const { pathname } = useLocation()
  const outlet = useOutlet()

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      {/* Desktop Sidebar */}
      <div className="hidden w-56 flex-col md:flex">
        <Sidebar />
      </div>

      {/* Under md the same sidebar is a drawer: closed on load, slides in from
          the menu button, holds focus, closes on Escape, the scrim and a link. */}
      <Sheet open={mobileNavOpen} onOpenChange={setMobileNavOpen}>
        <SheetContent side="left" className="w-56 p-0 md:hidden">
          <SheetTitle className="sr-only">Navigation</SheetTitle>
          <SheetDescription className="sr-only">The app's sections</SheetDescription>
          <Sidebar onNavigate={() => setMobileNavOpen(false)} />
        </SheetContent>
      </Sheet>

      {/* Main content */}
      <div className="flex flex-1 flex-col overflow-hidden">
        <TopBar />
        <ProgramSaveBanner />
        <Shortcuts />
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
