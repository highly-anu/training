import { useState } from 'react'
import { motion } from 'framer-motion'
import { Check, Info } from 'lucide-react'
import { cn } from '@/lib/utils'
import { PriorityBars } from './PriorityBars'
import { GoalDetailModal } from './GoalDetailModal'
import type { GoalProfile } from '@/api/types'

interface GoalCardProps {
  goal: GoalProfile
  selected: boolean
  onSelect: () => void
}

export function GoalCard({ goal, selected, onSelect }: GoalCardProps) {
  const [detailOpen, setDetailOpen] = useState(false)

  return (
    <>
      <motion.div
        whileHover={{ scale: 1.02, y: -2 }}
        transition={{ type: 'spring', stiffness: 300, damping: 20 }}
        className={cn(
          'relative w-full h-full flex flex-col rounded-xl border transition-shadow',
          'bg-card shadow-sm hover:shadow-md',
          selected
            ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
            : 'border-border hover:border-primary/50'
        )}
      >
        {selected && (
          <span className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-primary z-10">
            <Check className="size-3 text-primary-foreground" />
          </span>
        )}

        {/* === Text zone (fixed height) === */}
        <button
          onClick={onSelect}
          className="flex-none p-5 pb-3 text-left w-full"
          style={{ minHeight: '5rem' }}
        >
          <h3 className="text-sm font-semibold text-foreground pr-6 line-clamp-1">{goal.name}</h3>
          <p className="text-xs text-muted-foreground leading-relaxed mt-1 line-clamp-3">
            {goal.description}
          </p>
        </button>

        {/* === Chart zone (fixed height) === */}
        <button
          onClick={onSelect}
          className="flex-none px-5 py-3 text-left w-full"
          style={{ height: '7.5rem' }}
        >
          <PriorityBars priorities={goal.priorities} maxItems={5} />
        </button>

        {/* === Chips + Details zone (fixed height) === */}
        <div
          className="flex-none px-5 pt-2 pb-4 flex items-end justify-between gap-2"
          style={{ minHeight: '3rem' }}
        >
          <div className="flex gap-1 flex-wrap">
            {goal.primary_sources.slice(0, 3).map((src) => (
              <span
                key={src}
                className="inline-flex text-[9px] px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground"
              >
                {src.replace(/_/g, ' ')}
              </span>
            ))}
          </div>

          <button
            onClick={(e) => {
              e.stopPropagation()
              setDetailOpen(true)
            }}
            className={cn(
              'flex-none flex items-center gap-1 text-[10px] font-medium rounded-md px-2 py-1',
              'text-muted-foreground hover:text-foreground hover:bg-muted transition-colors'
            )}
          >
            <Info className="size-3" />
            Details
          </button>
        </div>
      </motion.div>

      <GoalDetailModal
        goal={goal}
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
      />
    </>
  )
}
