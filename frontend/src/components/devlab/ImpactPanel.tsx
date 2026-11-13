import { useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { Play } from 'lucide-react'
import { apiClient } from '@/api/client'
import { buildPostBody, type GenerateParams } from '@/api/programs'
import type { ConstraintImpact, ImpactChange, ImpactSessionView } from '@/api/types'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import { equipmentLabel } from '@/lib/equipment'

// Dev Lab ▸ Impact (roadmap 20.12; item 9, step 6): what each of the athlete's
// constraints changes in a program, against the same request with nothing in
// the way — the packages' equipment, no injuries, the framework's level — and
// once per constraint lifted alone (POST /api/dev/constraint-impact,
// src/constraint_impact.py: up to seven generations, twelve weeks). The
// preview's "Held back" is the athlete's reading of the same answer; this is
// the developer's: every change with its causes, session by session.

const CAUSES = ['equipment', 'injury', 'level', 'proficiency'] as const
const CAUSE_LABEL: Record<string, string> = {
  equipment: 'Equipment', injury: 'Injuries', level: 'Level', proficiency: 'Proficiency',
  combined: 'Several together', knock_on: 'Knock-on', schedule: 'Schedule',
}

const words = (id: string | null | undefined) => (id ?? '').replace(/_/g, ' ')

function view(v: ImpactSessionView | null): string {
  if (!v) return 'nothing'
  return `${v.archetype?.name ?? words(v.modality)}${v.test ? ' (test)' : ''}`
}

function causesOf(change: ImpactChange): string[] {
  const own = [...(change.causes ?? []), ...(change.why ?? []).map((w) => w.cause)]
  const slots = (change.slots ?? []).flatMap((s) => [...s.causes, ...s.why.map((w) => w.cause)])
  return [...new Set([...own, ...slots])]
}

function ChangeRow({ change }: { change: ImpactChange }) {
  const causes = causesOf(change)
  return (
    <li className="rounded-md border border-border/60 p-2.5 space-y-1.5 text-xs">
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="font-mono text-[10px] text-muted-foreground">W{change.week_number} {change.day}</span>
        <Badge variant="outline" className="text-[10px]">{change.change}</Badge>
        {change.knock_on && <Badge variant="outline" className="text-[10px] text-muted-foreground">knock-on</Badge>}
        {causes.map((c) => <Badge key={c} variant="secondary" className="text-[10px]">{CAUSE_LABEL[c] ?? words(c)}</Badge>)}
      </div>
      {change.change !== 'slots' && (
        <p>
          <span className="text-muted-foreground">{view(change.reference)}</span>
          {' → '}
          <span>{view(change.actual)}</span>
        </p>
      )}
      {(change.why ?? []).map((w, i) => <p key={i} className="text-muted-foreground">{w.text}</p>)}
      {(change.slots ?? []).length > 0 && (
        <ul className="space-y-0.5 pl-3 border-l border-border">
          {change.slots!.map((s) => (
            <li key={s.index}>
              <span className="font-mono text-[10px] text-muted-foreground">{s.role ?? `slot ${s.index}`}</span>{' '}
              {s.from?.name ?? 'empty'} → {s.kind === 'emptied' ? 'left empty' : s.to?.name ?? 'empty'}
              {s.why.length > 0 && <span className="text-muted-foreground"> — {s.why.map((w) => w.text).join('; ')}</span>}
            </li>
          ))}
        </ul>
      )}
    </li>
  )
}

export function ImpactResult({ impact }: { impact: ConstraintImpact }) {
  const [cause, setCause] = useState<string | null>(null)
  const [knockOn, setKnockOn] = useState(false)
  const changes = impact.changes ?? []
  const shown = changes.filter((c) => (knockOn || !c.knock_on) && (!cause || causesOf(c).includes(cause)))
  const lifts = impact.lifts ?? {}

  if (impact.feasible && impact.reference_generates === false) {
    return <p className="text-sm text-muted-foreground">The reference does not generate: {impact.detail}</p>
  }
  if (!impact.feasible) {
    const unblocked = impact.unblocked_by ?? []
    return (
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-sm">The request is refused</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-xs">
          {impact.refused?.detail && <p className="text-muted-foreground">{impact.refused.detail}</p>}
          {(impact.refused?.validation?.errors ?? []).map((e, i) => (
            <p key={i}><span className="font-mono text-[10px]">{e.code}</span> {e.message}</p>
          ))}
          {impact.reference_generates === false && (
            <p className="text-muted-foreground">
              The same request with nothing else in the way is refused too: the reason is not equipment, injuries or level.
            </p>
          )}
          <p className="font-medium pt-1">What alone would let it generate</p>
          {unblocked.length
            ? <ul className="list-disc pl-4 space-y-0.5">{unblocked.map((u, i) => (
              <li key={i}><Badge variant="secondary" className="text-[10px] mr-1.5">{CAUSE_LABEL[u.cause] ?? words(u.cause)}</Badge>{u.text}</li>
            ))}</ul>
            : <p className="text-muted-foreground">No single constraint: lifting any one alone still refuses it.</p>}
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-sm">Against the program with nothing in the way</CardTitle></CardHeader>
        <CardContent className="space-y-3 text-xs">
          <p>
            <span className="font-mono">{impact.sessions?.changed ?? 0}</span> of{' '}
            <span className="font-mono">{impact.sessions?.total ?? 0}</span> sessions change
            {typeof impact.sessions?.direct === 'number' && <> — <span className="font-mono">{impact.sessions.direct}</span> directly, the rest because an earlier change moved the rotation</>}.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="text-left text-muted-foreground">
                  <th className="pb-1 pr-3 font-normal">Constraint</th>
                  <th className="pb-1 pr-3 font-normal">Lifted, it is</th>
                  <th className="pb-1 pr-3 font-normal text-right">Sessions</th>
                  <th className="pb-1 pr-3 font-normal text-right">Slots</th>
                  <th className="pb-1 font-normal text-right">Knock-on</th>
                </tr>
              </thead>
              <tbody>
                {CAUSES.map((c) => {
                  const t = impact.totals?.[c]
                  const lifted = (impact.lifted ?? []).includes(c)
                  return (
                    <tr key={c} className="border-t border-border/20">
                      <td className="py-1 pr-3">{CAUSE_LABEL[c]}</td>
                      <td className="py-1 pr-3 text-muted-foreground">{lifted ? lifts[c] ?? 'lifted' : 'nothing to lift'}</td>
                      <td className="py-1 pr-3 text-right font-mono">{t?.sessions ?? 0}</td>
                      <td className="py-1 pr-3 text-right font-mono">{t?.slots ?? 0}</td>
                      <td className="py-1 text-right font-mono">{t?.knock_on ?? 0}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          {(impact.restore?.equipment ?? []).length > 0 && (
            <div>
              <p className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground mb-1">
                The equipment that would restore the most
              </p>
              <div className="flex flex-wrap gap-1.5">
                {impact.restore!.equipment!.map((r) => (
                  <Badge key={r.id} variant="outline" className="text-[10px]">{equipmentLabel(r.id)} · {r.changes}</Badge>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-xs text-muted-foreground">Changes caused by:</span>
          {[null, ...CAUSES, 'combined'].map((c) => (
            <button
              key={c ?? 'all'}
              aria-pressed={cause === c}
              onClick={() => setCause(c)}
              className={cn('rounded border px-2 py-0.5 text-xs transition-colors',
                cause === c ? 'border-primary/40 bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}
            >
              {c ? CAUSE_LABEL[c] : 'Any'}
            </button>
          ))}
          <label className="ml-auto flex items-center gap-1.5 text-xs text-muted-foreground">
            <input type="checkbox" checked={knockOn} onChange={(e) => setKnockOn(e.target.checked)} />
            with knock-on changes
          </label>
        </div>
        {shown.length
          ? <ul className="space-y-1.5">{shown.map((c) => <ChangeRow key={`${c.week_index}-${c.day}-${c.session_index}`} change={c} />)}</ul>
          : <p className="text-xs text-muted-foreground">
              {changes.length ? 'No change with that cause.' : 'The constraints change nothing: this is the program the package writes with nothing in the way.'}
            </p>}
      </div>
    </div>
  )
}

/** `params` is the Pipeline Trace form's request; null until a philosophy is picked. */
export function ImpactPanel({ params }: { params: GenerateParams | null }) {
  const run = useMutation({
    mutationFn: (p: GenerateParams) =>
      apiClient.post('/dev/constraint-impact', buildPostBody(p), { timeout: 180_000 }) as unknown as Promise<ConstraintImpact>,
  })
  return (
    <div className="px-6 py-4 max-w-5xl space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Button size="sm" className="h-8" disabled={!params} loading={run.isPending} onClick={() => params && run.mutate(params)}>
          <Play className="size-3" />
          Compare
        </Button>
        <p className="text-xs text-muted-foreground max-w-2xl">
          The request above, generated against a reference with nothing in the way and once per constraint lifted
          alone: equipment, injuries, level, proficiency. Up to seven generations and twelve weeks — about ten
          seconds.
        </p>
      </div>
      {run.isError && (
        <p className="text-xs text-destructive">
          The comparison failed. It needs the local API (or AUTHORING_ENABLED):{' '}
          <code className="bg-muted px-1 rounded">POST /api/dev/constraint-impact</code>.
        </p>
      )}
      {run.data && <ImpactResult impact={run.data} />}
    </div>
  )
}
