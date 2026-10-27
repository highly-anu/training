import { useState } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle, Loader2, Sparkles } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { usePhilosophyForMe } from '@/api/philosophyCompare'
import { useAuthStore } from '@/store/authStore'
import { cn } from '@/lib/utils'
import type { CompareGlance, PhilosophyForMe } from '@/api/types'
import { IntensityBar, MixLegend, PhaseBar } from '../philosophy/Glance'
import { Cell, Row, SectionTitle, WideLine } from './CompareGrid'

const num = (n: number) => (Number.isInteger(n) ? `${n}` : n.toFixed(1))

/** One column's state while the runs go one after another. */
function Pending({ waiting }: { waiting: boolean }) {
  return (
    <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
      {waiting ? 'Waiting…' : <><Loader2 className="size-3 animate-spin" /> Generating…</>}
    </span>
  )
}

/**
 * The comparison's For you rows: each philosophy's chosen track generated on
 * the athlete's profile (POST /philosophies/<id>/for-me), never saved. Asked
 * for, not run on load — each column is a whole program — and fetched one
 * column after another.
 */
export function ForYouSection({ cols, trackOf }: { cols: CompareGlance[]; trackOf: (g: CompareGlance) => string }) {
  const user = useAuthStore((s) => s.user)
  const [asked, setAsked] = useState(false)
  const results = usePhilosophyForMe(cols.map((g) => ({ id: g.id, trackId: trackOf(g) })), asked && !!user)

  if (!user) {
    return (
      <>
        <SectionTitle>For you</SectionTitle>
        <WideLine className="text-[11px] text-muted-foreground">Sign in to see what each would give you.</WideLine>
      </>
    )
  }
  if (!asked) {
    return (
      <>
        <SectionTitle>For you</SectionTitle>
        <WideLine className="flex flex-wrap items-center gap-3">
          <Button size="sm" onClick={() => setAsked(true)}>
            <Sparkles className="mr-1.5 size-3.5" /> See what each gives you
          </Button>
          <span className="text-[11px] text-muted-foreground">
            Builds each track on your profile — days, minutes, equipment, injuries. Nothing is saved.
          </span>
        </WideLine>
      </>
    )
  }

  const cell = (i: number, render: (r: PhilosophyForMe) => React.ReactNode, onlyFeasible = true) => {
    const q = results[i]
    if (q.error) return <span className="text-[11px] text-destructive">{(q.error as Error).message}</span>
    if (!q.data) return <Pending waiting={q.fetchStatus === 'idle'} />
    if (onlyFeasible && !q.data.feasible) return <span className="text-[11px] text-muted-foreground/50">—</span>
    return render(q.data)
  }
  const assumed = Array.from(new Set(results.flatMap((q) => q.data?.assumed.map((a) => a.text) ?? [])))

  return (
    <>
      <SectionTitle>For you</SectionTitle>
      {assumed.length > 0 && (
        <WideLine className="text-[11px] text-muted-foreground">
          Assumed: {assumed.join('; ')}.{' '}
          <Link to="/profile" className="underline hover:text-foreground">Set your profile</Link>
        </WideLine>
      )}
      <Row label="Runs for you">
        {cols.map((g, i) => (
          <Cell key={g.id}>
            {cell(i, (r) => r.feasible
              ? <span className="text-[11px]">
                  Yes — {r.trackName}, {r.weeks} wk
                  {r.trackWeeks && r.trackWeeks > r.ofWeeks ? ` of ${r.trackWeeks}` : ''}
                </span>
              : (
                <div className="space-y-1">
                  <span className="inline-flex items-center gap-1 text-[11px] font-medium text-amber-700 dark:text-amber-300">
                    <AlertTriangle className="size-3" /> Not as you are
                  </span>
                  <ul className="space-y-0.5">
                    {r.reasons.map((x, k) => (
                      <li key={k} className="text-[11px] text-muted-foreground">
                        {x.message}
                      </li>
                    ))}
                  </ul>
                </div>
              ), false)}
          </Cell>
        ))}
      </Row>
      <Row label="A week">
        {cols.map((g, i) => (
          <Cell key={g.id} className="font-mono tabular-nums">
            {cell(i, (r) => r.perWeek && (
              <span>
                {num(r.perWeek.days)} days · {num(r.perWeek.sessions)} sessions
                {r.perWeek.minutes != null && ` · ${r.perWeek.minutes}′`}
              </span>
            ))}
          </Cell>
        ))}
      </Row>
      <Row label="Mix">
        {cols.map((g, i) => (
          <Cell key={g.id}>
            {cell(i, (r) => <MixLegend mix={(r.mix ?? []).map((m) => ({ ...m, share: 0 }))} />)}
          </Cell>
        ))}
      </Row>
      <Row label="Easy → hard">
        {cols.map((g, i) => (
          <Cell key={g.id}>{cell(i, (r) => <IntensityBar split={r.intensity ?? {}} className="h-1.5" />)}</Cell>
        ))}
      </Row>
      <Row label="Phases">
        {cols.map((g, i) => (
          <Cell key={g.id}>
            {cell(i, (r) => (
              <div className="space-y-0.5">
                <PhaseBar phases={r.phases ?? []} scaleWeeks={r.weeks} height="h-2" />
                <p className="truncate text-[10px] text-muted-foreground">{(r.phases ?? []).map((p) => p.name).join(' → ')}</p>
              </div>
            ))}
          </Cell>
        ))}
      </Row>
      <Row label="Your kit">
        {cols.map((g, i) => (
          <Cell key={g.id} className="text-[11px]">
            {cell(i, (r) => (
              <div className="space-y-0.5">
                {r.missingEquipment.length > 0
                  ? <p className="text-muted-foreground">Lacks {r.missingEquipment.map((e) => e.name).join(', ')}</p>
                  : <p className="text-muted-foreground">Has all it asks for</p>}
                {(r.skippedForEquipment ?? 0) > 0 && (
                  <p className="text-muted-foreground/80">
                    Passes over {r.skippedForEquipment}{r.sessionCount ? ` of ${r.sessionCount}` : ''} sessions for it
                  </p>
                )}
              </div>
            ), false)}
          </Cell>
        ))}
      </Row>
      <Row label="Held back">
        {cols.map((g, i) => (
          <Cell key={g.id} className="text-[11px]">
            {cell(i, (r) => {
              const held = r.heldBack ?? { slots: 0, sessions: 0 }
              const subs = r.gaps?.substituted.length ?? 0
              const quiet = !held.sessions && !subs && !(r.warnings ?? []).length
              return (
                <div className={cn('space-y-0.5', quiet && 'text-muted-foreground')}>
                  {quiet ? 'Nothing' : (
                    <>
                      {held.sessions > 0 && <p>{held.sessions} session{held.sessions === 1 ? '' : 's'} with gaps ({held.slots} slot{held.slots === 1 ? '' : 's'})</p>}
                      {subs > 0 && <p>{subs} session{subs === 1 ? '' : 's'} swapped for another kind</p>}
                      {(r.warnings ?? []).map((w, k) => <p key={k} className="text-muted-foreground">{w.message}</p>)}
                    </>
                  )}
                </div>
              )
            })}
          </Cell>
        ))}
      </Row>
      <Row label="Tests">
        {cols.map((g, i) => (
          <Cell key={g.id} className="text-[11px]">
            {cell(i, (r) => {
              const t = r.tests ?? { placed: 0, skipped: [] }
              if (!t.placed && !t.skipped.length) return <span className="text-muted-foreground/50">—</span>
              return (
                <div className="space-y-0.5">
                  {t.placed > 0 && <p>{t.placed} placed</p>}
                  {t.skipped.map((s, k) => <p key={k} className="text-muted-foreground">Week {s.week} skipped: {s.why}</p>)}
                </div>
              )
            })}
          </Cell>
        ))}
      </Row>
    </>
  )
}
