import type { ElementType, ReactNode } from 'react'
import { ChevronLeft } from 'lucide-react'
import { cn } from '@/lib/utils'

interface PageHeaderProps {
  /** The page's sidebar icon. */
  icon: ElementType
  /** The page's name — its only `h1`. */
  title: ReactNode
  /** A line under the title: a builder step's hint, the previewed program's name. */
  subtitle?: ReactNode
  /** A flow's way back, before the icon. */
  onBack?: () => void
  /** The page's `<SubTabs>`, after a hairline. */
  tabs?: ReactNode
  /** Right-aligned actions. */
  actions?: ReactNode
  /** A second row under the first (the program's phase bar). */
  children?: ReactNode
  className?: string
}

/**
 * The top of every page (docs/frontend-design.md §17): icon, the page's one
 * `h1`, its sections after a hairline, its actions on the right. The row wraps
 * rather than overflows in a narrow window. A page does not write this by hand.
 */
export function PageHeader({ icon: Icon, title, subtitle, onBack, tabs, actions, children, className }: PageHeaderProps) {
  return (
    <header className={cn('shrink-0 space-y-3 border-b px-6 py-4', className)}>
      <div className="flex flex-wrap items-center gap-x-2 gap-y-3">
        {onBack && (
          <button
            type="button"
            onClick={onBack}
            aria-label="Back"
            className="rounded p-1 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <ChevronLeft className="size-4" />
          </button>
        )}
        <Icon className="size-5 shrink-0 text-primary" aria-hidden="true" />
        <div className="min-w-0 max-w-full shrink-0">
          <h1 className="text-lg font-semibold">{title}</h1>
          {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
        </div>
        {tabs && (
          <div className="ml-2 flex min-w-0 items-center gap-2">
            <div className="h-4 w-px shrink-0 bg-border/60" aria-hidden="true" />
            {tabs}
          </div>
        )}
        {actions && <div className="ml-auto flex flex-wrap items-center justify-end gap-2">{actions}</div>}
      </div>
      {children}
    </header>
  )
}
