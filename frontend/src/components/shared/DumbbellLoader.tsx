import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'

// All 5 Lucide "Dumbbell" paths (v1.7.0, 24×24 viewBox) — used for the dim base
// so the icon looks exactly like the Lucide icon at rest.
const ICON_PATHS = [
  'M17.596 12.768a2 2 0 1 0 2.829-2.829l-1.768-1.767a2 2 0 0 0 2.828-2.829l-2.828-2.828a2 2 0 0 0-2.829 2.828l-1.767-1.768a2 2 0 1 0-2.829 2.829z',
  'm2.5 21.5 1.4-1.4',
  'm20.1 3.9 1.4-1.4',
  'M5.343 21.485a2 2 0 1 0 2.829-2.828l1.767 1.768a2 2 0 1 0 2.829-2.829l-6.364-6.364a2 2 0 1 0-2.829 2.829l1.768 1.767a2 2 0 0 0-2.828 2.829z',
  'm9.6 14.4 4.8-4.8',
]

/**
 * Single closed path tracing the outer contour of the Lucide Dumbbell.
 * Used only for the traveling highlight so pathOffset can animate continuously.
 *
 * Construction: right weight outer arcs → bar top-edge line → left weight
 * outer arcs → Z closes via bar bottom-edge line back to start.
 */
const OUTLINE_PATH = [
  'M 17.596 12.768',
  'a 2 2 0 1 0 2.829 -2.829',
  'l -1.768 -1.767',
  'a 2 2 0 0 0 2.828 -2.829',
  'l -2.828 -2.828',
  'a 2 2 0 0 0 -2.829 2.828',
  'l -1.767 -1.768',
  'a 2 2 0 1 0 -2.829 2.829',
  'L 6.404 11.232',              // bar top edge
  'a 2 2 0 1 0 -2.829 2.829',
  'l 1.768 1.767',
  'a 2 2 0 0 0 -2.828 2.829',
  'L 5.343 21.485',
  'a 2 2 0 1 0 2.829 -2.828',
  'l 1.767 1.768',
  'a 2 2 0 1 0 2.829 -2.829',
  'Z',                           // bar bottom edge → back to start
].join(' ')

interface DumbbellLoaderProps {
  className?: string
  label?: string
}

export function DumbbellLoader({ className, label = 'Loading...' }: DumbbellLoaderProps) {
  return (
    <div className={cn('flex flex-col items-center gap-3 text-muted-foreground', className)}>
      <svg viewBox="0 0 24 24" className="w-10 h-10" fill="none" aria-hidden>
        {/* Dim base — full Lucide icon so it looks identical to the icon set */}
        <g
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity={0.2}
        >
          {ICON_PATHS.map((d, i) => <path key={i} d={d} />)}
        </g>

        {/* Traveling highlight along the outer contour */}
        <motion.path
          d={OUTLINE_PATH}
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          initial={{ pathLength: 0.14, pathOffset: 0 }}
          animate={{ pathOffset: 1 }}
          transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
        />
      </svg>
      {label && <p className="text-sm">{label}</p>}
    </div>
  )
}
