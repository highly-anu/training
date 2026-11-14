import type { ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Badge } from '@/components/ui/badge'
import { EmptyState } from '@/components/shared/EmptyState'
import { QueryState } from '@/components/shared/states'
import { cn } from '@/lib/utils'
import {
  useDevBuild, useDevBuilds,
  type BuildCall, type BuildCheck, type BuildDetail, type BuildsList, type BuildSummary, type BuildTurn, type TurnTokens,
} from '@/api/devlab'

// Dev Lab ▸ Builds: what each build of a method did (docs/roadmap.md 21.7) —
// its turns, the checks and the problems they found, the tokens and what they
// cost. Everything here is the server's (GET /api/dev/builds, src/build_report.py);
// this file only lays it out. The signed-in account's own builds: a build
// keeps what its athlete wrote and pasted.

const STATUS_CLASS: Record<string, string> = {
  done: 'border-good/30 bg-good/10 text-good',
  failed: 'border-bad/30 bg-bad/10 text-bad',
  cancelled: 'border-border bg-muted text-muted-foreground',
  running: 'border-warn/30 bg-warn/5 text-warn',
  queued: 'border-border bg-muted text-muted-foreground',
}

const count = (n: number) => n.toLocaleString('en-US')
const usd = (n: number) => `$${n.toFixed(2)}`

function duration(seconds: number): string {
  const s = Math.round(seconds)
  return s < 60 ? `${s} s` : `${Math.floor(s / 60)} min ${s % 60} s`
}

function when(stamp: string | null | undefined): string {
  if (!stamp) return '—'
  const date = new Date(stamp.replace(' ', 'T'))
  return Number.isNaN(date.getTime())
    ? stamp
    : date.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">{children}</h2>
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-lg border border-border px-3 py-2">
      <div className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</div>
      <div className="text-sm font-semibold tabular-nums">{value}</div>
      {sub && <div className="text-[10px] text-muted-foreground tabular-nums">{sub}</div>}
    </div>
  )
}

function StatusBadge({ status }: { status: string }) {
  return <Badge variant="outline" className={cn('text-[10px]', STATUS_CLASS[status])}>{status}</Badge>
}

/** The listed builds together, then one row a build. */
export function BuildsTable({ list, selected, onSelect }: {
  list: BuildsList
  selected: string | null
  onSelect: (id: string) => void
}) {
  const { totals } = list
  const statuses = Object.entries(totals.byStatus).map(([status, n]) => `${n} ${status}`).join(' · ')
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-2 md:grid-cols-5">
        <Stat label="Builds" value={count(totals.builds)} sub={statuses} />
        <Stat label="Done of those that ended"
          value={totals.doneShare === null ? '—' : `${Math.round(totals.doneShare * 100)}%`} />
        <Stat label="Output tokens" value={count(totals.outputTokens)} />
        <Stat label="Input tokens" value={count(totals.inputTokens)}
          sub={`${count(totals.cacheReadTokens)} read from cache · ${count(totals.cacheWriteTokens)} written`} />
        <Stat label="Tokens cost" value={usd(totals.costUsd)} sub={duration(totals.seconds)} />
      </div>
      <div className="rounded-lg border border-border overflow-x-auto">
        <table className="w-full text-xs min-w-[760px]">
          <thead>
            <tr className="border-b border-border bg-muted/30 text-muted-foreground">
              <th className="text-left px-3 py-2 font-medium">Started</th>
              <th className="text-left px-3 py-2 font-medium">Status</th>
              <th className="text-left px-3 py-2 font-medium">Asked for</th>
              <th className="text-right px-3 py-2 font-medium">Turns</th>
              <th className="text-right px-3 py-2 font-medium">Checks</th>
              <th className="text-right px-3 py-2 font-medium">Output</th>
              <th className="text-right px-3 py-2 font-medium">Time</th>
              <th className="text-right px-3 py-2 font-medium">Cost</th>
            </tr>
          </thead>
          <tbody>
            {list.builds.map((b) => (
              <tr key={b.id} aria-selected={b.id === selected}
                className={cn('border-b border-border/50 last:border-0', b.id === selected && 'bg-muted/40')}>
                <td className="px-3 py-2 whitespace-nowrap">
                  <button type="button" onClick={() => onSelect(b.id)}
                    className="font-medium underline-offset-2 hover:underline focus-visible:underline"
                    aria-label={`Open the build started ${when(b.createdAt)}`}>
                    {when(b.createdAt)}
                  </button>
                </td>
                <td className="px-3 py-2">
                  <StatusBadge status={b.status} />
                  {b.error && <span className="ml-1.5 font-mono text-[10px] text-muted-foreground">{b.error.code}</span>}
                </td>
                <td className="px-3 py-2 max-w-[320px]">
                  <div className="truncate">{b.result?.name ?? b.description}</div>
                  <div className="text-[10px] text-muted-foreground">
                    {[b.revise ? `revision of ${b.revise}` : 'new method', b.webSearch && 'web search',
                      b.pastedChars > 0 && `${count(b.pastedChars)} pasted characters`].filter(Boolean).join(' · ')}
                  </div>
                </td>
                <td className="px-3 py-2 text-right tabular-nums">{b.usage.turns}</td>
                <td className="px-3 py-2 text-right tabular-nums">{b.usage.checks}</td>
                <td className="px-3 py-2 text-right tabular-nums">{count(b.usage.outputTokens)}</td>
                <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{duration(b.usage.seconds)}</td>
                <td className="px-3 py-2 text-right tabular-nums">{usd(b.costUsd)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function tokensLine(t: TurnTokens | null): string | null {
  if (!t) return null
  return `${count(t.output)} out · ${count(t.input)} in · ${count(t.cacheRead)} cached`
    + (t.cacheWrite ? ` · ${count(t.cacheWrite)} written` : '')
}

function callLine(call: BuildCall): string {
  const what = call.path ?? call.kind ?? call.query
  return [call.tool, what, call.bytes !== null && `${count(call.bytes)} bytes`].filter(Boolean).join(' · ')
}

function Turn({ turn }: { turn: BuildTurn }) {
  const tokens = tokensLine(turn.tokens)
  return (
    <li className="rounded-lg border border-border px-3 py-2">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
        <span className="text-xs font-semibold">Turn {turn.n}</span>
        {tokens && <span className="text-[10px] text-muted-foreground tabular-nums">{tokens}</span>}
        {turn.thought && <span className="text-[10px] text-muted-foreground">thought first</span>}
      </div>
      {turn.said && <p className="mt-1 text-xs whitespace-pre-wrap">{turn.said}</p>}
      {turn.calls.length > 0 && (
        <ul className="mt-1.5 space-y-0.5">
          {turn.calls.map((call, i) => (
            <li key={i} className="text-[11px]">
              <span className="font-mono">{callLine(call)}</span>
              {call.result && (
                <span className={cn('ml-2', call.error ? 'text-bad' : 'text-muted-foreground')}>
                  {call.error ? 'refused: ' : '→ '}{call.result}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
      {turn.note && <p className="mt-1.5 text-[11px] text-warn">The loop said: {turn.note}</p>}
    </li>
  )
}

function Check({ check, index }: { check: BuildCheck; index: number }) {
  const athlete = check.athlete
  return (
    <li className="rounded-lg border border-border px-3 py-2">
      <div className="flex flex-wrap items-baseline gap-x-3">
        <span className="text-xs font-semibold">Check {index + 1}</span>
        <span className={cn('text-xs', check.ok ? 'text-good' : 'text-bad')}>
          {check.ok ? 'passes' : `${check.problems.length + check.moreProblems} to fix`}
        </span>
        <span className="text-[10px] text-muted-foreground">
          turn {check.turn}{check.tool === 'finish' ? ' · on finish' : ''}
          {check.checksLeft !== null && ` · ${check.checksLeft} left`}
        </span>
      </div>
      {check.problems.length > 0 && (
        <ul className="mt-1.5 space-y-1">
          {check.problems.map((p, i) => (
            <li key={i} className="text-[11px]">
              <span className="font-mono text-muted-foreground">{[p.stage, p.code, p.file].filter(Boolean).join(' · ')}</span>
              <span className="ml-2">{p.message}</span>
            </li>
          ))}
          {check.moreProblems > 0 && <li className="text-[11px] text-muted-foreground">and {check.moreProblems} more</li>}
        </ul>
      )}
      {check.warnings.length > 0 && (
        <ul className="mt-1.5 space-y-0.5">
          {check.warnings.map((w, i) => <li key={i} className="text-[11px] text-warn">{w}</li>)}
        </ul>
      )}
      {athlete?.error && <p className="mt-1.5 text-[11px] text-bad">The athlete's program was not generated: {athlete.error}</p>}
      {athlete && athlete.feasible === false && (
        <ul className="mt-1.5 space-y-0.5">
          {athlete.errors.map((e, i) => (
            <li key={i} className="text-[11px] text-bad"><span className="font-mono">{e.code}</span> {e.message}</li>
          ))}
        </ul>
      )}
      {athlete && athlete.checkThese.length > 0 && (
        <div className="mt-1.5">
          <div className="text-[10px] uppercase tracking-wider text-muted-foreground">The model was asked to look at</div>
          <ul className="space-y-0.5">
            {athlete.checkThese.map((line, i) => <li key={i} className="text-[11px]">{line}</li>)}
          </ul>
        </div>
      )}
      {athlete?.program && (
        <details className="mt-1.5">
          <summary className="cursor-pointer text-[11px] text-muted-foreground">
            The program the model was shown{athlete.weeks ? ` — ${athlete.weeks.shown} of ${athlete.weeks.of} weeks` : ''}
            {athlete.moreTracks > 0 ? `, and ${athlete.moreTracks} more track${athlete.moreTracks === 1 ? '' : 's'}` : ''}
          </summary>
          <pre className="mt-1 max-h-96 overflow-auto rounded bg-muted/40 p-2 text-[10px] leading-relaxed">{athlete.program}</pre>
        </details>
      )}
    </li>
  )
}

/** One build in full. */
export function BuildReport({ build }: { build: BuildDetail }) {
  const { usage, limits, request } = build
  const answers = [
    request.answers.days && `${request.answers.days} days`,
    request.answers.minutes && `${request.answers.minutes} min`,
    request.answers.level,
    request.answers.equipment ? request.answers.equipment.join(', ') || 'no equipment' : 'equipment not said',
  ].filter(Boolean).join(' · ')
  return (
    <div className="space-y-5">
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-sm font-semibold">{build.result?.name ?? (build.revise ? `Revision of ${build.revise}` : 'New method')}</h2>
          <StatusBadge status={build.status} />
          <span className="text-[10px] text-muted-foreground">
            {when(build.createdAt)} · {usage.model ?? 'no model yet'} · effort {build.effort}
            {build.attempts > 1 && ` · ${build.attempts} attempts`}
          </span>
        </div>
        {build.result && (
          <p className="mt-1 text-xs">
            <span className="font-mono text-[10px] text-muted-foreground">{build.result.packageId} r{build.result.revision}</span>{' '}
            {build.result.summary}
          </p>
        )}
        {build.error && (
          <div className="mt-2 rounded-lg border border-bad/30 bg-bad/10 px-3 py-2 text-xs">
            <span className="font-mono">{build.error.code}</span> — {build.error.message}
            {build.error.detail && <div className="mt-0.5 text-[11px] text-muted-foreground">{build.error.detail}</div>}
          </div>
        )}
      </div>

      <div>
        <SectionTitle>Asked for</SectionTitle>
        <p className="text-xs whitespace-pre-wrap">{request.description}</p>
        <p className="mt-1 text-[11px] text-muted-foreground">
          {answers}{request.webSearch && ' · web search allowed'}
        </p>
        {request.pastedText && (
          <details className="mt-1">
            <summary className="cursor-pointer text-[11px] text-muted-foreground">
              Pasted text — {count(request.pastedText.length)} characters
            </summary>
            <pre className="mt-1 max-h-64 overflow-auto whitespace-pre-wrap rounded bg-muted/40 p-2 text-[10px]">{request.pastedText}</pre>
          </details>
        )}
      </div>

      <div>
        <SectionTitle>Spent, against a build's limits</SectionTitle>
        <div className="grid grid-cols-2 gap-2 md:grid-cols-5">
          <Stat label="Turns" value={`${usage.turns} of ${limits.turns}`} />
          <Stat label="Checks" value={`${usage.checks} of ${limits.checks}`} />
          <Stat label="Output tokens" value={count(usage.outputTokens)} sub={`of ${count(limits.outputTokens)}`} />
          <Stat label="Time" value={duration(usage.seconds)} sub={`of ${duration(limits.seconds)}`} />
          <Stat label="Tokens cost" value={usd(build.costUsd)} sub={`at ${build.priceModel} prices`} />
        </div>
        <p className="mt-1.5 text-[10px] text-muted-foreground tabular-nums">
          Input {count(usage.inputTokens)} · read from cache {count(usage.cacheReadTokens)} · written to
          cache {count(usage.cacheWriteTokens)} · web searches {usage.webSearches} · pages fetched {usage.webFetches}.
          Searches are billed apart from tokens.
        </p>
        {build.droppedTurns.length > 0 && (
          <p className="mt-1 text-[11px] text-warn">
            {build.droppedTurns.length} repl{build.droppedTurns.length === 1 ? 'y was' : 'ies were'} cut off at the output
            limit and thrown away
            ({build.droppedTurns.map((d) => `${count(d.tokens?.output ?? 0)} output tokens`).join(', ')}): paid for, nothing kept.
          </p>
        )}
      </div>

      {build.problemCounts.length > 0 && (
        <div>
          <SectionTitle>Problems by kind, over every check</SectionTitle>
          <ul className="flex flex-wrap gap-1.5">
            {build.problemCounts.map((p) => (
              <li key={`${p.stage}:${p.code}`}>
                <Badge variant="outline" className="font-mono text-[10px]">
                  {[p.stage, p.code].filter(Boolean).join(' · ')} ×{p.count}
                </Badge>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div>
        <SectionTitle>Checks — the gate's answers</SectionTitle>
        {build.checks.length
          ? <ul className="space-y-2">{build.checks.map((c, i) => <Check key={i} check={c} index={i} />)}</ul>
          : <p className="text-xs text-muted-foreground">The gate answered no check in this build.</p>}
      </div>

      <div>
        <SectionTitle>Turns</SectionTitle>
        {build.turns.length
          ? <ul className="space-y-2">{build.turns.map((t) => <Turn key={t.n} turn={t} />)}</ul>
          : <p className="text-xs text-muted-foreground">The model has not answered yet.</p>}
      </div>

      <div>
        <SectionTitle>
          {build.status === 'done' ? 'Files — as installed' : 'Files — the draft as it was left'}
        </SectionTitle>
        {build.files.length
          ? (
            <ul className="space-y-1">
              {build.files.map((f) => (
                <li key={f.path}>
                  <details>
                    <summary className="cursor-pointer text-[11px]">
                      <span className="font-mono">{f.path}</span>
                      <span className="ml-2 text-muted-foreground tabular-nums">{count(f.bytes)} bytes</span>
                    </summary>
                    <pre className="mt-1 max-h-96 overflow-auto rounded bg-muted/40 p-2 text-[10px] leading-relaxed">{f.content}</pre>
                  </details>
                </li>
              ))}
            </ul>
          )
          : <p className="text-xs text-muted-foreground">Nothing was written.</p>}
      </div>
    </div>
  )
}

function SelectedBuild({ id }: { id: string }) {
  const query = useDevBuild(id)
  return (
    <QueryState query={query} loading="list" failedTitle="Could not load the build" size="compact">
      {(build: BuildSummary & BuildDetail) => <BuildReport build={build} />}
    </QueryState>
  )
}

export function BuildsPanel() {
  const query = useDevBuilds()
  const [searchParams, setSearchParams] = useSearchParams()
  const asked = searchParams.get('build')
  function select(id: string) {
    const next = new URLSearchParams(searchParams)
    next.set('build', id)
    setSearchParams(next, { replace: true })
  }
  return (
    <div className="px-4 md:px-6 py-4 max-w-5xl space-y-6">
      <p className="text-xs text-muted-foreground">
        What each build of a method did: its turns, the checks and the problems they found, the tokens and what
        they cost. This account's own builds — a build keeps what its athlete wrote.
      </p>
      <QueryState query={query} hasContent={(list: BuildsList) => list.builds.length > 0} loading="list"
        failedTitle="Could not load the builds"
        empty={<EmptyState size="compact" title="No builds yet"
          description="Describe a method in the program builder's first step; its build shows here." />}>
        {(list: BuildsList) => {
          const selected = list.builds.find((b) => b.id === asked)?.id ?? list.builds[0].id
          return (
            <>
              <BuildsTable list={list} selected={selected} onSelect={select} />
              <SelectedBuild key={selected} id={selected} />
            </>
          )
        }}
      </QueryState>
    </div>
  )
}
