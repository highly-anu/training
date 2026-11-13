import type { ReactNode } from 'react'
import { CheckCircle2, MinusCircle } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { PortabilityGap, PortabilityPackage, PortabilityReport, PortabilityStep } from '@/api/types'
import { usePortability } from '@/api/devlab'

// Dev Lab ▸ Builder readiness: where the foundation of the LLM package builder
// stands (docs/roadmap.md item 20). Everything here is the server's — the
// steps, the gaps with their code anchors and the per-package report
// (GET /api/dev/portability, src/portability.py, tools/portability_gaps.json);
// this file only lays it out. A gap closes in the JSON, in the change that
// closes it, and test_portability.py holds each open one to the code.

const SHAPE_LABEL: Record<string, string> = {
  contract: 'contract',
  templates: 'templates',
  scheduler: 'scheduler',
}

const IMPACT_CLASS: Record<PortabilityGap['impact'], string> = {
  blocks: 'bg-red-500/15 text-red-700 dark:text-red-300 border-red-500/30',
  degrades: 'bg-amber-500/15 text-amber-700 dark:text-amber-300 border-amber-500/30',
  cosmetic: 'bg-muted text-muted-foreground border-border',
}

const KIND_ORDER: PortabilityGap['kind'][] = [
  'runtime', 'gate', 'tooling', 'commons', 'code', 'client', 'watch', 'docs', 'devlab',
]
const KIND_LABEL: Record<PortabilityGap['kind'], string> = {
  runtime: 'Runtime',
  gate: 'Push gates',
  tooling: 'Tooling',
  commons: 'Commons',
  code: 'Engine code',
  client: 'Clients',
  watch: 'Watches',
  docs: 'Docs',
  devlab: 'Dev Lab',
}

function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
      {children}
    </h2>
  )
}

function Tick({ done, title }: { done: boolean | null; title: string }) {
  if (done === null) {
    return <span title={`${title} — not in this deployment`} aria-label={`${title}: not checkable here`}
      className="inline-flex size-3.5 items-center justify-center text-[10px] text-muted-foreground">—</span>
  }
  return done
    ? <span title={title}><CheckCircle2 className="size-3.5 text-emerald-700 dark:text-emerald-300" aria-label={`${title}: yes`} /></span>
    : <span title={title}><MinusCircle className="size-3.5 text-red-700 dark:text-red-300" aria-label={`${title}: missing`} /></span>
}

function PackageRow({ pkg, recordIds }: { pkg: PortabilityPackage; recordIds: string[] }) {
  const shapes = [...new Set(pkg.tracks.map(t => t.shape))]
  const optional = pkg.files.filter(f => !f.required && f.present !== null)
  const unreadable = pkg.files.filter(f => f.present === null).length
  const missingRequired = pkg.files.filter(f => f.required && !f.present)
  const unknown = pkg.vocabulary.flatMap(v => v.unknown.map(u => `${v.kind}: ${u}`))
  return (
    <tr className="border-b border-border/50 last:border-0">
      <td className="px-3 py-2">
        <div className="font-medium">{pkg.name}</div>
        <div className="font-mono text-[10px] text-muted-foreground">{pkg.id}</div>
      </td>
      <td className="px-3 py-2">
        <div className="flex flex-wrap gap-1">
          {shapes.map(s => (
            <Badge key={s} variant="outline" className="text-[10px]">
              {SHAPE_LABEL[s] ?? s} ×{pkg.tracks.filter(t => t.shape === s).length}
            </Badge>
          ))}
        </div>
      </td>
      <td className="px-3 py-2 text-[11px]">
        {missingRequired.length > 0
          ? <span className="text-red-700 dark:text-red-300">missing {missingRequired.map(f => f.path).join(', ')}</span>
          : <span className="text-muted-foreground" title={optional.filter(f => f.present).map(f => f.path).join(', ')}>
              core + {optional.filter(f => f.present).length}/{optional.length} optional
              {unreadable > 0 && ` (+${unreadable} not in this deployment)`}
            </span>}
      </td>
      <td className="px-3 py-2">
        <div className="flex gap-1">
          {recordIds.map(id => {
            const o = pkg.records.find(x => x.id === id)
            return o ? <Tick key={id} done={o.done} title={o.done === false ? `${o.label} — ${o.how}` : o.label} /> : null
          })}
        </div>
      </td>
      <td className="px-3 py-2 text-[11px]">
        {unknown.length
          ? <span className="text-red-700 dark:text-red-300" title={unknown.join('\n')}>{unknown.length} unknown</span>
          : <span className="text-muted-foreground">all in commons</span>}
      </td>
      <td className="px-3 py-2 text-[11px]">
        {pkg.collisions
          ? <span className="text-amber-700 dark:text-amber-300">{pkg.collisions}</span>
          : <span className="text-muted-foreground">0</span>}
      </td>
      <td className="px-3 py-2 text-center">
        <div className="flex justify-center"><Tick done={pkg.ready} title="Drops in" /></div>
      </td>
    </tr>
  )
}

function GapItem({ gap }: { gap: PortabilityGap }) {
  const done = gap.status === 'done'
  return (
    <li className="space-y-1">
      <div className="flex flex-wrap items-center gap-1.5">
        {done
          ? <Badge className="text-[10px] hover:bg-transparent bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border-emerald-500/30">
              done {gap.closed}
            </Badge>
          : <Badge className={cn('text-[10px] hover:bg-transparent', IMPACT_CLASS[gap.impact])}>{gap.impact}</Badge>}
        <span className={cn('text-xs', done ? 'text-muted-foreground' : 'text-foreground')}>{gap.title}</span>
        <span className="text-[10px] text-muted-foreground">{KIND_LABEL[gap.kind]}</span>
      </div>
      {gap.detail && <p className="text-[11px] text-muted-foreground leading-relaxed">{gap.detail}</p>}
      <div className="flex flex-wrap gap-1">
        {(done ? gap.evidence ?? [] : gap.anchors).map(a => (
          <code key={a} className="bg-muted px-1 rounded text-[10px] font-mono text-muted-foreground break-all">{a}</code>
        ))}
      </div>
    </li>
  )
}

/** A step is done when the roadmap says so, or when every gap citing it is. */
function stepDone(step: PortabilityStep, gaps: PortabilityGap[]): boolean {
  if (step.done) return true
  return gaps.length > 0 && gaps.every(g => g.status === 'done')
}

function StepCard({ step, gaps }: { step: PortabilityStep; gaps: PortabilityGap[] }) {
  const done = stepDone(step, gaps)
  const open = gaps.filter(g => g.status === 'open')
  return (
    <li className="rounded-lg border border-border p-3 space-y-2.5">
      <div className="flex flex-wrap items-center gap-2">
        <Tick done={done} title={done ? 'Done' : 'Open'} />
        <span className="font-mono text-[11px] text-muted-foreground">{step.id}</span>
        <span className="text-sm font-medium text-foreground">{step.title}</span>
        <span className="text-[11px] text-muted-foreground">
          {step.done
            ? `done ${step.done}`
            : gaps.length === 0
              ? 'no gap recorded'
              : `${gaps.length - open.length} of ${gaps.length} gaps closed`}
        </span>
      </div>
      {gaps.length > 0 && (
        <ul className="space-y-2.5 pl-5">
          {gaps.map(g => <GapItem key={g.id} gap={g} />)}
        </ul>
      )}
    </li>
  )
}

export function ReadinessSection({ report }: { report: PortabilityReport }) {
  const recordIds = report.packages[0]?.records.map(o => o.id) ?? []
  const recordLabels = report.packages[0]?.records ?? []
  const uncheckedLabels = report.unchecked.map(id =>
    recordLabels.find(o => o.id === id)?.label
      ?? report.packages[0]?.files.find(f => f.id === id)?.path
      ?? id)
  const steps = report.steps ?? []
  const stepIds = new Set(steps.map(s => s.id))
  const tracked = report.gaps.filter(g => g.status !== 'by_design')
  const open = tracked.filter(g => g.status === 'open')
  const blocking = open.filter(g => g.impact === 'blocks')
  const elsewhere = open.filter(g => !g.roadmap || !stepIds.has(g.roadmap))
  const byDesign = report.gaps.filter(g => g.status === 'by_design')
  const stepsDone = steps.filter(s => stepDone(s, report.gaps.filter(g => g.roadmap === s.id))).length
  const ready = report.packages.filter(p => p.ready).length
  return (
    <div className="space-y-8">
      <div>
        <SectionTitle>Can the app take a package written while it runs?</SectionTitle>
        <p className="text-xs text-foreground/80 leading-relaxed max-w-3xl">{report.verdict}</p>
        <p className="mt-2 text-sm text-foreground">
          {stepsDone} of {steps.length} steps done · {tracked.length - open.length} of {tracked.length} gaps
          closed · {blocking.length} open {blocking.length === 1 ? 'gap blocks' : 'gaps block'} a built package
        </p>
      </div>

      {steps.length > 0 && (
        <div>
          <SectionTitle>The foundation, in order</SectionTitle>
          <ol className="space-y-2">
            {steps.map(s => (
              <StepCard key={s.id} step={s} gaps={report.gaps.filter(g => g.roadmap === s.id)} />
            ))}
          </ol>
          <p className="mt-2 text-[10px] text-muted-foreground">
            The steps are <code className="bg-muted px-1 rounded">docs/roadmap.md</code> item 20; the gaps and their
            anchors <code className="bg-muted px-1 rounded">tools/portability_gaps.json</code>. An open gap's anchors
            are still in the code; a closed one names the test that holds it.
          </p>
        </div>
      )}

      {elsewhere.length > 0 && (
        <div>
          <SectionTitle>Other open gaps</SectionTitle>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {KIND_ORDER.map(kind => {
              const gaps = elsewhere.filter(g => g.kind === kind)
              if (!gaps.length) return null
              return (
                <div key={kind}>
                  <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5">
                    {KIND_LABEL[kind]}
                  </p>
                  <ul className="space-y-2.5">
                    {gaps.map(g => <GapItem key={g.id} gap={g} />)}
                  </ul>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {byDesign.length > 0 && (
        <div>
          <SectionTitle>By design — the engine's vocabulary a package chooses from</SectionTitle>
          <ul className="space-y-2.5">
            {byDesign.map(g => <GapItem key={g.id} gap={g} />)}
          </ul>
        </div>
      )}

      <div className="space-y-3">
        <SectionTitle>Packages — a folder that drops into a checkout?</SectionTitle>
        <div className="rounded-lg border border-border overflow-x-auto">
          <table className="w-full text-xs min-w-[720px]">
            <thead>
              <tr className="border-b border-border bg-muted/30 text-muted-foreground">
                <th className="text-left px-3 py-2 font-medium">Package</th>
                <th className="text-left px-3 py-2 font-medium">Engine shape (tracks)</th>
                <th className="text-left px-3 py-2 font-medium">In its folder</th>
                <th className="text-left px-3 py-2 font-medium" title={recordLabels.map(o => o.label).join(' · ')}>
                  Its records
                </th>
                <th className="text-left px-3 py-2 font-medium">Vocabulary</th>
                <th className="text-left px-3 py-2 font-medium">Id collisions</th>
                <th className="px-3 py-2 font-medium text-center">Drops in</th>
              </tr>
            </thead>
            <tbody>
              {report.packages.map(p => <PackageRow key={p.id} pkg={p} recordIds={recordIds} />)}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground">
          {ready} of {report.packages.length} packages in <code className="bg-muted px-1 rounded">{report.packagesDir}</code> drop
          in as they stand. The records the gates keep in each folder, in order: {recordLabels.map(o => o.label).join(' · ')}.{' '}
          {report.sharedExercises} exercise ids are shared between packages by design; each keeps its own prescription.
        </p>
        {report.unchecked.length > 0 && (
          <p className="text-[10px] text-amber-700 dark:text-amber-300">
            Not checkable here: {uncheckedLabels.join(' · ')} — their files are not in this deployment (the API
            image leaves every package's records, dossier and source weeks out). Run the local API to check them;
            "drops in" covers the rest.
          </p>
        )}

        {report.collisions.length > 0 && (
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wider text-amber-700/80 dark:text-amber-300/80 mb-1.5">
              Ids two packages declare — resolved silently
            </p>
            <ul className="space-y-0.5">
              {report.collisions.map(c => (
                <li key={`${c.kind}:${c.id}`} className="text-[11px] text-muted-foreground">
                  <span className="font-mono text-foreground">{c.kind} {c.id}</span> in {c.packages.join(', ')} — keeps {c.kept}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </div>
  )
}

export function ReadinessPanel() {
  const { data, isLoading, error } = usePortability()
  return (
    <div className="px-4 md:px-6 py-4 max-w-5xl">
      {isLoading
        ? <p className="text-xs text-muted-foreground">Reading the packages…</p>
        : error || !data
          ? (
            <p className="text-xs text-muted-foreground">
              The readiness report needs the local API (or AUTHORING_ENABLED):{' '}
              <code className="bg-muted px-1 rounded">GET /api/dev/portability</code>.
            </p>
          )
          : <ReadinessSection report={data} />}
    </div>
  )
}
