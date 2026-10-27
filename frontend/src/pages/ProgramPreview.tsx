import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import { ChevronLeft, Loader2, Play, ScanEye, SlidersHorizontal } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import { ProgramOverview } from '@/components/program/ProgramOverview'
import { PhaseBar } from '@/components/program/PhaseBar'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { ValidationAlert } from '@/components/shared/ValidationAlert'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { HeldBackPanel, RefusedPanel, type HeldBackActions } from '@/components/preview/HeldBackPanel'
import { AdjustSheet, type AdjustableConstraints } from '@/components/preview/AdjustSheet'
import { PreviewSessionSheet, type PreviewSessionTarget } from '@/components/preview/PreviewSessionSheet'
import { sourcesOf,
  commitProgram, commitRegeneratedTail, isInfeasible, useGenerateDraft, type GenerateParams,
} from '@/api/programs'
import { usePhilosophies } from '@/api/philosophies'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'
import { usePreviewStore } from '@/store/previewStore'
import { useProgramStore } from '@/store/programStore'
import { useProfileStore } from '@/store/profileStore'
import { useBuilderStore } from '@/store/builderStore'
import { builderGenerateParams } from '@/lib/builderParams'
import { heldBackSummary, idLabel } from '@/lib/heldBack'
import { cn } from '@/lib/utils'
import type { EquipmentId, TrainingPhase } from '@/api/types'

type PreviewTab = 'overview' | 'calendar' | 'held-back'
const TABS: { id: PreviewTab; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'calendar', label: 'Calendar' },
  { id: 'held-back', label: 'Held back' },
]

/**
 * Program ▸ Preview: a generated program before it is anyone's.
 *
 * The builder's last step lands here with a draft (`new`), and the profile's
 * regenerate offer with the rest of the active program rebuilt for the new
 * settings (`regenerate`, `?mode=regenerate`). The athlete sees the plan,
 * what their constraints held back and what would restore it, adjusts and
 * swaps on the draft, and only "Start this program" / "Apply" saves it.
 */
export function ProgramPreview() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [searchParams, setSearchParams] = useSearchParams()
  const tabParam = searchParams.get('tab') as PreviewTab | null
  const tab: PreviewTab = TABS.some((t) => t.id === tabParam) ? tabParam! : 'overview'
  const urlMode = searchParams.get('mode') === 'regenerate' ? 'regenerate' : 'new'

  const { mode, params, draft, edits, regenerate, setDraft, open, clear } = usePreviewStore()
  const hasActive = useProgramStore((s) => !!s.currentProgram)
  const profileEquipment = useProfileStore((s) => s.equipment)
  const { weeklySchedule, customInjuryFlags } = useProfileStore()
  const generate = useGenerateDraft()
  const { data: philosophies } = usePhilosophies()

  const [target, setTarget] = useState<PreviewSessionTarget | null>(null)
  const [adjustOpen, setAdjustOpen] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [addToProfile, setAddToProfile] = useState(true)

  // Set when the page itself clears the draft on its way out (start, apply,
  // back), so the reload rule below does not redirect over that navigation.
  const leaving = useRef(false)

  // A reload loses the draft (it lives in memory). A builder preview is
  // generated again from the builder's persisted choices; a regenerate
  // preview goes back to where it was offered.
  useEffect(() => {
    if (draft || generate.isPending || leaving.current) return
    if (urlMode === 'regenerate') {
      navigate('/profile', { replace: true })
      return
    }
    const b = useBuilderStore.getState()
    if (b.step !== 4 || b.selectedPhilosophyIds.length === 0) {
      navigate('/program/new', { replace: true })
      return
    }
    const p = builderGenerateParams(b, weeklySchedule, customInjuryFlags)
    generate.mutate(p, { onSuccess: (d) => open('new', p, d) })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft, urlMode])

  const { segments, totalWeeks } = usePhaseCalendar(draft ?? undefined, 1)
  const counts = useMemo(() => (draft ? heldBackSummary(draft) : { slots: 0, sessions: 0 }), [draft])
  const changed = useMemo(() => new Set((regenerate?.changes ?? [])
    .map((c) => `${c.week_index}|${c.day}|${c.session_index}`)), [regenerate])

  const ids = params ? sourcesOf(params).ids.filter(Boolean) : []
  const title = philosophies?.filter((p) => ids.includes(p.id)).map((p) => p.name).join(' + ')
    || draft?.goal?.name || 'Program'
  const refused = isInfeasible(draft)
  const startWeek = (regenerate?.startIdx ?? 0) + 1
  // Equipment the draft is built for that the profile lacks: offered back.
  const extraEquipment = mode === 'new'
    ? (params?.constraints.equipment ?? []).filter((e) => e !== 'open_space' && !profileEquipment.includes(e as EquipmentId))
    : []

  function setTab(next: PreviewTab) {
    setSearchParams((prev) => {
      const n = new URLSearchParams(prev)
      if (next === 'overview') n.delete('tab')
      else n.set('tab', next)
      return n
    }, { replace: true })
  }

  function repreview(patch: Partial<AdjustableConstraints>) {
    if (!params) return
    const next: GenerateParams = { ...params, constraints: { ...params.constraints, ...patch } }
    setAdjustOpen(false)
    generate.mutate(next, { onSuccess: (d) => setDraft(next, d) })
  }

  const actions: HeldBackActions = {
    addEquipment: (add) => repreview({
      equipment: [...new Set([...(params?.constraints.equipment ?? []), ...add])] as EquipmentId[],
    }),
    clearInjuries: () => repreview({ injury_flags: [] }),
    setLevel: (level) => repreview({ training_level: level as AdjustableConstraints['training_level'] }),
    editSchedule: () => {
      if (mode === 'regenerate') {
        navigate('/profile?tab=schedule')
      } else {
        useBuilderStore.getState().setStep(3, 'backward')
        navigate('/program/new')
      }
    },
  }

  function back() {
    if (mode === 'regenerate') {
      leaving.current = true
      clear()
      navigate(-1)
    } else {
      navigate('/program/new')  // the builder keeps its step; the draft stays until replaced
    }
  }

  function commit() {
    if (!draft || !params) return
    if (mode === 'regenerate') {
      if (!commitRegeneratedTail(queryClient, draft, { numWeeks: params.numWeeks, keepBefore: params.keepBefore })) return
    } else {
      if (!commitProgram(queryClient, draft, params)) return
      const b = useBuilderStore.getState()
      useProfileStore.getState().setActiveGoalId(b.selectedGoalIds[0] ?? ids[0])
      if (addToProfile && extraEquipment.length > 0) {
        useProfileStore.getState().setEquipment([...profileEquipment, ...extraEquipment] as EquipmentId[])
      }
      b.reset()
    }
    leaving.current = true
    navigate('/program')
    clear()
  }

  if (!draft || !params) {
    return (
      <div className="p-6">
        <LoadingCard lines={4} />
        {generate.isError && (
          <p className="mt-4 text-sm text-destructive">{(generate.error as Error).message}</p>
        )}
      </div>
    )
  }

  return (
    <motion.div
      key="program-preview"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      className="flex h-full flex-col"
    >
      {/* Header: identity row, then the phase strip (frontend-design §17.8, as Program). */}
      <div className="border-b px-6 py-4 space-y-3 shrink-0">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-3">
          <button type="button" onClick={back} aria-label="Back"
            className="rounded p-1 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <ChevronLeft className="size-4" />
          </button>
          <ScanEye className="size-5 text-primary shrink-0" />
          <h1 className="text-lg font-semibold shrink-0 max-w-full">
            {mode === 'regenerate' ? 'Preview changes' : 'Preview'}
          </h1>
          <span className="text-muted-foreground/50 text-xs">·</span>
          <span className="text-xs text-muted-foreground">{title}</span>
          <div className="ml-4 flex items-center gap-2">
            <div className="w-px h-4 bg-border/60 shrink-0" />
            <div className="flex items-center gap-1">
              {TABS.map((t) => (
                <button key={t.id} type="button" onClick={() => setTab(t.id)}
                  className={cn(
                    'px-3 py-1 rounded text-xs border transition-colors',
                    tab === t.id
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}>
                  {t.label}
                  {t.id === 'held-back' && counts.sessions > 0 && (
                    <span className="ml-1 text-amber-700 dark:text-amber-300">{counts.sessions}</span>
                  )}
                </button>
              ))}
            </div>
          </div>
          <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
            <Button variant="outline" size="sm" className="h-8 gap-1.5 text-xs" onClick={() => setAdjustOpen(true)}
              disabled={generate.isPending}>
              <SlidersHorizontal className="size-3.5" aria-hidden="true" /> Adjust
            </Button>
            <Button size="sm" className="h-8 gap-1.5 text-xs" disabled={refused || generate.isPending}
              onClick={() => setConfirmOpen(true)}>
              <Play className="size-3.5" aria-hidden="true" />
              {mode === 'regenerate' ? `Apply from week ${startWeek}` : 'Start this program'}
            </Button>
          </div>
        </div>
        {!refused && <PhaseBar segments={segments} totalWeeks={totalWeeks} currentWeek={1} />}
      </div>

      <div className="flex-1 overflow-y-auto">
        {generate.isPending && (
          <p className="mx-6 mt-4 inline-flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="size-4 animate-spin" aria-hidden="true" /> Previewing again…
          </p>
        )}
        {mode === 'regenerate' && !refused && regenerate && regenerate.changes.length > 0 && (
          <p className="mx-6 mt-4 text-sm text-muted-foreground">
            Your new settings change {regenerate.changes.length} session{regenerate.changes.length === 1 ? '' : 's'},
            marked in the calendar. Weeks before week {startWeek}, and the days already behind you this week, stay as they are.
          </p>
        )}

        {refused ? (
          <div className="max-w-3xl mx-auto px-6 py-6 space-y-4">
            <ValidationAlert validation={draft.validation} />
            <RefusedPanel params={params} actions={actions} />
            <Button variant="outline" onClick={() => setAdjustOpen(true)}>Adjust</Button>
          </div>
        ) : tab === 'overview' ? (
          <ProgramOverview program={draft} segments={segments} />
        ) : tab === 'calendar' ? (
          <div className="max-w-5xl mx-auto px-6 py-6 space-y-8">
            {draft.weeks.map((weekData, idx) => (
              <div key={`${weekData.week_number}-${idx}`} className="space-y-3">
                <div className="flex items-center gap-2 px-1">
                  <span className="text-sm font-semibold text-foreground">Week {weekData.week_number}</span>
                  <PhaseBadge phase={weekData.phase as TrainingPhase} label={weekData.phase_name} />
                  {weekData.is_deload && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-500/15 text-slate-700 dark:text-slate-300 border border-slate-500/30">
                      Deload
                    </span>
                  )}
                  {(weekData.tests_skipped?.length ?? 0) > 0 && (
                    <span className="text-[10px] text-amber-700 dark:text-amber-300">
                      Test skipped: {weekData.tests_skipped!.map((t) => idLabel(t.reason)).join(', ')}
                    </span>
                  )}
                </div>
                <WeekCalendar
                  weekData={weekData}
                  isCurrentWeek={false}
                  onOpenSession={(day, sessionIndex) => setTarget({ weekIndex: idx, day, sessionIndex })}
                  isHighlighted={changed.size ? (day, i) => changed.has(`${idx}|${day}|${i}`) : undefined}
                />
              </div>
            ))}
          </div>
        ) : (
          <div className="max-w-3xl mx-auto px-6 py-6">
            <HeldBackPanel params={params} draft={draft} actions={actions} busy={generate.isPending} />
          </div>
        )}
      </div>

      <PreviewSessionSheet program={draft} target={target} onClose={() => setTarget(null)} philosophyIds={ids} />
      <AdjustSheet
        open={adjustOpen}
        onOpenChange={setAdjustOpen}
        constraints={params.constraints}
        edits={edits}
        onApply={repreview}
        onEditSchedule={actions.editSchedule}
      />

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {mode === 'regenerate' ? `Apply the changes from week ${startWeek}?`
                : hasActive ? 'Replace your current program?' : 'Start this program?'}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {mode === 'regenerate'
                ? 'The rest of your program is rebuilt for your new settings. The weeks and days already behind you keep their sessions, logs and linked workouts.'
                : hasActive
                  ? `${title} becomes your program. The one you are on now stays in Program ▸ History with its logs and linked workouts.`
                  : `${title} becomes your program.`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          {extraEquipment.length > 0 && (
            <label className="flex items-start gap-2 text-sm">
              <Checkbox checked={addToProfile} onCheckedChange={(v) => setAddToProfile(v === true)} className="mt-0.5" />
              <span>Also add {extraEquipment.map(idLabel).join(', ')} to my profile's equipment</span>
            </label>
          )}
          <AlertDialogFooter>
            <AlertDialogCancel>Keep previewing</AlertDialogCancel>
            <AlertDialogAction onClick={commit}>
              {mode === 'regenerate' ? 'Apply' : hasActive ? 'Replace' : 'Start'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </motion.div>
  )
}
