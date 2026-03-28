import { Loader2, Wand2 } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { ValidationAlert } from '@/components/shared/ValidationAlert'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import { useGenerateProgram } from '@/api/programs'
import type { AthleteConstraints } from '@/api/types'

export function ReviewGenerate() {
  const navigate = useNavigate()
  const { selectedGoalIds, goalWeights, constraints, eventDate, selectedFrameworkId, priorityOverrides, numWeeks } = useBuilderStore()
  const setActiveGoalId = useProfileStore((s) => s.setActiveGoalId)
  const { customInjuryFlags } = useProfileStore()
  const { mutate, isPending, error, data } = useGenerateProgram()

  const hasErrors = data?.validation && !data.validation.feasible
  const isMultiGoal = selectedGoalIds.length > 1

  function handleGenerate() {
    if (!selectedGoalIds.length) return

    const totalRaw = selectedGoalIds.reduce((s, id) => s + (goalWeights[id] ?? 50), 0)
    const normalizedWeights = Object.fromEntries(
      selectedGoalIds.map((id) => [id, (goalWeights[id] ?? 50) / totalRaw])
    )

    mutate(
      {
        goalId: selectedGoalIds[0],
        goalIds: isMultiGoal ? selectedGoalIds : undefined,
        goalWeights: isMultiGoal ? normalizedWeights : undefined,
        constraints: constraints as AthleteConstraints,
        eventDate: eventDate ?? undefined,
        numWeeks: numWeeks ?? undefined,
        frameworkId: selectedFrameworkId,
        priorityOverrides: priorityOverrides,
        customInjuryFlags,
      },
      {
        onSuccess: (result) => {
          if (result.validation.feasible) {
            setActiveGoalId(selectedGoalIds[0])
            navigate('/program')
          }
        },
      }
    )
  }

  const goalLabel = isMultiGoal
    ? selectedGoalIds.map((id) => id.replace(/_/g, ' ')).join(' + ')
    : (selectedGoalIds[0]?.replace(/_/g, ' ') ?? '—')

  return (
    <div className="space-y-6 max-w-lg">
      {/* Summary */}
      <div className="rounded-xl border bg-card p-5 space-y-3">
        <h3 className="text-sm font-semibold text-foreground">Configuration Summary</h3>
        <Separator />
        <dl className="space-y-2 text-sm">
          <Row label={isMultiGoal ? 'Goals' : 'Goal'} value={goalLabel} />
          {isMultiGoal && (
            <Row
              label="Blend"
              value={selectedGoalIds.map((id) => {
                const totalRaw = selectedGoalIds.reduce((s, gid) => s + (goalWeights[gid] ?? 50), 0)
                const pct = Math.round(((goalWeights[id] ?? 50) / totalRaw) * 100)
                return `${id.replace(/_/g, ' ')} ${pct}%`
              }).join(' / ')}
            />
          )}
          {selectedFrameworkId && (
            <Row label="Framework" value={selectedFrameworkId.replace(/_/g, ' ')} />
          )}
          {numWeeks && <Row label="Duration" value={`${numWeeks} weeks`} />}
          <Row label="Days / week" value={String(constraints.days_per_week ?? 4)} />
          <Row label="Session time" value={`${constraints.session_time_minutes ?? 60} min`} />
          <Row label="Level" value={constraints.training_level ?? 'intermediate'} />
          <Row label="Phase" value={constraints.training_phase ?? 'base'} />
          <Row label="Fatigue" value={constraints.fatigue_state ?? 'normal'} />
          <Row label="Equipment" value={`${(constraints.equipment ?? []).length} items`} />
          <Row label="Injuries" value={(constraints.injury_flags ?? []).length === 0 ? 'None' : (constraints.injury_flags ?? []).length + ' flags'} />
          {eventDate && <Row label="Event Date" value={eventDate} />}
        </dl>
      </div>

      {/* Validation feedback */}
      {data?.validation && <ValidationAlert validation={data.validation} />}
      {error && (
        <p className="text-sm text-destructive">{(error as Error).message}</p>
      )}

      {/* Generate button */}
      <motion.div
        animate={{ scale: isPending ? 0.98 : 1 }}
        transition={{ duration: 0.2 }}
      >
        <Button
          size="lg"
          className="w-full gap-2"
          onClick={handleGenerate}
          disabled={isPending || !selectedGoalIds.length || hasErrors === true}
        >
          {isPending ? (
            <>
              <Loader2 className="size-4 animate-spin" />
              Generating…
            </>
          ) : (
            <>
              <Wand2 className="size-4" />
              Generate Program
            </>
          )}
        </Button>
      </motion.div>
    </div>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="font-medium text-foreground capitalize">{value}</dd>
    </div>
  )
}
