import { useId, useRef, type ElementType, type KeyboardEvent, type ReactNode } from 'react'
import { motion } from 'framer-motion'
import { pillMotion } from '@/lib/motion'
import { cn } from '@/lib/utils'

export interface SubTabItem<T extends string = string> {
  id: T
  label: string
  Icon?: ElementType
  /** A count beside the label (held-back sessions). */
  badge?: ReactNode
}

interface SubTabsProps<T extends string> {
  tabs: readonly SubTabItem<T>[]
  active: T
  onChange: (tab: T) => void
  /** What the row selects between, for a screen reader: "Analytics sections". */
  label: string
  /** Shared with `<TabPanels tabsId>` so each panel is labelled by its tab. */
  id?: string
  className?: string
}

/** The DOM id of one tab, for a panel's `aria-labelledby`. */
// eslint-disable-next-line react-refresh/only-export-components
export function tabDomId(tabsId: string, tab: string): string {
  return `${tabsId}-tab-${tab}`
}

/** Which tab an arrow, Home or End key moves to; `null` for any other key. */
// eslint-disable-next-line react-refresh/only-export-components
export function nextTab<T extends string>(ids: readonly T[], active: T, key: string): T | null {
  const i = ids.indexOf(active)
  if (i < 0 || ids.length === 0) return null
  switch (key) {
    case 'ArrowRight': return ids[(i + 1) % ids.length]
    case 'ArrowLeft': return ids[(i - 1 + ids.length) % ids.length]
    case 'Home': return ids[0]
    case 'End': return ids[ids.length - 1]
    default: return null
  }
}

/**
 * A page's sections (docs/frontend-design.md §17.5): one tablist, the selected
 * tab marked by a pill that slides to it. Tab reaches the row once and the
 * arrow keys, Home and End move along it, selecting as they go; on a touch
 * screen each tab is 44 px tall. The page owns where the selection lives
 * (`?tab=`); the panels below are `<TabPanels>`.
 */
export function SubTabs<T extends string>({ tabs, active, onChange, label, id, className }: SubTabsProps<T>) {
  const own = useId()
  const tabsId = id ?? own
  const row = useRef<HTMLDivElement>(null)

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const next = nextTab(tabs.map((t) => t.id), active, event.key)
    if (next === null) return
    event.preventDefault()
    onChange(next)
    row.current?.querySelector<HTMLElement>(`#${CSS.escape(tabDomId(tabsId, next))}`)?.focus()
  }

  return (
    // The tabs inside take the focus (a roving tabindex); the list only hears their arrow keys.
    // eslint-disable-next-line jsx-a11y/interactive-supports-focus
    <div
      ref={row}
      role="tablist"
      aria-label={label}
      onKeyDown={onKeyDown}
      className={cn('-m-0.5 flex items-center gap-1 overflow-x-auto p-0.5', className)}
    >
      {tabs.map((tab) => {
        const selected = tab.id === active
        const Icon = tab.Icon
        return (
          <button
            key={tab.id}
            id={tabDomId(tabsId, tab.id)}
            type="button"
            role="tab"
            aria-selected={selected}
            tabIndex={selected ? 0 : -1}
            onClick={() => onChange(tab.id)}
            className={cn(
              'relative flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded border px-3 py-1 text-xs transition-colors',
              'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              '[@media(pointer:coarse)]:min-h-11',
              selected
                ? 'border-transparent text-primary'
                : 'border-border text-muted-foreground hover:bg-muted',
            )}
          >
            {selected && (
              <motion.span
                layoutId={`${tabsId}-pill`}
                {...pillMotion}
                aria-hidden="true"
                className="absolute -inset-px rounded border border-primary/40 bg-primary/15"
              />
            )}
            {Icon && <Icon className="relative size-3.5 shrink-0" aria-hidden="true" />}
            <span className="relative">{tab.label}</span>
            {tab.badge != null && <span className="relative">{tab.badge}</span>}
          </button>
        )
      })}
    </div>
  )
}
