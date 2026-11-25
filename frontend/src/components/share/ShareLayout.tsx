import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Smartphone } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { appLink } from '@/lib/share'

/**
 * The frame of a shared link's page: no sidebar and no sign-in — whoever has
 * the link reads it. The header says what was shared and offers the app.
 */
export function ShareLayout({ token, kind, title, children }: {
  token?: string
  /** "Session", "Method", "Program". */
  kind?: string
  title?: string | null
  children: ReactNode
}) {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="border-b border-border/40">
        <div className="mx-auto flex max-w-2xl items-center gap-3 px-4 py-3">
          <div className="min-w-0 flex-1">
            <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
              {kind ? `Shared ${kind.toLowerCase()}` : 'Shared link'} · <Link to="/" className="hover:text-foreground">Training Companion</Link>
            </p>
            <h1 className="truncate text-base font-semibold">{title ?? 'Shared link'}</h1>
          </div>
          {token && (
            <Button asChild variant="outline" size="sm" className="h-8 shrink-0 gap-1.5 text-xs">
              <a href={appLink(token)}><Smartphone className="size-3.5" aria-hidden /> Open in the app</a>
            </Button>
          )}
        </div>
      </header>
      <main className="mx-auto max-w-2xl px-4 py-5">{children}</main>
    </div>
  )
}
