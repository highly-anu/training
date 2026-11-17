import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ChevronDown, Sparkles } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Collapse } from '@/components/motion/Collapse'
import { FailedState } from '@/components/shared/states/FailedState'
import { LoadingState } from '@/components/shared/states/LoadingState'
import { useMethods, useStartBuild } from '@/api/methods'
import { useProfileStore } from '@/store/profileStore'
import { useBuilderStore } from '@/store/builderStore'
import { useMethodDraft } from '@/store/methodDraftStore'
import { TRAINING_LEVELS, TRAINING_LEVEL_LABELS } from '@/lib/gen/clientVocab'
import { equipmentLabel } from '@/lib/equipment'
import { cn } from '@/lib/utils'
import {
  DESCRIPTION_LENGTH, MINUTES, NOTE_LENGTH, PASTED_MAX, buildRequest, startRefusal, textProblem, unavailableReason,
} from '@/lib/methodBuild'

const SECTION = 'text-[10px] uppercase tracking-widest text-muted-foreground/60 font-medium'
const EXAMPLE = 'For example: three strength days a week around squat, press and deadlift, adding weight slowly, '
  + 'with two easy runs. Twelve weeks, an easier week every fourth.'

/**
 * Describe a method in words (or say what to change in one of yours) and
 * start its build. The athlete's level and equipment come from their profile;
 * days and session length from the builder, and can be changed here.
 */
export function DescribeMethod({ revises }: { revises: string | null }) {
  const navigate = useNavigate()
  const { data: methods, isLoading, error, refetch } = useMethods()
  const start = useStartBuild()
  const draft = useMethodDraft()
  const profileLevel = useProfileStore((s) => s.trainingLevel)
  const equipment = useProfileStore((s) => s.equipment)
  const constraints = useBuilderStore((s) => s.constraints)

  const [description, setDescription] = useState(revises ? '' : draft.description)
  const [pastedText, setPastedText] = useState(revises ? '' : draft.pastedText)
  const [pasteOpen, setPasteOpen] = useState(!revises && draft.pastedText.length > 0)
  const [webSearch, setWebSearch] = useState(draft.webSearch)
  const [days, setDays] = useState(constraints.days_per_week ?? 4)
  const [minutes, setMinutes] = useState<number>(
    MINUTES.includes(constraints.session_time_minutes as typeof MINUTES[number]) ? constraints.session_time_minutes! : 60)
  const [level, setLevel] = useState<string>(profileLevel)
  const [tried, setTried] = useState(false)

  const method = revises ? methods?.methods.find((m) => m.id === revises) : undefined
  const unavailable = unavailableReason(methods)
  const problem = revises
    ? textProblem(description, NOTE_LENGTH, 'the change')
    : textProblem(description, DESCRIPTION_LENGTH, 'a description')
      ?? (pastedText.length > PASTED_MAX ? `The pasted text takes at most ${PASTED_MAX.toLocaleString('en')} characters.` : null)
  const refusal = useMemo(() => (start.error ? startRefusal(start.error) : null), [start.error])

  if (isLoading) return <LoadingState shape="lines" label="Loading your methods" />
  if (error || !methods) {
    return <FailedState title="Could not load your methods" error={error} onRetry={() => { void refetch() }} />
  }
  if (revises && !method) {
    return <FailedState title="That method is no longer among yours" error={new Error('Pick one of your methods in the program builder.')} />
  }

  function submit() {
    setTried(true)
    if (problem || unavailable) return
    const form = { description, pastedText, webSearch, answers: { days, minutes, level, equipment } }
    if (!revises) draft.keep({ description, pastedText, webSearch })
    start.mutate(buildRequest(form, revises), {
      onSuccess: (build) => navigate(`/program/new/method/${encodeURIComponent(build.id)}`),
      onError: (e) => {
        const running = startRefusal(e).running
        if (running) navigate(`/program/new/method/${encodeURIComponent(running.id)}`)
      },
    })
  }

  return (
    <form
      className="space-y-6"
      onSubmit={(e) => { e.preventDefault(); submit() }}
    >
      <div className="space-y-2">
        <Label htmlFor="method-description" className="text-sm font-semibold">
          {revises ? `What should change in ${method?.name}?` : 'Describe how you want to train'}
        </Label>
        <p className="text-[11px] text-muted-foreground">
          {revises
            ? 'Say it as you would to a coach. The method keeps its name unless you ask otherwise, and the change becomes a new revision.'
            : 'In your own words: what a week looks like, what you want to get better at, how it should progress. '
              + 'Name a published method if it is one — it is written as your version of it.'}
        </p>
        <Textarea
          id="method-description"
          rows={revises ? 4 : 7}
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder={revises ? 'For example: make the Saturday session a long easy run instead of intervals.' : EXAMPLE}
          aria-invalid={tried && !!problem}
          aria-describedby={tried && problem ? 'method-description-problem' : undefined}
        />
        {tried && problem && (
          <p id="method-description-problem" role="alert" className="text-[11px] text-bad">{problem}</p>
        )}
      </div>

      <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-4">
        <p className={SECTION}>Written for</p>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="space-y-1.5">
            <Label className="text-xs">Days a week</Label>
            <Select value={String(days)} onValueChange={(v) => setDays(Number(v))}>
              <SelectTrigger aria-label="Days a week"><SelectValue /></SelectTrigger>
              <SelectContent>
                {[2, 3, 4, 5, 6, 7].map((n) => <SelectItem key={n} value={String(n)}>{n} days</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">Session length</Label>
            <Select value={String(minutes)} onValueChange={(v) => setMinutes(Number(v))}>
              <SelectTrigger aria-label="Session length"><SelectValue /></SelectTrigger>
              <SelectContent>
                {MINUTES.map((n) => <SelectItem key={n} value={String(n)}>{n} minutes</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">Level</Label>
            <Select value={level} onValueChange={setLevel}>
              <SelectTrigger aria-label="Level"><SelectValue /></SelectTrigger>
              <SelectContent>
                {TRAINING_LEVELS.map((id) => <SelectItem key={id} value={id}>{TRAINING_LEVEL_LABELS[id] ?? id}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
        <p className="text-[11px] text-muted-foreground">
          {equipment.length > 0
            ? <>Your equipment: {equipment.map(equipmentLabel).join(', ')}. </>
            : <>No equipment on your profile, so it is written for bodyweight. </>}
          <Link to="/profile?tab=equipment" className="underline underline-offset-2 hover:text-foreground">Change equipment</Link>
        </p>
      </div>

      {!revises && (
        <div className="space-y-2">
          <button
            type="button"
            onClick={() => setPasteOpen((v) => !v)}
            aria-expanded={pasteOpen}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <ChevronDown className={cn('size-3.5', !pasteOpen && '-rotate-90')} />
            Paste a plan or notes to work from (optional)
          </button>
          <Collapse open={pasteOpen}>
            <Textarea
              rows={6}
              value={pastedText}
              onChange={(e) => setPastedText(e.target.value)}
              aria-label="A plan or notes to work from"
              placeholder="A plan from a coach, a week you wrote down, notes from a book."
            />
          </Collapse>
        </div>
      )}

      <div className="flex items-start justify-between gap-4">
        <div className="space-y-0.5">
          <Label htmlFor="method-web" className="text-sm">Look it up on the web</Label>
          <p className="text-[11px] text-muted-foreground">
            For a published method: reads how its week is really built before writing yours.
          </p>
        </div>
        <Switch id="method-web" checked={webSearch} onCheckedChange={setWebSearch} />
      </div>

      {(unavailable || (refusal && !refusal.running)) && (
        <p role="alert" className="text-xs text-bad">{unavailable ?? refusal?.message}</p>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-[11px] text-muted-foreground">
          Takes a few minutes. {methods.limits.remaining} of {methods.limits.daily} builds left today.
        </p>
        <div className="flex gap-2">
          <Button type="button" variant="outline" size="sm" onClick={() => navigate('/program/new')}>Cancel</Button>
          <Button type="submit" size="sm" loading={start.isPending} disabled={!!unavailable} className="gap-1.5">
            <Sparkles className="size-4" /> {revises ? 'Build the revision' : 'Build the method'}
          </Button>
        </div>
      </div>
    </form>
  )
}
