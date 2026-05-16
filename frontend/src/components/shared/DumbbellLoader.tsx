import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'

/**
 * Dumbbell outline traced as a single closed path (80×28 viewBox, perimeter ≈ 260 units).
 * Layout: left plate (0–10) → left collar (10–16) → bar (16–64) → right collar (64–70) → right plate (70–80).
 */
const PATH =
  'M 10 0 L 0 0 L 0 28 L 10 28 L 10 21 L 16 21 L 16 17 L 64 17 ' +
  'L 64 21 L 70 21 L 70 28 L 80 28 L 80 0 L 70 0 L 70 7 L 64 7 ' +
  'L 64 11 L 16 11 L 16 7 L 10 7 Z'

interface DumbbellLoaderProps {
  className?: string
  label?: string
}

export function DumbbellLoader({ className, label = 'Loading...' }: DumbbellLoaderProps) {
  return (
    <div className={cn('flex flex-col items-center gap-3 text-muted-foreground', className)}>
      <svg viewBox="0 0 80 28" className="w-16 h-auto" fill="none" aria-hidden>
        {/* Dim track */}
        <path d={PATH} stroke="currentColor" strokeWidth="2" opacity={0.18} />
        {/* Traveling highlight — 12 % of path length (~31 units) */}
        <motion.path
          d={PATH}
          stroke="currentColor"
          strokeWidth="2"
          initial={{ pathLength: 0.12, pathOffset: 0 }}
          animate={{ pathOffset: 1 }}
          transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
        />
      </svg>
      {label && <p className="text-sm">{label}</p>}
    </div>
  )
}
