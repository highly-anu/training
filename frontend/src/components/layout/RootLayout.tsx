import { Shortcuts } from './Shortcuts'
import { useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { UNSAFE_LocationContext as LocationContext, useLocation, useOutlet } from 'react-router-dom'
import { AnimatePresence, useIsPresent } from 'framer-motion'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'
import { ProgramSaveBanner } from './ProgramSaveBanner'
import { RouteErrorBoundary } from './RouteErrorBoundary'
import { useUiStore } from '@/store/uiStore'
import { useModalities } from '@/api/modalities'
import { modalityVocabularyVersion, registerModalities } from '@/lib/modalityColors'
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet'

/**
 * A page on its way out keeps the location it was shown at. Without it the
 * leaving page read the next page's path and query while it faded, and drew
 * one frame of the wrong tab or an empty detail.
 */
function HeldLocation({ children }: { children: ReactNode }) {
  const present = useIsPresent()
  const current = useContext(LocationContext)
  const [held, setHeld] = useState(current)
  if (present && held !== current) setHeld(current)
  return <LocationContext.Provider value={present ? current : held}>{children}</LocationContext.Provider>
}

export function RootLayout() {
  const mobileNavOpen = useUiStore((s) => s.mobileNavOpen)
  const setMobileNavOpen = useUiStore((s) => s.setMobileNavOpen)
  // The outlet is keyed by path, so the page leaving runs its exit before the
  // next one enters (un-keyed, AnimatePresence never saw a child leave). The
  // query is not part of the key: `?tab=` changes a page, it does not replace it.
  const { pathname } = useLocation()
  const outlet = useOutlet()

  // A package may bring modalities this build has never met (roadmap 20.6):
  // their labels and colours come from the server. The page is drawn again
  // once, when one is first learned, so nothing keeps the neutral style.
  const { data: modalities } = useModalities()
  const vocabulary = useMemo(() => {
    registerModalities(modalities)
    return modalityVocabularyVersion()
  }, [modalities])

  // The drawer is the phone's; a window widened past md with it open would
  // keep its scrim over the page with nothing in it.
  useEffect(() => {
    const wide = window.matchMedia?.('(min-width: 768px)')
    if (!wide) return
    const close = () => { if (wide.matches) setMobileNavOpen(false) }
    wide.addEventListener('change', close)
    return () => wide.removeEventListener('change', close)
  }, [setMobileNavOpen])

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      {/* The first stop of the keyboard: past the sidebar, to the page. */}
      <a
        href="#main"
        className="sr-only focus-visible:not-sr-only focus-visible:fixed focus-visible:left-3 focus-visible:top-3 focus-visible:z-50 focus-visible:rounded-md focus-visible:bg-background focus-visible:px-3 focus-visible:py-2 focus-visible:text-sm focus-visible:font-medium focus-visible:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        Skip to content
      </a>
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
        <main id="main" tabIndex={-1} className="flex-1 overflow-hidden flex flex-col focus-visible:outline-none">
          <AnimatePresence mode="wait">
            <div key={`${pathname}:${vocabulary}`} className="contents">
              <HeldLocation>
                <RouteErrorBoundary resetKey={pathname}>{outlet}</RouteErrorBoundary>
              </HeldLocation>
            </div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  )
}
