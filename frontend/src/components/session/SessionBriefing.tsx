import { Link } from 'react-router-dom'
import { ArrowUpRight, CheckCircle2, Circle, CircleHelp, Flag, History, Trophy, XCircle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { useSessionBriefing, type BriefingItem, type BriefingOccurrence, type BriefingStatus } from '@/api/briefing'
import { briefingSeries, briefingSeriesSummary, saysSomething, sessionPath } from '@/lib/briefing'
import { modalityHex } from '@/lib/modalityColors'

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

interface SessionBriefingProps {
  /** The server's key for the session: "3-Monday-0". */
  sessionKey: string
  modality: string
}

/**
 * Before a session: per item of it, today's numbers, the suggestion, where it
 * stands in its cycle and the earlier times the same session was done
 * (docs/frontend-design.md §13.10). The document is the server's; this lays it
 * out. Shown for a session still to do; one that adds nothing to the
 * prescription shows nothing.
 */
export function SessionBriefing({ sessionKey, modality }: SessionBriefingProps) {
  const query = useSessionBriefing(sessionKey)
  if (query.error && !query.data) {
    return <ErrorBanner error={query.error} title="Could not read your earlier sessions" onRetry={() => { void query.refetch() }} />
  }
  const briefing = query.data
  if (!briefing || !saysSomething(briefing)) return null
  return (
    <section aria-label="Before you start" className="space-y-2">
      <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Before you start</h4>
      {briefing.pending.map((p) => {
        const to = sessionPath(p.sessionKey)
        return (
          <div key={p.sessionKey} className="flex items-center gap-2 rounded-lg border border-warn/40 bg-warn/5 px-3 py-2 text-sm">
            <CircleHelp aria-hidden="true" className="size-4 shrink-0 text-warn" />
            <span className="flex-1">{p.text}</span>
            {to && <Link to={to} className="shrink-0 text-xs font-semibold text-primary hover:underline">Confirm</Link>}
          </div>
        )
      })}
      {briefing.items.map((item) => <Item key={item.id} item={item} hex={modalityHex(modality)} />)}
    </section>
  )
}

function Item({ item, hex }: { item: BriefingItem; hex: string }) {
  const Icon = item.suggestion ? SUGGESTION_ICON[item.suggestion.kind] ?? History : History
  const several = item.today.lines.length > 1 && new Set(item.today.lines.map((l) => l.text)).size > 1
  return (
    <div className="space-y-3 rounded-lg border bg-card p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h5 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{item.title}</h5>
        {item.cycle && <span className="text-xs tabular-nums text-muted-foreground">{item.cycle.text}</span>}
      </div>
      {several ? (
        <ul className="space-y-1 text-sm">
          {item.today.lines.map((l) => (
            <li key={l.exerciseId} className="flex flex-wrap justify-between gap-x-3">
              <span>{l.name}</span>
              <span className="font-semibold tabular-nums">{l.text}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-2xl font-bold tabular-nums leading-tight">
          <span className="sr-only">Today: </span>{item.today.lines[0]?.text ?? item.today.text}
        </p>
      )}
      {item.suggestion && (
        <p className={cn('flex items-start gap-2 text-sm', item.suggestion.kind === 'confirm_pending' && 'text-warn')}>
          <Icon aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
          <span>{item.suggestion.text}</span>
        </p>
      )}
      {item.cycle && item.cycle.of > 1 && (
        <div role="progressbar" aria-label={item.cycle.text} aria-valuemin={0} aria-valuemax={item.cycle.of}
             aria-valuenow={item.cycle.step} className="h-1 overflow-hidden rounded-full bg-muted">
          <div className="h-full rounded-full" style={{ width: `${(100 * item.cycle.step) / item.cycle.of}%`, backgroundColor: hex }} />
        </div>
      )}
      <Series item={item} hex={hex} />
      {item.history.length > 0 ? (
        <ul className="space-y-1">
          {[...item.history].reverse().map((h) => <Occurrence key={`${h.date}-${h.sessionKey ?? h.text}`} occurrence={h} />)}
        </ul>
      ) : item.times === 0 && <p className="text-xs text-muted-foreground">The first time on record.</p>}
      {item.standard && (item.standard.best || item.standard.target) && (
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Trophy aria-hidden="true" className="size-3.5 text-primary" />
          {[item.standard.best && `Best ${item.standard.best}`, item.standard.target].filter(Boolean).join(' · ')}
        </p>
      )}
      {item.notes && <p className="text-xs text-muted-foreground">{item.notes}</p>}
    </div>
  )
}

function Occurrence({ occurrence }: { occurrence: BriefingOccurrence }) {
  const status = STATUS[occurrence.status] ?? STATUS.logged
  const day = occurrence.dayText.charAt(0).toUpperCase() + occurrence.dayText.slice(1)
  return (
    <li className="flex flex-wrap items-baseline justify-between gap-x-3 text-xs">
      <span className="flex items-center gap-1.5">
        <status.icon aria-hidden="true" className={cn('size-3.5', status.className)} />
        <span>{day}</span>
        <span className="sr-only">{status.label}</span>
        {occurrence.isDeload && <span className="text-muted-foreground">Deload</span>}
      </span>
      <span className="tabular-nums text-muted-foreground">{occurrence.text}</span>
    </li>
  )
}

/** One bar a session: the earlier ones done, today's as the plan in the modality colour. */
function Series({ item, hex }: { item: BriefingItem; hex: string }) {
  const points = briefingSeries(item)
  if (!points.length) return null
  const max = Math.max(...points.map((p) => p.value), 1)
  const summary = briefingSeriesSummary(item)
  return (
    <div role="img" aria-label={[item.metric?.label ?? 'Earlier sessions', summary].filter(Boolean).join('. ')}
         className="flex h-20 items-end gap-2">
      {points.map((p, i) => (
        <div key={i} aria-hidden="true" className="flex h-full flex-1 flex-col items-center justify-end gap-0.5">
          <span className={cn('text-[10px] tabular-nums', p.planned ? 'font-semibold' : 'text-muted-foreground')}>
            {Math.round(p.value * 10) / 10}
          </span>
          <div className={cn('w-full max-w-10 rounded-sm', !p.planned && 'bg-done', p.isDeload && 'opacity-50')}
               style={{ height: `${Math.max(4, (64 * p.value) / max)}px`, ...(p.planned ? { backgroundColor: hex } : {}) }} />
        </div>
      ))}
    </div>
  )
}
