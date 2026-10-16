import { useMemo, useState } from 'react'
import type { ModalityId, PhaseSummary, PhaseSummaryItem } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { SessionsPerWeekRows } from '@/components/explore/SessionsPerWeekRows'
import { cn } from '@/lib/utils'

// How a program's sessions and exercises change from phase to phase. Every
// number here is the server's (`phase_summary`, src/phase_summary.py); the
// phone lays out the same document, so nothing is counted in the browser.

const modalityHex = (m: string) => MODALITY_COLORS[m as ModalityId]?.hex ?? '#6366f1'
const modalityLabel = (m: string) => MODALITY_COLORS[m as ModalityId]?.label ?? m.replace(/_/g, ' ')

/** The summary for the i-th phase segment. Both are the program's phases in
 *  order; week numbers cannot be compared, because the calendar counts weeks
 *  from 1 while `week_number` may start later (an event-date program, or a
 *  regenerate that kept its head). */
export function findPhaseSummary(
  summaries: PhaseSummary[] | undefined, index: number, segmentCount: number,
): PhaseSummary | undefined {
  if (!summaries || summaries.length !== segmentCount) return undefined
  return summaries[index]
}

function kg(n: number) {
  return `${Number.isInteger(n) ? n : n.toFixed(1)} kg`
}

/** Inside a phase's "Your Program" card: its weekly shape, what changed from
 *  the phase before, and where the loaded lifts start and finish. */
export function PhaseChangeList({ summary }: { summary: PhaseSummary }) {
  const added = summary.archetypes.filter((a) => a.status === 'new')
  const gone = summary.dropped.archetypes
  return (
    <div className="space-y-3">
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-1.5">
          Weekly shape
        </div>
        <SessionsPerWeekRows sessionsPerWeek={summary.sessions_per_week} />
      </div>

      {summary.changes.length > 0 && (
        <div>
          <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-1">
            What changes
          </div>
          <ul className="space-y-0.5">
            {summary.changes.map((c) => (
              <li key={c} className="text-xs text-muted-foreground leading-snug flex gap-1.5">
                <span aria-hidden="true" className="text-muted-foreground/50">›</span>{c}
              </li>
            ))}
          </ul>
        </div>
      )}

      {(added.length > 0 || gone.length > 0) && (
        <div className="flex flex-wrap gap-1">
          {added.map((a) => (
            <span key={a.id} className="text-[10px] px-1.5 py-0.5 rounded-md border font-medium"
              style={{ borderColor: `${modalityHex(a.modality)}66`, color: modalityHex(a.modality) }}>
              + {a.name}
            </span>
          ))}
          {gone.map((a) => (
            <span key={a.id} className="text-[10px] px-1.5 py-0.5 rounded-md border border-dashed text-muted-foreground line-through">
              {a.name}
            </span>
          ))}
        </div>
      )}

      {summary.lifts.length > 0 && (
        <div>
          <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-1">
            Lifts
          </div>
          <div className="space-y-0.5">
            {summary.lifts.slice(0, 5).map((l) => (
              <div key={l.id} className="flex items-center justify-between gap-2 text-xs">
                <span className="truncate text-foreground">{l.name}</span>
                <span className="tabular-nums text-muted-foreground shrink-0">
                  {l.first_kg === l.last_kg ? kg(l.last_kg) : <>{kg(l.first_kg)} → {kg(l.last_kg)}</>}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

interface MatrixRow { id: string; name: string; modality: string; perWeek: (number | null)[] }

function matrixRows(summaries: PhaseSummary[], key: 'archetypes' | 'exercises'): MatrixRow[] {
  const rows = new Map<string, MatrixRow>()
  summaries.forEach((s, i) => {
    s[key].forEach((item: PhaseSummaryItem) => {
      let row = rows.get(item.id)
      if (!row) {
        row = { id: item.id, name: item.name, modality: item.modality, perWeek: summaries.map(() => null) }
        rows.set(item.id, row)
      }
      row.perWeek[i] = Math.round((item.sessions / Math.max(1, s.weeks)) * 10) / 10
    })
  })
  // Grouped by modality, each group in order of first appearance.
  const order = [...rows.values()]
  const modOrder = [...new Set(order.map((r) => r.modality))]
  return order.sort((a, b) => modOrder.indexOf(a.modality) - modOrder.indexOf(b.modality))
}

const COLLAPSED_ROWS = 14

/** Every archetype (or exercise) against every phase: how often it appears per
 *  week. Reads across a row to see a session enter, grow, shrink and leave. */
export function PhaseMatrix({ summaries }: { summaries: PhaseSummary[] }) {
  const [view, setView] = useState<'archetypes' | 'exercises'>('archetypes')
  const [expanded, setExpanded] = useState(false)
  const rows = useMemo(() => matrixRows(summaries, view), [summaries, view])
  if (summaries.length < 2) return null
  const max = Math.max(1, ...rows.flatMap((r) => r.perWeek.map((v) => v ?? 0)))
  const shown = expanded ? rows : rows.slice(0, COLLAPSED_ROWS)

  return (
    <div>
      <div className="flex items-end justify-between gap-3 mb-3">
        <div>
          <h2 className="text-sm font-semibold">How the phases change</h2>
          <p className="text-xs text-muted-foreground">
            Times per week each {view === 'archetypes' ? 'session' : 'exercise'} appears in each phase.
          </p>
        </div>
        <div role="tablist" className="flex rounded-md border p-0.5 text-[11px] shrink-0">
          {(['archetypes', 'exercises'] as const).map((v) => (
            <button key={v} role="tab" aria-selected={view === v}
              onClick={() => { setView(v); setExpanded(false) }}
              className={cn('px-2 py-0.5 rounded', view === v ? 'bg-muted text-foreground' : 'text-muted-foreground')}>
              {v === 'archetypes' ? 'Sessions' : 'Exercises'}
            </button>
          ))}
        </div>
      </div>
      <div className="rounded-xl border bg-card overflow-x-auto">
        <table className="w-full text-xs border-collapse">
          <thead>
            <tr className="border-b">
              <th className="text-left font-medium text-muted-foreground px-3 py-2 sticky left-0 bg-card min-w-40">
                {view === 'archetypes' ? 'Session' : 'Exercise'}
              </th>
              {summaries.map((s) => (
                <th key={`${s.phase_id}-${s.week_start}`} className="px-2 py-2 font-semibold text-center whitespace-nowrap"
                  style={{ color: PHASE_COLORS[s.kind]?.hex }}>
                  {s.name}
                  <div className="text-[9px] font-normal text-muted-foreground">
                    {s.weeks} {s.weeks === 1 ? 'week' : 'weeks'}
                  </div>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {shown.map((row) => (
              <tr key={row.id} className="border-b last:border-b-0">
                <td className="px-3 py-1.5 sticky left-0 bg-card">
                  <div className="flex items-center gap-1.5 min-w-0">
                    <span className="inline-block size-1.5 rounded-full shrink-0"
                      style={{ backgroundColor: modalityHex(row.modality) }}
                      title={modalityLabel(row.modality)} />
                    <span className="truncate">{row.name}</span>
                  </div>
                </td>
                {row.perWeek.map((v, i) => (
                  <td key={i} className="px-2 py-1.5 text-center tabular-nums">
                    {v == null ? (
                      <span className="text-muted-foreground/30">·</span>
                    ) : (
                      <span className="inline-block min-w-8 rounded px-1 py-0.5 text-[11px] font-medium"
                        style={{
                          backgroundColor: `${modalityHex(row.modality)}${Math.round(0x22 + (0x66 - 0x22) * (v / max)).toString(16)}`,
                        }}>
                        {v}
                      </span>
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {rows.length > COLLAPSED_ROWS && (
        <button onClick={() => setExpanded((e) => !e)}
          className="mt-1 text-[11px] text-muted-foreground hover:text-foreground">
          {expanded ? 'Show fewer' : `Show all ${rows.length}`}
        </button>
      )}
    </div>
  )
}
