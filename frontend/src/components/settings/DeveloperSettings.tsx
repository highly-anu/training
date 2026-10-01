import { Link } from 'react-router-dom'
import { Terminal } from 'lucide-react'
import { Button } from '@/components/ui/button'

/**
 * Settings → Developer, dev builds only (src/lib/featureFlags.ts). Where
 * this build sends its requests, and the way into the Dev Lab.
 */
export function DeveloperSettings() {
  const apiBase = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? ''
  const mockMode = !apiBase

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Settings
          </p>
          <h2 className="text-2xl font-semibold tracking-tight">Developer.</h2>
          <p className="text-sm text-muted-foreground max-w-prose">
            Present in development builds only. Nothing here reaches an athlete.
          </p>
        </div>

        <div className="space-y-3">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">API target</h3>
          <div className="rounded-lg border border-border/30 bg-card/40 p-4 space-y-1">
            <p className="text-xs font-mono">{mockMode ? 'mock data (MSW)' : apiBase}</p>
            <p className="text-[11px] text-muted-foreground">
              {mockMode
                ? 'No VITE_API_BASE_URL in frontend/.env.local, so the app answers itself from the mock handlers. Explore, Home and the inbox need the real API.'
                : 'Set by VITE_API_BASE_URL in frontend/.env.local and baked in at build time.'}
            </p>
          </div>
        </div>

        <div className="space-y-3">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">Dev Lab</h3>
          <div className="rounded-lg border border-border/30 bg-card/40 p-4 flex items-center justify-between gap-3">
            <p className="text-[11px] text-muted-foreground">
              Pipeline trace, object browser, ontology and model interactions. Behind VITE_DEVLAB in production builds.
            </p>
            <Button asChild size="sm" variant="outline" className="h-8 text-xs shrink-0">
              <Link to="/dev"><Terminal className="size-3.5" /> Open Dev Lab</Link>
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
