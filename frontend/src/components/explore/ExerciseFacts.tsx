import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { ExerciseAnimationPanel } from '@/components/exercises/ExerciseAnimationPanel'
import { ExerciseCuePoints } from '@/components/exercises/ExerciseCuePoints'
import { MuscleHighlightDiagram } from '@/components/exercises/MuscleHighlightDiagram'
import { EX_CATEGORY_COLORS } from '@/lib/exploreColors'
import type { Exercise } from '@/api/types'

/**
 * An exercise as its own document says it: name and kinds, the demo, what it
 * is, how it progresses, coaching notes, cues and the muscles it works. Needs
 * nothing but the exercise, so Explore's panel and a shared session's page
 * (which has no library to look one up in) draw the same thing.
 */
export function ExerciseFacts({ exercise }: { exercise: Exercise }) {
  return (
    <>
    {/* Header */}
    <div>
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-1">Exercise</p>
      <h2 className="text-base font-semibold"
        style={{ color: EX_CATEGORY_COLORS[exercise.category] ?? undefined }}>
        {exercise.name}
      </h2>
      <div className="flex flex-wrap gap-1 mt-2">
        {exercise.modality.map((m) => <ModalityBadge key={m} modality={m} />)}
      </div>
    </div>

    {/* Animation */}
    {exercise.animation && exercise.animation.type !== 'none' && (
      <ExerciseAnimationPanel
        animation={exercise.animation}
        exerciseName={exercise.name}
        category={exercise.category}
        variant="drawer"
      />
    )}

    {/* Meta grid */}
    <div className="grid grid-cols-2 gap-2">
      {[
        { label: 'Category', value: exercise.category.replace(/_/g, ' ') },
        { label: 'Effort',   value: exercise.effort },
        { label: 'Bilateral', value: exercise.bilateral ? 'Yes' : 'No' },
        ...(exercise.typical_volume
          ? [{ label: 'Typical', value: `${exercise.typical_volume.sets}×${exercise.typical_volume.reps}` }]
          : []),
      ].map(({ label, value }) => (
        <div key={label} className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
          <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
          <p className="text-[11px] font-medium capitalize">{value}</p>
        </div>
      ))}
    </div>

    {/* Progressions */}
    {exercise.progressions && Object.keys(exercise.progressions).length > 0 && (
      <div className="space-y-1.5">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Progressions</p>
        <div className="space-y-1 text-xs text-muted-foreground">
          {exercise.progressions.load && <p><span className="text-foreground font-medium">Load:</span> {exercise.progressions.load}</p>}
          {exercise.progressions.volume && <p><span className="text-foreground font-medium">Volume:</span> {exercise.progressions.volume}</p>}
          {exercise.progressions.complexity && <p><span className="text-foreground font-medium">Complexity:</span> {exercise.progressions.complexity}</p>}
        </div>
      </div>
    )}

    {/* Notes */}
    {exercise.notes && (
      <div className="space-y-1.5">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Coaching Notes</p>
        <p className="text-xs text-muted-foreground leading-relaxed">{exercise.notes}</p>
      </div>
    )}

    {/* Description */}
    {exercise.description && (
      <div className="space-y-1.5">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">About</p>
        <p className="text-xs text-muted-foreground leading-relaxed">{exercise.description}</p>
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

    {/* Muscle diagram */}
    {exercise.muscle_diagram &&
      (exercise.muscle_diagram.highlight_primary.length > 0 || exercise.muscle_diagram.highlight_secondary.length > 0) && (
      <MuscleHighlightDiagram diagram={exercise.muscle_diagram} />
    )}
    </>
  )
}
