import { useState } from 'react'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { useSessionBriefing, type BriefingStatus } from '@/api/briefing'
import { briefingRows, markHeight, rowLabel, saysSomething, stripMarks, type BriefingRow } from '@/lib/briefing'
import { modalityHex } from '@/lib/modalityColors'
import { BriefingHistorySheet } from '@/components/session/BriefingHistorySheet'

/** A mark's colour by how that time went; missed and not confirmed are outlined, the shape's twin. */
const MARK: Record<BriefingStatus, string> = {
  clean: 'bg-done', made: 'bg-done', logged: 'bg-muted-foreground',
  missed: 'border border-bad', unconfirmed: 'border border-warn',
}

interface SessionBriefingProps {
  /** The server's key for the session: "3-Monday-0". */
  sessionKey: string
  modality: string
}

/**
 * Before a session: one row an exercise — its name, today's numbers and a
 * strip with one mark for every earlier time it was done — and under it the
 * one suggestion (docs/frontend-design.md §13.10). A row opens its history:
 * the dated lines, the chart, the standard. The document is the server's; this
 * lays it out. Shown for a session still to do; one that adds nothing to the
 * prescription shows nothing.
 */
export function SessionBriefing({ sessionKey, modality }: SessionBriefingProps) {
  const query = useSessionBriefing(sessionKey)
  const [shown, setShown] = useState<string | null>(null)
  if (query.error && !query.data) {
    return <ErrorBanner error={query.error} title="Could not read your earlier sessions" onRetry={() => { void query.refetch() }} />
  }
  const briefing = query.data
  if (!briefing || !saysSomething(briefing)) return null
  const rows = briefingRows(briefing)
  const hex = modalityHex(modality)
  return (
    <section aria-label="Before you start" className="space-y-2">
      <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Before you start</h4>
      <div className="divide-y rounded-lg border bg-card">
        {rows.map((row) => <Row key={row.id} row={row} hex={hex} onOpen={() => setShown(row.id)} />)}
      </div>
      <BriefingHistorySheet row={rows.find((r) => r.id === shown) ?? null} hex={hex}
                            pending={briefing.pending.map((p) => p.sessionKey)} onClose={() => setShown(null)} />
    </section>
  )
}

function Row({ row, hex, onOpen }: { row: BriefingRow; hex: string; onOpen: () => void }) {
  return (
    <div className="space-y-1.5 px-4 py-3">
      {row.header && (
        <div className="flex flex-wrap items-baseline justify-between gap-x-3">
          <h5 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{row.header}</h5>
          {row.headerDetail && <span className="text-xs tabular-nums text-muted-foreground">{row.headerDetail}</span>}
        </div>
      )}
      <button type="button" onClick={onOpen} aria-label={`${rowLabel(row).replace(/\.$/, '')}. Shows every earlier session.`}
              className="block w-full space-y-1.5 rounded-md text-left hover:bg-muted/50 focus-visible:outline-2 focus-visible:outline-ring">
        <span className="flex flex-wrap items-baseline justify-between gap-x-3">
          <span className="text-sm font-semibold">{row.name}</span>
          <span className="text-sm font-semibold tabular-nums">{row.todayText}</span>
        </span>
        <span className="flex items-center gap-2">
          <Strip row={row} hex={hex} />
          <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{row.caption}</span>
          <ChevronRight aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
        </span>
        {row.suggestion && (
          <span className={cn('block text-xs', row.suggestion.kind === 'confirm_pending' ? 'text-warn' : 'text-muted-foreground')}>
            {row.suggestion.text}
          </span>
        )}
      </button>
    </div>
  )
}

/**
 * Every earlier time as one mark, oldest first, then today's as the plan in
 * the modality colour: height is the row's number, colour how it went. A run
 * longer than the strip shows its newest; the caption says how many there are.
 */
function Strip({ row, hex }: { row: BriefingRow; hex: string }) {
  const marks = stripMarks(row)
  const values = [...marks.map((m) => m.value), row.todayValue].filter((v): v is number => typeof v === 'number')
  const height = (value?: number) => `${Math.round(100 * markHeight(value, values))}%`
  return (
    <span aria-hidden="true" data-testid="briefing-strip" className="flex h-6 min-w-0 flex-1 items-end gap-0.5">
      {marks.map((m, i) => (
        <span key={i} data-status={m.status}
              className={cn('min-w-[3px] max-w-2.5 flex-1 rounded-[2px]', MARK[m.status] ?? MARK.logged, m.isDeload && 'opacity-50')}
              style={{ height: height(m.value) }} />
      ))}
      <span data-status="today" className="ml-1 min-w-[3px] max-w-2.5 flex-1 rounded-[2px]"
            style={{ height: height(row.todayValue), backgroundColor: hex }} />
    </span>
  )
}
