import { createContext, useContext, type ReactElement, type ReactNode } from 'react'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

const Provided = createContext(false)

/**
 * The app's one tooltip provider (App.tsx): a tooltip opens after 400 ms, at
 * once when the pointer moves from one to the next.
 */
export function TipProvider({ children }: { children: ReactNode }) {
  return (
    <Provided.Provider value>
      <TooltipProvider delayDuration={400}>{children}</TooltipProvider>
    </Provided.Provider>
  )
}

interface TipProps {
  /** What the control does, in the words its `aria-label` uses. Empty: no tooltip. */
  label: ReactNode
  /** Its keyboard shortcut, shown as keys after the label ("g t"). */
  keys?: string
  side?: 'top' | 'right' | 'bottom' | 'left'
  /** The control: one element that takes a ref — a `<button>` or `<Button>`. */
  children: ReactElement
}

/**
 * The name of an icon-only control, shown on hover and on keyboard focus
 * (docs/frontend-design.md §11.10). The control still carries its own
 * `aria-label` — the tooltip is for the eye — and never a `title`, which a
 * keyboard cannot open, a touch never sees and no theme styles.
 */
export function Tip({ label, keys, side = 'top', children }: TipProps) {
  const provided = useContext(Provided)
  if (label == null || label === '' || label === false) return children
  const tip = (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent side={side} className="flex items-center gap-2 px-2 py-1 text-xs">
        {label}
        {keys && <Keys keys={keys} />}
      </TooltipContent>
    </Tooltip>
  )
  // A component rendered alone (a test, a story) still gets its tooltip.
  return provided ? tip : <TooltipProvider delayDuration={400}>{tip}</TooltipProvider>
}

/** A shortcut as key caps: "g t" is two keys, pressed one after the other. */
export function Keys({ keys, spoken = false }: { keys: string; /** Read out: the keys are the content, not a hint beside a label. */ spoken?: boolean }) {
  return (
    <span className="flex items-center gap-0.5" aria-hidden={spoken ? undefined : true}>
      {keys.split(' ').map((key, i) => (
        <kbd key={i} className="rounded border bg-muted px-1 font-mono text-[10px] leading-4 text-muted-foreground">
          {key}
        </kbd>
      ))}
    </span>
  )
}
