import { useState } from 'react'
import { format } from 'date-fns'
import { Pencil, Trash2 } from 'lucide-react'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { thresholdTexts } from '@/lib/standards'
import { useDeleteResult, useLogResult, useStandardResults, useUpdateResult } from '@/api/standards'
import type { BenchmarkStandard, StandardEntry, StandardResultInput } from '@/api/types'
import { StandardLadder, StandardLevelBadge } from './StandardLadder'
import { StandardHistoryChart } from './StandardHistoryChart'

const SOURCE_LABEL: Record<string, string> = {
  manual: 'Typed in', session: 'From a session', garmin: 'Garmin', apple_watch: 'Apple Watch', workout: 'From a workout',
}

function dayText(iso: string | null | undefined): string {
  return iso ? format(new Date(`${iso}T12:00:00`), 'd MMM yyyy') : ''
}

const today = () => format(new Date(), 'yyyy-MM-dd')

interface FormProps {
  /** The standard, or none for bodyweight. */
  standard?: BenchmarkStandard
  initial?: StandardEntry
  submitLabel: string
  pending: boolean
  error: string | null
  onSubmit: (input: StandardResultInput) => void
  onCancel?: () => void
}

/**
 * One result as the athlete would write it: the value ("4:58", or for a ×BW
 * standard the load and reps lifted), the day it was done and a note. The
 * server reads and converts it; what it cannot read comes back in its words.
 */
function ResultForm({ standard, initial, submitLabel, pending, error, onSubmit, onCancel }: FormProps) {
  const isRatio = standard?.metricType === 'bw_ratio'
  const [mode, setMode] = useState<'value' | 'load'>(isRatio && !initial ? 'load' : 'value')
  const [text, setText] = useState(initial?.valueText ?? '')
  const [kg, setKg] = useState('')
  const [reps, setReps] = useState('1')
  const [day, setDay] = useState(initial?.date ?? today())
  const [note, setNote] = useState(initial?.note ?? '')
  const hint = standard ? (standard.inputHint ?? standard.unit.trim()) : 'kg'
  const ready = mode === 'load' ? kg.trim() !== '' : text.trim() !== ''

  function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!ready || pending) return
    const base: StandardResultInput = { loggedOn: day, note: note.trim() }
    onSubmit(mode === 'load'
      ? { ...base, kg: Number(kg.replace(',', '.')), reps: Number(reps) || 1 }
      : { ...base, text: text.trim() })
  }

  const field = 'h-8 rounded border border-border/40 bg-card/40 px-2 text-xs text-foreground placeholder:text-muted-foreground/50 focus:border-primary focus:outline-none'
  return (
    <form onSubmit={submit} className="space-y-2">
      {isRatio && (
        <div className="flex gap-1 text-[11px]" role="radiogroup" aria-label="Log as">
          {(['load', 'value'] as const).map((m) => (
            <button key={m} type="button" role="radio" aria-checked={mode === m} onClick={() => setMode(m)}
              className={cn('rounded px-2 py-0.5', mode === m ? 'bg-primary/15 text-foreground' : 'text-muted-foreground hover:text-foreground')}>
              {m === 'load' ? 'Load lifted' : 'Ratio ×BW'}
            </button>
          ))}
        </div>
      )}
      <div className="flex flex-wrap items-end gap-2">
        {mode === 'load' ? (
          <>
            <label className="space-y-0.5">
              <span className="block text-[10px] text-muted-foreground">kg</span>
              <input className={cn(field, 'w-20 text-right')} inputMode="decimal" value={kg} onChange={(e) => setKg(e.target.value)} aria-label="Load in kg" />
            </label>
            <label className="space-y-0.5">
              <span className="block text-[10px] text-muted-foreground">reps</span>
              <input className={cn(field, 'w-14 text-right')} inputMode="numeric" value={reps} onChange={(e) => setReps(e.target.value)} aria-label="Reps" />
            </label>
          </>
        ) : (
          <label className="space-y-0.5">
            <span className="block text-[10px] text-muted-foreground">{standard ? 'Result' : 'Bodyweight'}</span>
            <input className={cn(field, 'w-24 text-right')} inputMode="decimal" placeholder={hint} value={text}
                   onChange={(e) => setText(e.target.value)} aria-label={standard ? `Result (${hint})` : 'Bodyweight in kg'} />
          </label>
        )}
        <label className="space-y-0.5">
          <span className="block text-[10px] text-muted-foreground">Day</span>
          <input type="date" className={field} value={day} max={today()} onChange={(e) => setDay(e.target.value)} aria-label="Day" />
        </label>
        <label className="min-w-32 flex-1 space-y-0.5">
          <span className="block text-[10px] text-muted-foreground">Note</span>
          <input className={cn(field, 'w-full')} value={note} onChange={(e) => setNote(e.target.value)} placeholder="optional" aria-label="Note" />
        </label>
      </div>
      {mode === 'load' && (
        <p className="text-[10px] text-muted-foreground">Divided by your bodyweight on that day; more than one rep is an estimate.</p>
      )}
      {error && <p className="text-[11px] text-red-700 dark:text-red-300">{error}</p>}
      <div className="flex gap-2">
        <Button type="submit" size="sm" className="h-7 text-xs" disabled={!ready || pending}>{submitLabel}</Button>
        {onCancel && <Button type="button" size="sm" variant="ghost" className="h-7 text-xs" onClick={onCancel}>Cancel</Button>}
      </div>
    </form>
  )
}

function EntryRow({ entry, standard }: { entry: StandardEntry; standard?: BenchmarkStandard }) {
  const [editing, setEditing] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const update = useUpdateResult()
  const remove = useDeleteResult()
  if (entry.id == null) return null
  if (editing) {
    return (
      <li className="rounded-md border border-border/40 p-3">
        <ResultForm standard={standard} initial={entry} submitLabel="Save" pending={update.isPending}
          error={update.error?.message ?? null} onCancel={() => { setEditing(false); update.reset() }}
          onSubmit={(input) => {
            // Only what changed: re-sending the printed value would replace a
            // load's kg × reps with the ratio, and its day with the same day.
            const patch: StandardResultInput = {}
            if (input.kg !== undefined) { patch.kg = input.kg; patch.reps = input.reps }
            else if (input.text !== undefined && input.text !== entry.valueText) patch.text = input.text
            if (input.loggedOn && input.loggedOn !== entry.date) patch.loggedOn = input.loggedOn
            if ((input.note ?? '') !== (entry.note ?? '')) patch.note = input.note ?? ''
            if (Object.keys(patch).length === 0) { setEditing(false); return }
            update.mutate({ id: entry.id!, ...patch }, { onSuccess: () => setEditing(false) })
          }} />
      </li>
    )
  }
  return (
    <li className="flex items-start justify-between gap-3 py-2">
      <div className="min-w-0 space-y-0.5 text-xs">
        <p>
          <span className="font-semibold tabular-nums text-foreground">{entry.valueText}</span>{' '}
          {standard && <StandardLevelBadge level={entry.level} domain={standard.domain} />}
          <span className="text-muted-foreground"> · {dayText(entry.date)}</span>
        </p>
        <p className="text-[11px] text-muted-foreground">
          {SOURCE_LABEL[entry.source] ?? entry.source}
          {entry.block && <> · {entry.block.name}</>}
          {entry.inputText && <> · {entry.inputText}</>}
        </p>
        {entry.note && <p className="text-[11px] text-foreground/80">{entry.note}</p>}
        {remove.error && <p className="text-[11px] text-red-700 dark:text-red-300">{remove.error.message}</p>}
      </div>
      {confirming ? (
        <div className="flex shrink-0 items-center gap-1">
          <span className="text-[11px] text-muted-foreground">Delete this result?</span>
          <Button size="sm" variant="destructive" className="h-6 px-2 text-[11px]" disabled={remove.isPending}
                  onClick={() => remove.mutate(entry.id!)}>Delete</Button>
          <Button size="sm" variant="ghost" className="h-6 px-2 text-[11px]" onClick={() => setConfirming(false)}>Keep</Button>
        </div>
      ) : (
        <div className="flex shrink-0 gap-1">
          <button type="button" onClick={() => setEditing(true)} aria-label={`Edit the result of ${dayText(entry.date)}`}
                  className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"><Pencil className="size-3.5" /></button>
          <button type="button" onClick={() => setConfirming(true)} aria-label={`Delete the result of ${dayText(entry.date)}`}
                  className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"><Trash2 className="size-3.5" /></button>
        </div>
      )}
    </li>
  )
}

interface SheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** The standard to show; none shows the bodyweight series. */
  standard?: BenchmarkStandard
}

/**
 * One standard — or the bodyweight series — and every result on it: where the
 * athlete stands, the ladder, the history across programs, and each result to
 * correct or delete. A result belongs to the athlete, not a program, so the
 * history runs through every block they have trained.
 */
export function StandardDetailSheet({ open, onOpenChange, standard }: SheetProps) {
  const { data: results } = useStandardResults()
  const log = useLogResult()
  const result = standard ? results?.standards[standard.id] : undefined
  const entries = (standard ? result?.entries : results?.bodyweight?.entries) ?? []
  const benchmarkId = standard?.id ?? 'bodyweight_kg'
  const newestFirst = [...entries].reverse()

  return (
    <Sheet open={open} onOpenChange={(o) => { onOpenChange(o); if (!o) log.reset() }}>
      <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>{standard?.name ?? 'Bodyweight'}</SheetTitle>
          <SheetDescription>
            {standard
              ? <>{standard.categoryName ?? standard.category}{standard.lower_is_better ? ' · lower is better' : ''}</>
              : <>Every weight you have logged. The ×BW standards read the one on or before each result's day.</>}
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 space-y-6 pb-8">
          {standard && (standard.testProtocol || standard.description || standard.notes) && (
            <div className="space-y-1 text-xs text-muted-foreground">
              {standard.description && <p>{standard.description}</p>}
              {standard.testProtocol && <p><span className="font-medium text-foreground">How to test: </span>{standard.testProtocol}</p>}
              {standard.notes && <p>{standard.notes}</p>}
            </div>
          )}

          {standard && (
            <div className="space-y-2">
              {result ? (
                <p className="text-sm">
                  <span className="font-semibold tabular-nums">{result.current.valueText}</span>{' '}
                  <StandardLevelBadge level={result.current.level} domain={standard.domain} />
                  <span className="text-xs text-muted-foreground">
                    {result.current.date && <> · {dayText(result.current.date)}</>}
                    {result.best.value !== result.current.value && <> · best {result.best.valueText}</>}
                    {result.current.next && result.current.gapText && <> · {result.current.gapText} to {result.current.next}</>}
                  </span>
                </p>
              ) : (
                <p className="text-xs text-muted-foreground">No result yet.</p>
              )}
              <StandardLadder thresholds={thresholdTexts(standard.standardsText, standard.standards, standard.unit)}
                              levelIndex={result ? result.current.levelIndex : undefined} domain={standard.domain} />
            </div>
          )}

          {entries.length > 0 && (
            <StandardHistoryChart entries={entries} domain={standard?.domain} blocks={results?.blocks}
              thresholds={standard?.standards} thresholdText={standard?.standardsText} />
          )}

          <section className="space-y-2">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Log a result</h3>
            <ResultForm key={log.data?.id ?? 'new'} standard={standard} submitLabel="Log" pending={log.isPending}
              error={log.error?.message ?? null} onSubmit={(input) => log.mutate({ benchmarkId, ...input })} />
          </section>

          {newestFirst.length > 0 && (
            <section className="space-y-1">
              <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                History · {newestFirst.length} result{newestFirst.length === 1 ? '' : 's'}
              </h3>
              <ul className="divide-y divide-border/40">
                {newestFirst.map((e) => <EntryRow key={e.id ?? e.date} entry={e} standard={standard} />)}
              </ul>
            </section>
          )}
        </div>
      </SheetContent>
    </Sheet>
  )
}
