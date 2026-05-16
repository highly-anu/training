import { useEffect, useId, useRef } from 'react'
import { cn } from '@/lib/utils'

// Lucide "Dumbbell" icon — v1.7.0, 24×24 viewBox
const PATHS = [
  'M17.596 12.768a2 2 0 1 0 2.829-2.829l-1.768-1.767a2 2 0 0 0 2.828-2.829l-2.828-2.828a2 2 0 0 0-2.829 2.828l-1.767-1.768a2 2 0 1 0-2.829 2.829z',
  'm2.5 21.5 1.4-1.4',
  'm20.1 3.9 1.4-1.4',
  'M5.343 21.485a2 2 0 1 0 2.829-2.828l1.767 1.768a2 2 0 1 0 2.829-2.829l-6.364-6.364a2 2 0 1 0-2.829 2.829l1.768 1.767a2 2 0 0 0-2.828 2.829z',
  'm9.6 14.4 4.8-4.8',
]

interface DumbbellLoaderProps {
  className?: string
  label?: string
}

/**
 * Animated Lucide Dumbbell icon where a bright highlight sweeps along
 * the icon's strokes from bottom-left to top-right (following the
 * dumbbell's diagonal axis). Uses SVG mask (icon shape) + clipPath
 * (moving diagonal strip) so no Framer Motion dep is needed here.
 */
export function DumbbellLoader({ className, label = 'Loading...' }: DumbbellLoaderProps) {
  const uid   = useId().replace(/\W/g, '')
  const mId   = `dbm-${uid}`   // mask id
  const cId   = `dbc-${uid}`   // clipPath id
  const strip = useRef<SVGRectElement>(null)

  useEffect(() => {
    const el = strip.current
    if (!el) return

    // Animate the strip's x from −20 to 44 (user-space units, before rotation).
    // After rotate(−45 12 12) this moves the strip from the bottom-left of the
    // icon to the top-right, along the dumbbell's diagonal axis.
    const FROM = -20, TO = 44, DURATION = 1800
    let start: number | null = null
    let raf: number

    const tick = (ts: number) => {
      if (start === null) start = ts
      const t = ((ts - start) % DURATION) / DURATION
      el.setAttribute('x', String(FROM + (TO - FROM) * t))
      raf = requestAnimationFrame(tick)
    }

    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])

  return (
    <div className={cn('flex flex-col items-center gap-3 text-muted-foreground', className)}>
      <svg viewBox="0 0 24 24" className="w-10 h-10" fill="none" aria-hidden>
        <defs>
          {/* White strokes define the icon shape — white = opaque in SVG mask */}
          <mask id={mId}>
            <g stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none">
              {PATHS.map((d, i) => <path key={i} d={d} />)}
            </g>
          </mask>

          {/* Diagonal strip perpendicular to the dumbbell's 45° axis */}
          <clipPath id={cId}>
            <rect
              ref={strip}
              x={-20} y={-50}
              width={9} height={124}
              transform="rotate(-45 12 12)"
            />
          </clipPath>
        </defs>

        {/* Dim track — full icon at low opacity */}
        <rect width="24" height="24" fill="currentColor" opacity={0.18} mask={`url(#${mId})`} />

        {/* Bright highlight — intersection of icon strokes and moving strip */}
        <rect
          width="24" height="24"
          fill="currentColor"
          mask={`url(#${mId})`}
          clipPath={`url(#${cId})`}
        />
      </svg>
      {label && <p className="text-sm">{label}</p>}
    </div>
  )
}
