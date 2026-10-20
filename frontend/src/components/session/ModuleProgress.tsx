import { useState } from 'react'
import { BadgeCheck, MinusCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { confirmSession } from '@/api/health'
import { useBioStore } from '@/store/bioStore'
import type { Session } from '@/api/types'

interface Props {
  session: Session
  /** Where this session's log lives in the store (the day key for a day's first session). */
  logKey: string
  /** The session's full key ("3-Monday-0"), which the server resolves. */
  serverKey: string
}

/**
 * "Done as written" for a training-contract session. Wildman and BJJ: clean or
 * not, and the RPE — only a clean session at or below the module's RPE moves a
 * module on when the program is next rebuilt. Starting Strength: each lift made
 * or missed. A watch-recorded or linked workout logs no per-exercise outcome,
 * so without this none ever did.
 */
export function ModuleProgress(props: Props) {
  const byLoad = props.session.exercises.some(
    (ea) => ea.load?.advances_module && ea.exercise && ea.load.progression_model === 'load_per_exposure')
  return byLoad ? <LiftProgress {...props} /> : <CleanProgress {...props} />
}

/** "Done as written" for modules that move on clean, low-RPE sessions (Wildman, BJJ). */
function CleanProgress({ session, logKey, serverKey }: Props) {
  const progressing = session.exercises
    .filter((ea) => ea.load?.advances_module && ea.exercise)
    .map((ea) => ea.exercise!.id)
  const log = useBioStore((s) => s.sessionPerformanceLogs[logKey])
  const applyConfirmation = useBioStore((s) => s.applyConfirmation)
  const [rpe, setRpe] = useState(7)
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState(false)
  const [changing, setChanging] = useState(false)
  if (progressing.length === 0) return null

  const verdict = log?.exercises[progressing[0]]
  const answered = typeof verdict?.clean === 'boolean' && !changing

  async function confirm(clean: boolean) {
    setBusy(true)
    setFailed(false)
    try {
      const res = await confirmSession(serverKey, clean, rpe)
      applyConfirmation(logKey, res.exercises, res.completedAt)
      setChanging(false)
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="rounded-lg border bg-muted/30 p-4 space-y-3">
      <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Progress</h4>
      {answered ? (
        <div className="flex items-center justify-between gap-2 text-sm">
          {verdict!.clean ? (
            <span className="flex items-center gap-1.5 text-green-700 dark:text-green-400">
              <BadgeCheck className="size-4" />
              Clean, as written{verdict!.rpe != null ? ` · RPE ${verdict!.rpe}` : ''}
            </span>
          ) : (
            <span className="flex items-center gap-1.5 text-muted-foreground">
              <MinusCircle className="size-4" />
              Not clean — the cycle holds here
            </span>
          )}
          <button type="button" className="text-xs text-muted-foreground hover:underline" onClick={() => setChanging(true)}>
            Change
          </button>
        </div>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            Done as written? A clean session at RPE 7 or below moves each module on when the program is next rebuilt.
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-1.5 text-sm">
              RPE
              <select
                aria-label="RPE"
                className="h-8 rounded-md border bg-background px-2 text-sm"
                value={rpe}
                onChange={(e) => setRpe(Number(e.target.value))}
              >
                {Array.from({ length: 10 }, (_, i) => i + 1).map((v) => <option key={v} value={v}>{v}</option>)}
              </select>
            </label>
            <Button size="sm" disabled={busy} onClick={() => confirm(true)}>
              <BadgeCheck className="size-4 mr-1.5" /> Clean, as written
            </Button>
            <Button size="sm" variant="outline" disabled={busy} onClick={() => confirm(false)}>
              Not clean
            </Button>
          </div>
        </>
      )}
      {failed && <p className="text-xs text-red-600">Not saved — try again.</p>}
    </div>
  )
}

interface LiftAnswer { made: boolean; kg: string }

/**
 * A loaded lift moves on what was made (Starting Strength): each lift made or
 * missed, at its prescribed weight or the weight worked up to. A made lift
 * goes up next time; a miss repeats the weight, and two in a row reset it.
 */
function LiftProgress({ session, logKey, serverKey }: Props) {
  const lifts = session.exercises.filter(
    (ea) => ea.load?.advances_module && ea.exercise && ea.load.progression_model === 'load_per_exposure')
  const log = useBioStore((s) => s.sessionPerformanceLogs[logKey])
  const applyConfirmation = useBioStore((s) => s.applyConfirmation)
  const [answers, setAnswers] = useState<Record<string, LiftAnswer>>(() =>
    Object.fromEntries(lifts.map((ea) => [ea.exercise!.id, { made: true, kg: '' }])))
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState(false)
  const [changing, setChanging] = useState(false)

  const logged = lifts.map((ea) => log?.exercises[ea.exercise!.id])
  const answered = logged.every((p) => typeof p?.made === 'boolean') && !changing
  // A work-up made without its weight would leave the lift where it was.
  const unweighed = (allMade: boolean) => lifts.some((ea) => {
    const a = answers[ea.exercise!.id]
    return ea.load.weight_kg == null && (allMade || a.made) && !(Number(a.kg) > 0)
  })

  async function save(allMade: boolean) {
    setBusy(true)
    setFailed(false)
    const sent: Record<string, { made: boolean; weightKg?: number }> = {}
    for (const ea of lifts) {
      const a = answers[ea.exercise!.id]
      const kg = Number(a.kg)
      const made = allMade || a.made
      if (!made || (a.kg && kg > 0)) sent[ea.exercise!.id] = { made, ...(a.kg && kg > 0 ? { weightKg: kg } : {}) }
    }
    try {
      const everyMade = lifts.every((ea) => allMade || answers[ea.exercise!.id].made)
      const res = await confirmSession(serverKey, everyMade, undefined, Object.keys(sent).length ? sent : undefined)
      applyConfirmation(logKey, res.exercises, res.completedAt)
      setChanging(false)
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="rounded-lg border bg-muted/30 p-4 space-y-3">
      <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Progress</h4>
      {answered ? (
        <div className="space-y-1.5 text-sm">
          {lifts.map((ea, i) => (
            <div key={ea.exercise!.id} className="flex items-center gap-1.5">
              {logged[i]!.made ? (
                <BadgeCheck className="size-4 text-green-700 dark:text-green-400" />
              ) : (
                <MinusCircle className="size-4 text-muted-foreground" />
              )}
              <span>{ea.exercise!.name}</span>
              <span className="text-muted-foreground">
                {logged[i]!.weightKg != null ? `${logged[i]!.weightKg} kg` : ''}
                {logged[i]!.made ? '' : ' · missed, repeats'}
              </span>
            </div>
          ))}
          <button type="button" className="text-xs text-muted-foreground hover:underline" onClick={() => setChanging(true)}>
            Change
          </button>
        </div>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            Made every rep? A made lift goes up next time; a miss repeats its weight.
          </p>
          <div className="space-y-2">
            {lifts.map((ea) => {
              const id = ea.exercise!.id
              const a = answers[id]
              const set = (next: Partial<LiftAnswer>) => setAnswers((s) => ({ ...s, [id]: { ...s[id], ...next } }))
              return (
                <div key={id} className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="min-w-32 font-medium">{ea.exercise!.name}</span>
                  {ea.load.weight_kg != null ? (
                    <span className="text-muted-foreground">{ea.load.weight_kg} kg</span>
                  ) : (
                    <input
                      aria-label={`${ea.exercise!.name} kg`}
                      inputMode="decimal"
                      placeholder="kg"
                      className="h-8 w-20 rounded-md border bg-background px-2 text-sm"
                      value={a.kg}
                      onChange={(e) => set({ kg: e.target.value })}
                    />
                  )}
                  <div className="flex gap-1" role="group" aria-label={`${ea.exercise!.name} outcome`}>
                    <Button size="sm" variant={a.made ? 'default' : 'outline'} onClick={() => set({ made: true })}>Made</Button>
                    <Button size="sm" variant={a.made ? 'outline' : 'default'} onClick={() => set({ made: false })}>Missed</Button>
                  </div>
                </div>
              )
            })}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={busy || unweighed(true)} onClick={() => save(true)}>
              <BadgeCheck className="size-4 mr-1.5" /> All made
            </Button>
            <Button size="sm" variant="outline" disabled={busy || unweighed(false)} onClick={() => save(false)}>
              Save
            </Button>
          </div>
          {unweighed(false) && (
            <p className="text-xs text-muted-foreground">Enter the weight you worked up to on each lift you made.</p>
          )}
        </>
      )}
      {failed && <p className="text-xs text-red-600">Not saved — try again.</p>}
    </div>
  )
}
