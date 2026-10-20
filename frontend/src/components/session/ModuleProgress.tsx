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
 * "Done as written" for a training-contract session (Wildman, BJJ): clean or
 * not, and the RPE. Only a clean session at or below the module's RPE moves a
 * module on when the program is next rebuilt; a watch-recorded or linked
 * workout logs no per-exercise outcome, so without this none ever did.
 */
export function ModuleProgress({ session, logKey, serverKey }: Props) {
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
