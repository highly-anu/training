import { Badge } from '@/components/ui/badge'
import type {
  ContractWeekTrace, PlacementTrace, SchedulerTrace, TemplateWeekTrace, TraceEngine, WeekTestsTrace,
} from '@/api/types'
import { words } from './engine'

// What each engine decided for a week, laid out from the trace (roadmap 20.9,
// 20.10). A week is built one of three ways — a training contract places its
// modules, a week template writes the source's days, the modality scheduler
// allocates sessions — and a composition runs several tracks, each on its
// own. The Schedule step and the pipeline flow both draw from here, so the two
// cannot describe an engine differently.

const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

function Heading({ children }: { children: React.ReactNode }) {
  return <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-1.5">{children}</p>
}

function dayName(day: string | number): string {
  const n = Number(day)
  return Number.isInteger(n) && n >= 1 && n <= 7 ? DAY_SHORT[n - 1] : String(day)
}

// ─── Tests ────────────────────────────────────────────────────────────────────

export function WeekTests({ tests }: { tests?: WeekTestsTrace | null }) {
  if (!tests || (!tests.placed.length && !tests.skipped.length)) return null
  return (
    <div className="text-xs space-y-0.5">
      <Heading>Tests</Heading>
      {tests.placed.map((t, i) => (
        <p key={`p${i}`}>
          <Badge variant="outline" className="text-[10px] mr-1.5">placed</Badge>
          <span className="font-mono">{t.archetype}</span> <span className="text-muted-foreground">on {t.day}</span>
        </p>
      ))}
      {tests.skipped.map((t, i) => (
        <p key={`s${i}`}>
          <Badge variant="outline" className="text-[10px] mr-1.5 text-amber-700 dark:text-amber-300">skipped</Badge>
          <span className="font-mono">{(t.archetypes ?? []).join(', ')}</span>{' '}
          <span className="text-muted-foreground">— {words(t.reason)}</span>
        </p>
      ))}
    </div>
  )
}

// ─── A training contract's week ───────────────────────────────────────────────

const SCORE_ROWS: Array<[keyof PlacementTrace['score'], string]> = [
  ['days_shared_with_other_tracks', "Days shared with another track's"],
  ['days_stacked', 'Modules stacked on a day'],
  ['optional_sessions', 'Optional sessions placed'],
  ['same_modality_back_to_back', 'Same modality on days back to back'],
  ['same_modality_neighbours', 'Same modality on neighbouring training days'],
  ['regions_loaded_close', 'Body regions loaded heavily a day or two apart'],
  ['spread', "Days between each module's own sessions (more is better)"],
]

function PlacementDays({ placement }: { placement: PlacementTrace }) {
  return (
    <div className="grid grid-cols-7 gap-1">
      {DAY_SHORT.map((label, i) => {
        const modules = placement.days[String(i + 1)] ?? []
        return (
          <div key={label} className="text-center">
            <p className="text-[10px] text-muted-foreground mb-1">{label}</p>
            <div className="min-h-[24px] space-y-0.5">
              {modules.length
                ? modules.map((m) => (
                  <div key={m} className="rounded px-1 py-0.5 text-[9px] font-medium bg-primary/10 text-primary truncate" title={m}>
                    {words(m)}
                  </div>
                ))
                : <div className="text-[9px] text-muted-foreground/30">—</div>}
            </div>
          </div>
        )
      })}
    </div>
  )
}

export function ContractWeek({ decided }: { decided: ContractWeekTrace }) {
  const { chosen, runner_up: next, considered } = decided.placement
  return (
    <div className="space-y-4">
      <div>
        <Heading>The modules this week</Heading>
        <div className="overflow-x-auto">
          <table className="text-xs w-full">
            <thead>
              <tr className="text-muted-foreground text-left">
                <th className="pr-3 pb-1 font-normal">Module</th>
                <th className="pr-3 pb-1 font-normal">A week</th>
                <th className="pr-3 pb-1 font-normal">Minutes</th>
                <th className="pr-3 pb-1 font-normal">Step</th>
                <th className="pr-3 pb-1 font-normal">Model</th>
                <th className="pb-1 font-normal">This week</th>
              </tr>
            </thead>
            <tbody>
              {decided.modules.map((m) => (
                <tr key={m.id} className="border-t border-border/20">
                  <td className="pr-3 py-0.5">
                    {m.name} <span className="font-mono text-[10px] text-muted-foreground">{m.id}</span>
                  </td>
                  <td className="pr-3 py-0.5 font-mono">×{m.exposures_per_week}</td>
                  <td className="pr-3 py-0.5 font-mono">{m.minutes}</td>
                  <td className="pr-3 py-0.5 font-mono">{m.step}</td>
                  <td className="pr-3 py-0.5 font-mono text-muted-foreground">{m.model}</td>
                  <td className="py-0.5 text-muted-foreground">
                    {[m.optional ? 'optional' : null, m.deload ? 'deload' : null, m.blocked ? `out: ${m.blocked}` : null]
                      .filter(Boolean).join(' · ') || 'as written'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground mt-1">
          Training days [{decided.day_pool.map(dayName).join(', ')}] · {decided.session_minutes}-minute sessions ·{' '}
          {decided.deload.week
            ? decided.deload.forced ? 'a deload week (forced)' : `a deload week (every ${decided.deload.frequency_weeks} weeks)`
            : 'not a deload week'}
        </p>
      </div>

      <div>
        <Heading>Placement — the best of {considered} looked at</Heading>
        <PlacementDays placement={chosen} />
        <details className="text-xs mt-2">
          <summary className="cursor-pointer select-none text-muted-foreground hover:text-foreground transition-colors">
            Why this one{next ? ', against the next best' : ''}
          </summary>
          <table className="text-xs w-full mt-2">
            <thead>
              <tr className="text-muted-foreground text-left">
                <th className="pr-3 pb-1 font-normal">Counted</th>
                <th className="pr-3 pb-1 font-normal">Chosen</th>
                {next && <th className="pb-1 font-normal">Next best</th>}
              </tr>
            </thead>
            <tbody>
              {SCORE_ROWS.map(([key, label]) => (
                <tr key={key} className="border-t border-border/20">
                  <td className="pr-3 py-0.5">{label}</td>
                  <td className="pr-3 py-0.5 font-mono">{String(chosen.score[key])}</td>
                  {next && <td className="py-0.5 font-mono text-muted-foreground">{String(next.score[key])}</td>}
                </tr>
              ))}
            </tbody>
          </table>
          {next && (
            <div className="mt-2">
              <p className="text-[10px] text-muted-foreground mb-1">The next best:</p>
              <PlacementDays placement={next} />
            </div>
          )}
        </details>
      </div>

      {decided.optional_short.length > 0 && (
        <div className="text-xs">
          <Heading>Optional work left short</Heading>
          {decided.optional_short.map((o) => (
            <p key={o.id}>
              {o.name}: {o.placed} of {o.of} — <span className="text-muted-foreground">{o.reason}</span>
            </p>
          ))}
        </div>
      )}
      {decided.test && (
        <p className="text-xs">
          <Badge variant="outline" className="text-[10px] mr-1.5">test</Badge>
          <span className="font-mono">{(decided.test.archetypes ?? []).join(', ')}</span>
          {decided.test.day && <span className="text-muted-foreground"> — the {decided.test.day} session of its module</span>}
        </p>
      )}
    </div>
  )
}

// ─── A week the source writes day by day ──────────────────────────────────────

export function TemplateWeek({ decided, onlyDay }: { decided: TemplateWeekTrace; onlyDay?: string | null }) {
  const days = Object.entries(decided.days).filter(([day]) => !onlyDay || dayName(day) === onlyDay.slice(0, 3))
  return (
    <div className="space-y-3">
      {!onlyDay && (
        <p className="text-xs text-muted-foreground">
          The source trains {decided.source_days} days; the athlete {decided.training_days}.
          {decided.dropped.length > 0 && <> Left out: <span className="text-foreground">{decided.dropped.join(', ')}</span>.</>}
        </p>
      )}
      {days.map(([day, d]) => (
        <div key={day} className="text-xs">
          <p className="mb-1">
            <span className="font-medium">{dayName(day)}</span>{' '}
            <span className="text-muted-foreground">{d.categories.map(words).join(' + ')} · {d.minutes} min</span>
            {d.left_out && <Badge variant="outline" className="text-[10px] ml-1.5 text-amber-700 dark:text-amber-300">nothing fitted</Badge>}
          </p>
          <div className="space-y-1 pl-3 border-l border-border">
            {d.asked.map((pool, i) => (
              <div key={i}>
                <p>
                  <span className="text-muted-foreground">{words(pool.category)}</span>{' '}
                  <span className="font-mono text-[10px] text-muted-foreground">
                    workout {pool.pool ? (pool.rotation_at % pool.pool) + 1 : 0} of {pool.pool} · {pool.minutes} min
                  </span>{' → '}
                  {pool.picked
                    ? <span className="font-mono">{pool.picked}</span>
                    : <span className="text-amber-700 dark:text-amber-300">none fits</span>}
                </p>
                {pool.passed_over.length > 0 && (
                  <details>
                    <summary className="cursor-pointer select-none text-[10px] text-muted-foreground hover:text-foreground transition-colors">
                      {pool.passed_over.length} passed over
                    </summary>
                    <ul className="pl-3 text-[10px] text-muted-foreground">
                      {pool.passed_over.map((p) => (
                        <li key={p.id}><span className="font-mono">{p.id}</span> — {p.why}</li>
                      ))}
                    </ul>
                  </details>
                )}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

// ─── Whichever engine built it ────────────────────────────────────────────────

/** What an engine decided, from its scheduler block; nothing for the scheduler (its card draws the allocation). */
export function EngineDecisions({ engine, scheduler, onlyDay }: {
  engine: TraceEngine
  scheduler: SchedulerTrace | null | undefined
  onlyDay?: string | null
}) {
  if (engine === 'training_contract' && scheduler?.contract_week) return <ContractWeek decided={scheduler.contract_week} />
  if (engine === 'week_templates' && scheduler?.template) return <TemplateWeek decided={scheduler.template} onlyDay={onlyDay} />
  return null
}
