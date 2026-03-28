import { AnimatePresence, motion, type Variants } from 'framer-motion'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { StepIndicator } from '@/components/builder/StepIndicator'
import { GoalGrid } from '@/components/builder/GoalGrid'
import { ProgramTuner } from '@/components/builder/ProgramTuner'
import { ConstraintsForm } from '@/components/builder/ConstraintsForm'
import { ReviewGenerate } from '@/components/builder/ReviewGenerate'
import { useBuilderStore } from '@/store/builderStore'
import { useGoals } from '@/api/goals'

const STEP_TITLES = {
  1: { title: 'Choose your Goal', sub: 'Select one or more training profiles that match your objective' },
  2: { title: 'Tune your Program', sub: 'Adjust framework, priorities, and duration' },
  3: { title: 'Set Constraints', sub: 'Equipment, schedule, injuries, and current phase' },
  4: { title: 'Review & Generate', sub: 'Confirm your settings and generate your program' },
}

function getStepVariants(direction: 'forward' | 'backward'): Variants {
  return {
    enter: { x: direction === 'forward' ? 60 : -60, opacity: 0 },
    center: { x: 0, opacity: 1, transition: { duration: 0.28, ease: [0.25, 0.1, 0.25, 1] } },
    exit: { x: direction === 'forward' ? -60 : 60, opacity: 0, transition: { duration: 0.18 } },
  }
}

export function ProgramBuilder() {
  const { step, direction, selectedGoalIds, goalWeights, toggleGoal, setGoalWeight, setStep } = useBuilderStore()
  const { data: goals } = useGoals()
  const stepInfo = STEP_TITLES[step]
  const variants = getStepVariants(direction)

  function goNext() {
    if (step < 4) setStep((step + 1) as 2 | 3 | 4, 'forward')
  }
  function goBack() {
    if (step > 1) setStep((step - 1) as 1 | 2 | 3, 'backward')
  }

  return (
    <motion.div
      key="builder"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="border-b bg-card/50 px-6 py-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold tracking-tight text-foreground">{stepInfo.title}</h1>
            <p className="text-sm text-muted-foreground">{stepInfo.sub}</p>
          </div>
          <StepIndicator current={step} />
        </div>
      </div>

      {/* Step content */}
      <div className="flex-1 overflow-y-auto">
        <AnimatePresence mode="wait" custom={direction}>
          {step === 1 && (
            <motion.div
              key="step1"
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              className="p-6 space-y-4"
            >
              <GoalGrid selectedIds={selectedGoalIds} onToggle={toggleGoal} />

              {/* Weight controls — shown when 2+ goals selected */}
              {selectedGoalIds.length >= 2 && (
                <div className="rounded-xl border bg-card p-4 space-y-3">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    Goal Weights
                  </p>
                  {selectedGoalIds.map((id) => {
                    const goalName = goals?.find((g) => g.id === id)?.name ?? id.replace(/_/g, ' ')
                    const raw = goalWeights[id] ?? 50
                    const totalRaw = selectedGoalIds.reduce((s, gid) => s + (goalWeights[gid] ?? 50), 0)
                    const pct = Math.round((raw / totalRaw) * 100)
                    return (
                      <div key={id} className="space-y-1">
                        <div className="flex justify-between text-xs">
                          <span className="truncate capitalize">{goalName}</span>
                          <span className="font-medium ml-2 shrink-0">{pct}%</span>
                        </div>
                        <input
                          type="range" min={5} max={95} step={5}
                          value={raw}
                          onChange={(e) => setGoalWeight(id, parseInt(e.target.value))}
                          className="w-full accent-primary"
                        />
                      </div>
                    )
                  })}
                  <p className="text-[10px] text-muted-foreground">
                    Weights control how much each goal's priorities shape the generated program.
                  </p>
                </div>
              )}
            </motion.div>
          )}

          {step === 2 && (
            <motion.div
              key="step2"
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              className="p-6"
            >
              <ProgramTuner />
            </motion.div>
          )}

          {step === 3 && (
            <motion.div
              key="step3"
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              className="p-6"
            >
              <ConstraintsForm />
            </motion.div>
          )}

          {step === 4 && (
            <motion.div
              key="step4"
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              className="p-6"
            >
              <ReviewGenerate />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Footer nav — always visible */}
      <div className="border-t bg-card/50 px-6 py-3 flex items-center justify-between">
        <Button variant="ghost" size="sm" onClick={goBack} disabled={step === 1} className="gap-1">
          <ChevronLeft className="size-4" /> Back
        </Button>
        {step < 4 && (
          <Button
            size="sm"
            onClick={goNext}
            disabled={selectedGoalIds.length === 0 && step === 1}
            className="gap-1"
          >
            Next <ChevronRight className="size-4" />
          </Button>
        )}
      </div>
    </motion.div>
  )
}
