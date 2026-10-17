import { Link } from 'react-router-dom'
import { format } from 'date-fns'
import { Trophy } from 'lucide-react'
import type { GeneratedProgram } from '@/api/types'
import { useStandardResults, useStandards } from '@/api/standards'
import { StandardLevelBadge } from '@/components/standards/StandardLadder'

/**
 * Today, when a session tests the phase's standards: each standard, where the
 * athlete stands, and the number to beat for the next level. Nothing on other
 * days — the card exists only when there is a test to show up for.
 */
export function TestDayCard({ program, weekIndex }: { program: GeneratedProgram; weekIndex: number }) {
  const today = format(new Date(), 'EEEE')
  const week = program.weeks[weekIndex]
  const tests = (week?.schedule[today] ?? []).map((s, i) => ({ s, i })).filter(({ s }) => s.test)
  const { data: standards = [] } = useStandards()
  const { data: results } = useStandardResults()
  if (!week || tests.length === 0) return null
  const byId = new Map(standards.map((s) => [s.id, s]))
  return (
    <div className="rounded-lg border border-primary/40 bg-card p-4 space-y-3">
      <div className="flex items-center gap-2">
        <Trophy className="size-4 text-primary" aria-hidden="true" />
        <p className="text-sm font-semibold">Test today</p>
      </div>
      {tests.map(({ s, i }) => (
        <div key={i} className="space-y-2">
          <Link to={`/program/${week.week_number}/${today}`} className="text-sm font-medium hover:underline underline-offset-2">
            {s.archetype?.name ?? 'Test'}
          </Link>
          {s.test?.instead_of?.name && (
            <p className="text-[11px] text-muted-foreground">In place of {s.test.instead_of.name}. Log each result after the session.</p>
          )}
          <ul className="space-y-1.5">
            {(s.test?.standards ?? []).map((id) => {
              const b = byId.get(id)
              const r = results?.standards[id]
              return (
                <li key={id} className="flex flex-wrap items-center justify-between gap-2 text-xs">
                  <Link to={`/profile?tab=standards&standard=${id}`} className="hover:underline underline-offset-2">{b?.name ?? id}</Link>
                  <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                    {r ? (
                      <>
                        <span className="font-semibold tabular-nums text-foreground">{r.best.valueText}</span>
                        <span>best</span>
                        <StandardLevelBadge level={r.best.level} domain={b?.domain} />
                        {r.current.next && r.current.nextText && <span>· {r.current.nextText} for {r.current.next}</span>}
                      </>
                    ) : (
                      <span>First result{b?.standardsText?.entry ? ` · ${b.standardsText.entry} for entry` : ''}</span>
                    )}
                  </span>
                </li>
              )
            })}
          </ul>
        </div>
      ))}
    </div>
  )
}
