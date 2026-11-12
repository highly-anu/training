import { EFFORT_HEX, EXERCISE_CATEGORY_TEXT, NEUTRAL_HEX } from '@/lib/dataColors'
import { motion } from 'framer-motion'
import { pressMotion } from '@/lib/motion'
import { cn } from '@/lib/utils'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { ExerciseAnimationPanel } from './ExerciseAnimationPanel'
import type { Exercise } from '@/api/types'

interface ExerciseCardProps {
  exercise: Exercise
  onClick: () => void
}

export function ExerciseCard({ exercise, onClick }: ExerciseCardProps) {
  return (
    <motion.button
      {...pressMotion}
      onClick={onClick}
      className="w-full rounded-xl border border-border bg-card p-4 text-left transition-shadow hover:shadow-sm hover:border-primary/40"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-foreground truncate">{exercise.name}</h3>
          <span className={cn('text-[10px] font-medium uppercase tracking-wider', EXERCISE_CATEGORY_TEXT[exercise.category] ?? 'text-muted-foreground')}>
            {exercise.category.replace(/_/g, ' ')}
          </span>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          {exercise.animation?.type === 'gif' ? (
            <div className="relative">
              <ExerciseAnimationPanel
                animation={exercise.animation}
                exerciseName={exercise.name}
                category={exercise.category}
                variant="card"
              />
              <div
                className="absolute -bottom-0.5 -right-0.5 size-2 rounded-full border border-card"
                style={{ backgroundColor: EFFORT_HEX[exercise.effort] ?? NEUTRAL_HEX }}
                title={`Effort: ${exercise.effort}`}
              />
            </div>
          ) : (
            <div
              className="size-2 rounded-full"
              style={{ backgroundColor: EFFORT_HEX[exercise.effort] ?? NEUTRAL_HEX }}
              title={`Effort: ${exercise.effort}`}
            />
          )}
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
