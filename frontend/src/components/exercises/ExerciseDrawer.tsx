import { motion } from 'framer-motion'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Separator } from '@/components/ui/separator'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PrereqChain } from './PrereqChain'
import { ExerciseAnimationPanel } from './ExerciseAnimationPanel'
import { ExerciseCuePoints } from './ExerciseCuePoints'
import { MuscleHighlightDiagram } from './MuscleHighlightDiagram'
import type { Exercise } from '@/api/types'

interface ExerciseDrawerProps {
  exercise: Exercise | null
  allExercises: Exercise[]
  open: boolean
  onClose: () => void
  onNavigate: (id: string) => void
}

export function ExerciseDrawer({ exercise, allExercises, open, onClose, onNavigate }: ExerciseDrawerProps) {
  return (
    <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        {exercise && (
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0, transition: { delay: 0.1, duration: 0.25 } }}
            className="space-y-5"
          >
            <SheetHeader>
              <SheetTitle className="text-left">{exercise.name}</SheetTitle>
              <div className="flex flex-wrap gap-1">
                {exercise.modality.map((m) => (
                  <ModalityBadge key={m} modality={m} />
                ))}
              </div>
            </SheetHeader>

            {exercise.animation && exercise.animation.type !== 'none' && (
              <ExerciseAnimationPanel
                animation={exercise.animation}
                exerciseName={exercise.name}
                category={exercise.category}
                variant="drawer"
              />
            )}

            <Separator />

            {/* Metadata */}
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <Pair label="Category" value={exercise.category.replace(/_/g, ' ')} />
              <Pair label="Effort" value={exercise.effort} />
              <Pair label="Bilateral" value={exercise.bilateral ? 'Yes' : 'No'} />
              {exercise.typical_volume && (
                <Pair label="Typical" value={`${exercise.typical_volume.sets}×${exercise.typical_volume.reps}`} />
              )}
            </dl>

            {/* Movement patterns */}
            {exercise.movement_patterns.length > 0 && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Patterns</p>
                <div className="flex flex-wrap gap-1">
                  {exercise.movement_patterns.map((p) => (
                    <span key={p} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground capitalize">
                      {p.replace(/_/g, ' ')}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Progressions */}
            {Object.keys(exercise.progressions).length > 0 && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Progressions</p>
                <div className="space-y-1 text-xs text-muted-foreground">
                  {exercise.progressions.load && <p><span className="text-foreground font-medium">Load:</span> {exercise.progressions.load}</p>}
                  {exercise.progressions.volume && <p><span className="text-foreground font-medium">Volume:</span> {exercise.progressions.volume}</p>}
                  {exercise.progressions.complexity && <p><span className="text-foreground font-medium">Complexity:</span> {exercise.progressions.complexity}</p>}
                </div>
              </div>
            )}

            {/* Scaling down */}
            {exercise.scaling_down && exercise.scaling_down.length > 0 && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Scale Down To</p>
                <div className="flex flex-wrap gap-1">
                  {exercise.scaling_down.map((s) => (
                    <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">
                      {s.replace(/_/g, ' ')}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Description */}
            {exercise.description && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">About</p>
                <p className="text-sm text-muted-foreground leading-relaxed">{exercise.description}</p>
              </div>
            )}

            {/* Cue points */}
            {(exercise.cue_points?.length || exercise.coaching_focus || exercise.common_errors?.length) && (
              <ExerciseCuePoints
                cues={exercise.cue_points ?? []}
                errors={exercise.common_errors}
                coachingFocus={exercise.coaching_focus}
              />
            )}

            {/* Notes */}
            {exercise.notes && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Coaching Notes</p>
                <p className="text-sm text-muted-foreground leading-relaxed">{exercise.notes}</p>
              </div>
            )}

            {/* Muscle diagram */}
            {exercise.muscle_diagram &&
              (exercise.muscle_diagram.highlight_primary.length > 0 || exercise.muscle_diagram.highlight_secondary.length > 0) && (
              <MuscleHighlightDiagram diagram={exercise.muscle_diagram} />
            )}

            <Separator />

            {/* Prereq chain */}
            <div>
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Progression Chain</p>
              <PrereqChain
                exercise={exercise}
                allExercises={allExercises}
                onSelect={(id) => { onNavigate(id); }}
              />
            </div>

            {/* Sources */}
            {exercise.sources.length > 0 && (
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Sources</p>
                <div className="flex flex-wrap gap-1">
                  {exercise.sources.map((s) => (
                    <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">
                      {s}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </motion.div>
        )}
      </SheetContent>
    </Sheet>
  )
}

function Pair({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground text-xs">{label}</dt>
      <dd className="font-medium text-xs capitalize">{value}</dd>
    </>
  )
}
