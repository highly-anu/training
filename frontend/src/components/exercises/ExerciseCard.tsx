import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { ExerciseAnimationPanel } from './ExerciseAnimationPanel'
import type { Exercise } from '@/api/types'

const EFFORT_DOT: Record<string, string> = {
  low: 'bg-emerald-400',
  medium: 'bg-yellow-400',
  high: 'bg-orange-500',
  max: 'bg-red-500',
}

const CATEGORY_COLORS: Record<string, string> = {
  barbell: 'text-red-700 dark:text-red-300',
  kettlebell: 'text-orange-700 dark:text-orange-300',
  bodyweight: 'text-emerald-700 dark:text-emerald-300',
  aerobic: 'text-sky-700 dark:text-sky-300',
  carries: 'text-amber-700 dark:text-amber-300',
  sandbag: 'text-yellow-700 dark:text-yellow-300',
  mobility: 'text-teal-700 dark:text-teal-300',
  skill: 'text-violet-700 dark:text-violet-300',
  rehab: 'text-lime-700 dark:text-lime-300',
  gym_jones: 'text-pink-700 dark:text-pink-300',
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
          {exercise.animation?.type === 'gif' ? (
            <div className="relative">
              <ExerciseAnimationPanel
                animation={exercise.animation}
                exerciseName={exercise.name}
                category={exercise.category}
                variant="card"
              />
              <div
                className={cn('absolute -bottom-0.5 -right-0.5 size-2 rounded-full border border-card', EFFORT_DOT[exercise.effort] ?? 'bg-muted')}
                title={`Effort: ${exercise.effort}`}
              />
            </div>
          ) : (
            <div
              className={cn('size-2 rounded-full', EFFORT_DOT[exercise.effort] ?? 'bg-muted')}
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
