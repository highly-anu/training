import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'

/**
 * Single closed path tracing the outer contour of the Lucide Dumbbell icon.
 *
 * Construction: the Lucide icon has two separate weight paths (paths 1 & 4).
 * Each weight's inner junction points are:
 *   right weight: (11.232, 6.404) and (17.596, 12.768)
 *   left weight:  (6.404, 11.232) and (12.768, 17.596)
 *
 * The full outline traces the outer arc of the right weight, then a diagonal
 * line along the bar's top edge to the left weight, the outer arc of the left
 * weight, and closes back via the bar's bottom edge — one unbroken loop.
 */
const PATH = [
  'M 17.596 12.768',         // inner bottom-right of right weight (bar bottom edge start)
  'a 2 2 0 1 0 2.829 -2.829',  // outer arc → (20.425, 9.939)
  'l -1.768 -1.767',            //             → (18.657, 8.172)
  'a 2 2 0 0 0 2.828 -2.829',  //             → (21.485, 5.343) top-right tip
  'l -2.828 -2.828',            //             → (18.657, 2.515)
  'a 2 2 0 0 0 -2.829 2.828',  //             → (15.828, 5.343)
  'l -1.767 -1.768',            //             → (14.061, 3.575)
  'a 2 2 0 1 0 -2.829 2.829',  // outer arc → (11.232, 6.404) inner top-left of right weight
  'L 6.404 11.232',             // bar top edge → inner top-right of left weight
  'a 2 2 0 1 0 -2.829 2.829',  // outer arc → (3.575, 14.061)
  'l 1.768 1.767',              //             → (5.343, 15.828)
  'a 2 2 0 0 0 -2.828 2.829',  //             → (2.515, 18.657)
  'L 5.343 21.485',             // replaces implicit Z of left weight → bottom-left tip
  'a 2 2 0 1 0 2.829 -2.828',  // outer arc → (8.172, 18.657)
  'l 1.767 1.768',              //             → (9.939, 20.425)
  'a 2 2 0 1 0 2.829 -2.829',  // outer arc → (12.768, 17.596) inner bottom-right of left weight
  'Z',                          // bar bottom edge closes back to (17.596, 12.768)
].join(' ')

interface DumbbellLoaderProps {
  className?: string
  label?: string
}

export function DumbbellLoader({ className, label = 'Loading...' }: DumbbellLoaderProps) {
  return (
    <div className={cn('flex flex-col items-center gap-3 text-muted-foreground', className)}>
      <svg viewBox="0 0 24 24" className="w-10 h-10" fill="none" aria-hidden>
        {/* Dim track — full outline at low opacity */}
        <path
          d={PATH}
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity={0.18}
        />
        {/* Traveling highlight — 14 % of path length visible */}
        <motion.path
          d={PATH}
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
