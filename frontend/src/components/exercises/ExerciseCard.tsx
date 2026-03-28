import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import type { Exercise } from '@/api/types'

const EFFORT_DOT: Record<string, string> = {
  low: 'bg-emerald-400',
  medium: 'bg-yellow-400',
  high: 'bg-orange-500',
  max: 'bg-red-500',
}

const CATEGORY_COLORS: Record<string, string> = {
  barbell: 'text-red-400',
  kettlebell: 'text-orange-400',
  bodyweight: 'text-emerald-400',
  aerobic: 'text-sky-400',
  carries: 'text-amber-400',
  sandbag: 'text-yellow-600',
  mobility: 'text-teal-400',
  skill: 'text-violet-400',
  rehab: 'text-lime-400',
  gym_jones: 'text-pink-400',
}

interface ExerciseCardProps {
  exercise: Exercise
  onClick: () => void
}

export function ExerciseCard({ exercise, onClick }: ExerciseCardProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.02, y: -1 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="w-full rounded-xl border border-border bg-card p-4 text-left transition-shadow hover:shadow-sm hover:border-primary/40"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-foreground truncate">{exercise.name}</h3>
          <span className={cn('text-[10px] font-medium uppercase tracking-wider', CATEGORY_COLORS[exercise.category] ?? 'text-muted-foreground')}>
            {exercise.category.replace(/_/g, ' ')}
          </span>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <div
            className={cn('size-2 rounded-full', EFFORT_DOT[exercise.effort] ?? 'bg-muted')}
            title={`Effort: ${exercise.effort}`}
          />
        </div>
      </div>

      <div className="mt-2 flex flex-wrap gap-1">
        {exercise.modality.slice(0, 2).map((m) => (
          <ModalityBadge key={m} modality={m} size="sm" />
        ))}
        {exercise.modality.length > 2 && (
          <span className="text-[10px] text-muted-foreground">+{exercise.modality.length - 2}</span>
        )}
      </div>

      {exercise.notes && (
        <p className="mt-2 text-[10px] text-muted-foreground line-clamp-2 leading-relaxed">
          {exercise.notes}
        </p>
      )}
    </motion.button>
  )
}
