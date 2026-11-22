import { Link } from 'react-router-dom'
import { ArrowUpRight, CheckCircle2, Circle, CircleHelp, Flag, History, Trophy, XCircle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import type { BriefingOccurrence, BriefingStatus } from '@/api/briefing'
import { rowSeries, rowSeriesSummary, sessionPath, type BriefingRow } from '@/lib/briefing'

const STATUS: Record<BriefingStatus, { label: string; icon: typeof Circle; className: string }> = {
  clean: { label: 'Clean', icon: CheckCircle2, className: 'text-done' },
  made: { label: 'Made', icon: CheckCircle2, className: 'text-done' },
  missed: { label: 'Missed', icon: XCircle, className: 'text-bad' },
  logged: { label: 'Logged', icon: Circle, className: 'text-muted-foreground' },
  unconfirmed: { label: 'Not confirmed', icon: CircleHelp, className: 'text-warn' },
}

const SUGGESTION_ICON: Record<string, typeof Circle> = {
  confirm_pending: CircleHelp, next_step: ArrowUpRight, next_load: ArrowUpRight, cycle_end: Flag,
  beat_last: Trophy, standard_target: Trophy,
}

interface BriefingHistorySheetProps {
  /** The row whose history is shown; null closes the sheet. */
  row: BriefingRow | null
  hex: string
  /** The sessions the briefing asks to confirm first. */
  pending: string[]
  onClose: () => void
}

/**
 * Everything behind one row of the briefing (frontend-design §13.10): today's
 * numbers, the cycle, the run as a chart, the standard, and every earlier time
 * with its day and what was done, newest first. A session still to confirm
 * links to its page.
 */
export function BriefingHistorySheet({ row, hex, pending, onClose }: BriefingHistorySheetProps) {
  const item = row?.item
  const Icon = item?.suggestion ? SUGGESTION_ICON[item.suggestion.kind] ?? History : History
  return (
    <Sheet open={!!row} onOpenChange={(open) => { if (!open) onClose() }}>
      <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-lg">
        {row && item && (
          <>
            <SheetHeader>
              <SheetTitle>{row.name}</SheetTitle>
              <SheetDescription>{row.header && row.header !== row.name ? `${row.header} · ${row.caption}` : row.caption}</SheetDescription>
            </SheetHeader>
            <div className="mt-4 space-y-4">
              <p className="text-2xl font-bold tabular-nums leading-tight">
                <span className="sr-only">Today: </span>{row.todayText}
              </p>
              {item.cycle && (
                <div className="space-y-1.5">
                  <p className="text-xs tabular-nums text-muted-foreground">{item.cycle.text}</p>
                  {item.cycle.of > 1 && (
                    <div role="progressbar" aria-label={item.cycle.text} aria-valuemin={0} aria-valuemax={item.cycle.of}
                         aria-valuenow={item.cycle.step} className="h-1 overflow-hidden rounded-full bg-muted">
                      <div className="h-full rounded-full" style={{ width: `${(100 * item.cycle.step) / item.cycle.of}%`, backgroundColor: hex }} />
                    </div>
                  )}
                </div>
              )}
              {item.suggestion && (
                <p className={cn('flex items-start gap-2 text-sm', item.suggestion.kind === 'confirm_pending' && 'text-warn')}>
                  <Icon aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
                  <span>{item.suggestion.text}</span>
                </p>
              )}
              {item.standard && (item.standard.best || item.standard.target) && (
                <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Trophy aria-hidden="true" className="size-3.5 text-primary" />
                  {[item.standard.best && `Best ${item.standard.best}`, item.standard.target].filter(Boolean).join(' · ')}
                </p>
              )}
              <Series row={row} hex={hex} />
              <section aria-label="Earlier sessions" className="space-y-2">
                <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {row.run.length ? `Earlier sessions · ${row.run.length}` : 'Earlier sessions'}
                </h4>
                {row.run.length ? (
                  <ul className="space-y-1.5">
                    {[...row.run].reverse().map((o, i) => (
                      <Occurrence key={`${o.date}-${i}`} occurrence={o}
                                  confirm={o.sessionKey && pending.includes(o.sessionKey) ? sessionPath(o.sessionKey) : null} />
                    ))}
                  </ul>
                ) : <p className="text-sm text-muted-foreground">The first time on record.</p>}
              </section>
              {item.notes && <p className="text-xs text-muted-foreground">{item.notes}</p>}
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  )
}

function Occurrence({ occurrence, confirm }: { occurrence: BriefingOccurrence; confirm: string | null }) {
  const status = STATUS[occurrence.status] ?? STATUS.logged
  const day = occurrence.dayText.charAt(0).toUpperCase() + occurrence.dayText.slice(1)
  return (
    <li className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
      <span className="flex items-center gap-1.5">
        <status.icon aria-hidden="true" className={cn('size-3.5', status.className)} />
        <span>{day}</span>
        <span className="sr-only">{status.label}</span>
        {occurrence.isDeload && <span className="text-xs text-muted-foreground">Deload</span>}
      </span>
      <span className="flex items-baseline gap-2">
        <span className="tabular-nums text-muted-foreground">{occurrence.text}</span>
        {confirm && <Link to={confirm} className="text-xs font-semibold text-primary hover:underline">Confirm</Link>}
      </span>
    </li>
  )
}

/** One bar a session: the earlier ones done, today's as the plan in the modality colour. A long run scrolls. */
function Series({ row, hex }: { row: BriefingRow; hex: string }) {
  const points = rowSeries(row)
  if (!points.length) return null
  const max = Math.max(...points.map((p) => p.value), 1)
  return (
    <div role="img" aria-label={[row.metric?.label ?? 'Earlier sessions', rowSeriesSummary(row)].filter(Boolean).join('. ')}
         className="overflow-x-auto" dir="rtl">
      <div dir="ltr" className="flex h-24 items-end gap-2">
        {points.map((p, i) => (
          <div key={i} aria-hidden="true" className="flex h-full min-w-6 flex-1 flex-col items-center justify-end gap-0.5">
            <span className={cn('text-[10px] tabular-nums', p.planned ? 'font-semibold' : 'text-muted-foreground')}>
              {Math.round(p.value * 10) / 10}
            </span>
            <div className={cn('w-full max-w-10 rounded-sm', !p.planned && 'bg-done', p.isDeload && 'opacity-50')}
                 style={{ height: `${Math.max(4, (76 * p.value) / max)}px`, ...(p.planned ? { backgroundColor: hex } : {}) }} />
          </div>
        ))}
      </div>
    </div>
  )
}
