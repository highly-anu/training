import { AnimatePresence, motion, type Variants } from 'framer-motion'
import { ChevronLeft, ChevronRight, Wand2 } from 'lucide-react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { Button } from '@/components/ui/button'
import { StepIndicator } from '@/components/builder/StepIndicator'
import { GoalGrid } from '@/components/builder/GoalGrid'
import { ProgramTuner } from '@/components/builder/ProgramTuner'
import { ConstraintsForm } from '@/components/builder/ConstraintsForm'
import { ReviewGenerate } from '@/components/builder/ReviewGenerate'
import { useBuilderStore } from '@/store/builderStore'
import { useGoals } from '@/api/goals'

const GOAL_COLORS = ['#6366f1', '#f59e0b', '#10b981', '#f43f5e', '#0ea5e9', '#a855f7']

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
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <Wand2 className="size-5 text-primary" />
        <div className="flex-1 min-w-0">
          <h1 className="text-lg font-semibold">{stepInfo.title}</h1>
          <p className="text-xs text-muted-foreground">{stepInfo.sub}</p>
        </div>
        <StepIndicator current={step} />
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
              {selectedGoalIds.length >= 2 && (() => {
                const totalRaw = selectedGoalIds.reduce((s, gid) => s + (goalWeights[gid] ?? 50), 0)
                const pieData = selectedGoalIds.map((id, i) => ({
                  id,
                  name: goals?.find((g) => g.id === id)?.name ?? id.replace(/_/g, ' '),
                  value: Math.round(((goalWeights[id] ?? 50) / totalRaw) * 100),
                  raw: goalWeights[id] ?? 50,
                  color: GOAL_COLORS[i % GOAL_COLORS.length],
                }))
                return (
                  <div className="rounded-xl border bg-card p-4 space-y-4">
                    <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Goal Weights
                    </p>

                    {/* Pie chart */}
                    <div className="relative">
                      <ResponsiveContainer width="100%" height={160}>
                        <PieChart>
                          <Pie
                            data={pieData}
                            cx="50%"
                            cy="50%"
                            innerRadius={44}
                            outerRadius={68}
                            paddingAngle={3}
                            dataKey="value"
                            animationBegin={0}
                            animationDuration={500}
                          >
                            {pieData.map((entry) => (
                              <Cell key={entry.id} fill={entry.color} stroke="transparent" />
                            ))}
                          </Pie>
                          <Tooltip
                            contentStyle={{
                              backgroundColor: 'var(--card)',
                              border: '1px solid var(--border)',
                              borderRadius: '8px',
                              fontSize: '12px',
                              color: 'var(--foreground)',
                            }}
                            formatter={(v, name) => [`${String(v)}%`, String(name)]}
                          />
                        </PieChart>
                      </ResponsiveContainer>
                    </div>

                    {/* Sliders */}
                    <div className="space-y-3">
                      {pieData.map((entry) => (
                        <div key={entry.id} className="space-y-1">
                          <div className="flex items-center justify-between text-xs">
                            <div className="flex items-center gap-1.5 min-w-0">
                              <span
                                className="size-2 rounded-full shrink-0"
                                style={{ backgroundColor: entry.color }}
                              />
                              <span className="truncate capitalize">{entry.name}</span>
                            </div>
                            <span className="font-semibold ml-2 shrink-0 tabular-nums">
                              {entry.value}%
                            </span>
                          </div>
                          <input
                            type="range" min={5} max={95} step={5}
                            value={entry.raw}
                            onChange={(e) => setGoalWeight(entry.id, parseInt(e.target.value))}
                            style={{ accentColor: entry.color }}
                            className="w-full"
                          />
                        </div>
                      ))}
                    </div>

                    <p className="text-[10px] text-muted-foreground">
                      Weights control how much each goal's priorities shape the generated program.
                    </p>
                  </div>
                )
              })()}
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
