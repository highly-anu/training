import { useMemo, useState } from 'react'
import { CalendarDays, ChevronDown, ChevronRight, CircleSlash, Dumbbell, GraduationCap, Loader2, Plus, ShieldAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { impactParams, useProgramImpact, type GenerateParams } from '@/api/programs'
import { heldBackSummary, idLabel } from '@/lib/heldBack'
import { cn } from '@/lib/utils'
import type { ConstraintImpact, GeneratedProgram, ImpactChange, ValidationResult } from '@/api/types'

/** The athlete can act on these from the panel; each re-previews. */
export interface HeldBackActions {
  addEquipment: (ids: string[]) => void
  clearInjuries: () => void
  setLevel: (level: string) => void
  editSchedule: () => void
}

interface HeldBackPanelProps {
  params: GenerateParams
  draft: GeneratedProgram
  actions: HeldBackActions
  busy?: boolean
}

const CAUSES = [
  { key: 'equipment', label: 'Equipment', icon: Dumbbell },
  { key: 'injury', label: 'Injuries', icon: ShieldAlert },
  { key: 'level', label: 'Level', icon: GraduationCap },
  { key: 'proficiency', label: 'Proficiency', icon: GraduationCap },
  { key: 'combined', label: 'More than one constraint', icon: CircleSlash },
] as const

/** The validator's schedule and time findings, which no lifted run explains. */
const SCHEDULE_CODES = /^(SCHEDULE_|INSUFFICIENT_DAYS|MINIMAL_DAYS|PHASE_DAYS_MISMATCH|SESSION_TIME_|SESSION_TOO_SHORT)/

function scheduleFindings(validation: ValidationResult | undefined, compromises: string[] | undefined): string[] {
  const out = [...(validation?.errors ?? []), ...(validation?.warnings ?? [])]
    .filter((v) => SCHEDULE_CODES.test(v.code) && v.code !== 'SCHEDULE_MEETS_IDEAL')
    .map((v) => v.message)
  for (const c of compromises ?? []) if (/days|volume|minutes|rest/i.test(c)) out.push(c)
  return [...new Set(out)]
}

/** The cause a change is filed under: its first direct one. */
function primaryCause(change: ImpactChange): string {
  const causes = change.causes ?? change.slots?.flatMap((s) => s.causes) ?? []
  return causes.find((c) => c !== 'combined') ?? causes[0] ?? 'combined'
}

function changeLine(change: ImpactChange): { title: string; detail: string[] } {
  const where = `Week ${change.week_number} · ${change.day}`
  if (change.change === 'slots') {
    const slots = (change.slots ?? []).filter((s) => !s.knock_on)
    return {
      title: `${where} · ${change.actual?.archetype?.name ?? change.reference?.archetype?.name ?? ''}`,
      detail: slots.map((s) => {
        const was = s.from?.name ?? idLabel(s.role ?? 'slot')
        const now = s.kind === 'emptied' ? 'left empty' : s.to ? `now ${s.to.name}` : ''
        const why = s.why.map((w) => w.text).join('; ')
        return `${was} ${now}${why ? ` — ${why}` : ''}`
      }),
    }
  }
  const ref = change.reference?.archetype?.name ?? (change.reference ? idLabel(change.reference.modality) : 'nothing')
  const act = change.actual?.archetype?.name ?? (change.actual ? idLabel(change.actual.modality) : 'nothing')
  return { title: `${where} · ${ref} → ${act}`, detail: (change.why ?? []).map((w) => w.text) }
}

/**
 * Held back: what the athlete's equipment, injuries, level and schedule
 * changed in this program, against the same request with nothing in the way
 * (POST /programs/impact — the Dev Lab's comparison), and what would restore
 * it. Loads after the draft is on screen; up to seven generations.
 */
export function HeldBackPanel({ params, draft, actions, busy }: HeldBackPanelProps) {
  const impact = useProgramImpact(impactParams(params, draft))
  const recorded = useMemo(() => heldBackSummary(draft), [draft])
  const schedule = scheduleFindings(draft.validation, draft.compromises)

  return (
    <div className="space-y-5">
      <section className="rounded-xl border bg-card p-4 space-y-1">
        <h3 className="text-sm font-semibold">In this program</h3>
        <p className="text-sm text-muted-foreground">
          {recorded.slots === 0 && recorded.sessions === 0
            ? 'No slot is left empty and no session runs in place of another.'
            : `${recorded.slots} exercise slot${recorded.slots === 1 ? '' : 's'} left empty across ${recorded.sessions} session${recorded.sessions === 1 ? '' : 's'}; open a session in the calendar for why.`}
        </p>
      </section>

      {schedule.length > 0 && (
        <section className="rounded-xl border bg-card p-4 space-y-2">
          <div className="flex items-center gap-2">
            <CalendarDays className="size-4 text-primary" aria-hidden="true" />
            <h3 className="text-sm font-semibold">Schedule</h3>
            <Button variant="outline" size="sm" className="ml-auto h-7 text-xs" onClick={actions.editSchedule}>
              Change schedule
            </Button>
          </div>
          <ul className="space-y-1 text-xs text-muted-foreground">
            {schedule.map((s) => <li key={s}>{s}</li>)}
          </ul>
        </section>
      )}

      {impact.isPending && (
        <section className="rounded-xl border bg-card p-4 space-y-3" aria-busy="true">
          <p className="inline-flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="size-4 animate-spin" aria-hidden="true" />
            Checking what your constraints change — this builds the program several ways (about 10 s).
          </p>
          <Skeleton className="h-4 w-2/3" />
          <Skeleton className="h-4 w-1/2" />
        </section>
      )}
      {impact.isError && (
        <p className="text-sm text-muted-foreground">
          Could not compare against the unconstrained program: {(impact.error as Error).message}
        </p>
      )}
      {impact.data && <ImpactSections impact={impact.data} actions={actions} busy={busy}
                                      weeksCompared={draft.weeks.length > 12 ? 12 : undefined} />}
    </div>
  )
}

function ImpactSections({ impact, actions, busy, weeksCompared }: {
  impact: ConstraintImpact; actions: HeldBackActions; busy?: boolean
  /** The comparison runs at most 12 weeks; set when the draft is longer. */
  weeksCompared?: number
}) {
  const [showKnockOn, setShowKnockOn] = useState(false)
  const changes = impact.changes ?? []
  const direct = changes.filter((c) => !c.knock_on)
  const knockOn = changes.filter((c) => c.knock_on)
  const restore = impact.restore?.equipment ?? []
  const lifts = impact.lifts ?? {}

  if (impact.reference_generates === false) {
    return <p className="text-sm text-muted-foreground">{impact.detail}</p>
  }

  return (
    <div className="space-y-5">
      {direct.length === 0 ? (
        <section className="rounded-xl border bg-card p-4">
          <p className="text-sm">
            Your constraints change nothing: this is the program the methodology writes with
            nothing in the way{impact.lifted?.length ? '' : ' (you have no constraint to lift)'}.
          </p>
        </section>
      ) : (
        <p className="text-sm text-muted-foreground">
          Against the same program with nothing in the way ({lifts.equipment ? `${lifts.equipment}, ` : ''}
          {impact.reference?.training_level ?? ''}{lifts.injury ? `, ${lifts.injury}` : ''}),{' '}
          {direct.length} of {impact.sessions?.total ?? '?'} sessions change{weeksCompared ? `, over its first ${weeksCompared} weeks` : ''}.
        </p>
      )}

      {restore.length > 0 && (
        <section className="space-y-2">
          <h3 className="text-sm font-semibold">What would restore it</h3>
          <div className="flex flex-wrap gap-2">
            {restore.slice(0, 6).map((r) => (
              <Button key={r.id} variant="outline" size="sm" className="h-8 gap-1.5 text-xs" disabled={busy}
                onClick={() => actions.addEquipment([r.id])}>
                <Plus className="size-3.5" aria-hidden="true" />
                Add {idLabel(r.id)} · restores {r.changes}
              </Button>
            ))}
            {(impact.lifted ?? []).includes('injury') && (
              <Button variant="outline" size="sm" className="h-8 text-xs" disabled={busy} onClick={actions.clearInjuries}>
                Preview {lifts.injury}
              </Button>
            )}
            {(impact.lifted ?? []).includes('level') && impact.reference?.training_level && (
              <Button variant="outline" size="sm" className="h-8 text-xs" disabled={busy}
                onClick={() => actions.setLevel(impact.reference!.training_level!)}>
                Preview {lifts.level}
              </Button>
            )}
          </div>
          <p className="text-[11px] text-muted-foreground">
            Each previews again with the change; your profile changes only if you start the program
            and keep the box ticked.
          </p>
        </section>
      )}

      {CAUSES.map(({ key, label, icon: Icon }) => {
        const group = direct.filter((c) => primaryCause(c) === key)
        if (group.length === 0) return null
        return (
          <section key={key} className="rounded-xl border bg-card p-4 space-y-2">
            <div className="flex items-center gap-2">
              <Icon className="size-4 text-primary" aria-hidden="true" />
              <h3 className="text-sm font-semibold">{label}</h3>
              <span className="text-xs text-muted-foreground">{group.length} session{group.length === 1 ? '' : 's'}</span>
            </div>
            <ul className="space-y-2">
              {group.map((c) => {
                const line = changeLine(c)
                return (
                  <li key={`${c.week_index}-${c.day}-${c.session_index}`} className="text-xs">
                    <p className="font-medium text-foreground">{line.title}</p>
                    {line.detail.map((d) => <p key={d} className="text-muted-foreground">{d}</p>)}
                  </li>
                )
              })}
            </ul>
          </section>
        )
      })}

      {knockOn.length > 0 && (
        <section className="space-y-1">
          <button type="button" onClick={() => setShowKnockOn((v) => !v)}
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
            {showKnockOn ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
            {knockOn.length} more change{knockOn.length === 1 ? '' : 's'} follow from these (the rotation moved)
          </button>
          {showKnockOn && (
            <ul className={cn('space-y-1 pl-5 text-xs text-muted-foreground')}>
              {knockOn.map((c) => (
                <li key={`${c.week_index}-${c.day}-${c.session_index}`}>{changeLine(c).title}</li>
              ))}
            </ul>
          )}
        </section>
      )}
    </div>
  )
}

/** A refused draft: the one change that alone lets it generate. */
export function RefusedPanel({ params, actions }: { params: GenerateParams; actions: HeldBackActions }) {
  const impact = useProgramImpact(impactParams(params, null))
  if (impact.isPending) {
    return <p className="inline-flex items-center gap-2 text-sm text-muted-foreground">
      <Loader2 className="size-4 animate-spin" aria-hidden="true" /> Finding what would let it build…
    </p>
  }
  const unblocked = impact.data?.unblocked_by ?? []
  if (unblocked.length === 0) return null
  const have = new Set(params.constraints.equipment ?? [])
  const missing = (impact.data?.reference?.equipment ?? []).filter((e) => !have.has(e as never) && e !== 'open_space')
  const action = (cause: string) => {
    switch (cause) {
      case 'equipment':
        return missing.length ? { label: `Add ${missing.map(idLabel).join(', ')} and preview`, run: () => actions.addEquipment(missing) } : null
      case 'injury':
        return { label: 'Preview without the injury flags', run: actions.clearInjuries }
      case 'level':
        return impact.data?.reference?.training_level
          ? { label: `Preview at ${impact.data.reference.training_level}`, run: () => actions.setLevel(impact.data!.reference!.training_level!) }
          : null
      case 'schedule':
        return { label: 'Change schedule', run: actions.editSchedule }
      default:
        return null
    }
  }
  return (
    <section className="rounded-xl border bg-card p-4 space-y-2">
      <h3 className="text-sm font-semibold">What would let it build</h3>
      <ul className="space-y-2 text-sm">
        {unblocked.map((u) => {
          const a = action(u.cause)
          return (
            <li key={u.cause} className="flex flex-wrap items-center gap-2">
              <span className="capitalize text-muted-foreground">{u.cause}:</span> {u.text}
              {a && (
                <Button variant="outline" size="sm" className="ml-auto h-7 text-xs" onClick={a.run}>
                  {a.label}
                </Button>
              )}
            </li>
          )
        })}
      </ul>
    </section>
  )
}
