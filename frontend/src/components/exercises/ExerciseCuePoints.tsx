import { motion } from 'framer-motion'
import { staggerVariants } from '@/lib/motion'

interface ExerciseCuePointsProps {
  cues: string[]
  errors?: string[]
  coachingFocus?: string
  title?: string
}

const { list: listVariants, item: itemVariants } = staggerVariants('loose')

export function ExerciseCuePoints({
  cues,
  errors,
  coachingFocus,
  title = 'Coaching Cues',
}: ExerciseCuePointsProps) {
  if (!cues.length && !coachingFocus && !errors?.length) return null

  return (
    <div className="space-y-4">
      {coachingFocus && (
        <div className="rounded-md bg-primary/5 border border-primary/20 px-3 py-2">
          <p className="text-[11px] font-semibold text-primary/80 uppercase tracking-wider mb-0.5">Focus</p>
          <p className="text-sm text-foreground leading-snug">{coachingFocus}</p>
        </div>
      )}

      {cues.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">{title}</p>
          <motion.ol
            variants={listVariants}
            initial="hidden"
            animate="visible"
            className="space-y-1.5"
          >
            {cues.map((cue, i) => (
              <motion.li
                key={i}
                variants={itemVariants}
                className="flex items-start gap-2 text-sm text-foreground/80"
              >
                <span className="shrink-0 flex size-5 items-center justify-center rounded-full bg-muted text-[10px] font-semibold text-muted-foreground mt-0.5">
                  {i + 1}
                </span>
                <span className="leading-snug">{cue}</span>
              </motion.li>
            ))}
          </motion.ol>
        </div>
      )}

      {errors && errors.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">Common Errors</p>
          <ul className="space-y-1.5">
            {errors.map((err, i) => (
              <li key={i} className="flex items-start gap-2 text-sm text-muted-foreground">
                <span className="shrink-0 text-warn mt-0.5">&#x26A0;</span>
                <span className="leading-snug">{err}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
