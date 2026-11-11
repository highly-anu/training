import { PageHeader } from '@/components/layout/PageHeader'
import { AnimatePresence, motion } from 'framer-motion'
import { stepVariants } from '@/lib/motion'
import { Page } from '@/components/layout/Page'
import { ChevronLeft, ChevronRight, Wand2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { StepIndicator } from '@/components/builder/StepIndicator'
import { ProgramSource } from '@/components/builder/ProgramSource'
import { ProgramTuner } from '@/components/builder/ProgramTuner'
import { ConstraintsForm } from '@/components/builder/ConstraintsForm'
import { ReviewGenerate } from '@/components/builder/ReviewGenerate'
import { useBuilderStore } from '@/store/builderStore'

const STEP_TITLES = {
  1: { title: 'Programming Source', sub: 'Philosophy, blend, or custom modality priorities' },
  2: { title: 'Tune & Periodize', sub: 'Track, priorities, and program duration' },
  3: { title: 'Athlete Constraints', sub: 'Schedule, equipment, training level, and injuries' },
  4: { title: 'Review & Preview', sub: 'Verify configuration and preview your program' },
}

export function ProgramBuilder() {
  const { step, direction, selectedGoalIds, sourceMode, setStep } = useBuilderStore()
  const stepInfo = STEP_TITLES[step]
  const variants = stepVariants(direction)

  function goNext() {
    if (step < 4) setStep((step + 1) as 2 | 3 | 4, 'forward')
  }
  function goBack() {
    if (step > 1) setStep((step - 1) as 1 | 2 | 3, 'backward')
  }

  return (
    <Page
      key="builder"
      className="flex h-full flex-col"
    >
      <PageHeader icon={Wand2} title={stepInfo.title} subtitle={stepInfo.sub} actions={<StepIndicator current={step} />} />

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
            >
              <ProgramSource />
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
            disabled={step === 1 && (sourceMode === null || selectedGoalIds.length === 0)}
            className="gap-1"
          >
            Next <ChevronRight className="size-4" />
          </Button>
        )}
      </div>
    </Page>
  )
}
