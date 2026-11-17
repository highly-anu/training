import { useState, type ReactNode } from 'react'
import { ChevronRight, Code2, Database, AlertCircle, CheckCircle2, MinusCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { ModelEdge, ModelMap, TraceEngine, TracedProgram } from '@/api/types'
import { useModelMap } from '@/api/devlab'
import { SubTabs } from '@/components/layout/SubTabs'
import { engineOf } from './engine'

// Dev Lab ▸ Model Interactions: how the model's parts act on each other.
//
// Everything shown is the server's (GET /api/dev/model-map, src/model_map.py,
// tools/model_map.json): each interaction names the code that carries it, and
// test_model_map.py fails when that code is gone. Until 20.11 the map was
// constants in this file, describing the modality scheduler's path as the
// pipeline — the path no shipped package takes. A week is built one of three
// ways, so the map is read one engine at a time.

type Status = ModelMap['authoring'][number]['create']

const ENGINE_ORDER: TraceEngine[] = ['training_contract', 'week_templates', 'scheduler', 'composition']

function StatusIcon({ status }: { status: Status }) {
  if (status === 'yes') return <CheckCircle2 className="size-4 text-emerald-700 dark:text-emerald-300" aria-label="yes" />
  if (status === 'partial') return <AlertCircle className="size-4 text-amber-700 dark:text-amber-300" aria-label="in part" />
  if (status === 'no') return <MinusCircle className="size-4 text-red-700 dark:text-red-300" aria-label="no" />
  return <span className="text-xs text-muted-foreground">—</span>
}

function KnowledgeBar({ ratio }: { ratio: number }) {
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-[10px] text-muted-foreground">
        <span className="flex items-center gap-1"><Database className="size-3" /> Package data</span>
        <span className="flex items-center gap-1"><Code2 className="size-3" /> Engine code</span>
      </div>
      <div className="h-2 rounded-full bg-muted overflow-hidden flex">
        <div className="h-full bg-sky-500 rounded-l-full" style={{ width: `${100 - ratio}%` }} />
        <div className="h-full bg-orange-500 rounded-r-full" style={{ width: `${ratio}%` }} />
      </div>
      <div className="flex justify-between text-[10px] text-muted-foreground">
        <span>{100 - ratio}%</span>
        <span>{ratio}%</span>
      </div>
    </div>
  )
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">{children}</h2>
}

function List({ title, items }: { title: string; items: string[] }) {
  if (!items.length) return null
  return (
    <div>
      <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5">{title}</p>
      <ul className="space-y-1 text-xs text-foreground/85 list-disc pl-4">
        {items.map((item, i) => <li key={i}>{item}</li>)}
      </ul>
    </div>
  )
}

function EdgeDetail({ edge, labels }: { edge: ModelEdge; labels: Record<string, string> }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-sm space-y-1.5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-muted-foreground">{labels[edge.from] ?? edge.from}</span>
            <ChevronRight className="size-3 text-muted-foreground" />
            <span>{labels[edge.to] ?? edge.to}</span>
          </div>
          <p className="font-normal text-foreground/85">{edge.title}</p>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="outline" className="font-mono text-[10px] whitespace-normal">{edge.function}</Badge>
          <Badge variant="secondary" className="font-mono text-[10px] whitespace-normal">{edge.files}</Badge>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <List title={`Read from ${labels[edge.from] ?? edge.from}`} items={edge.reads_from_source} />
          <List title={`Read from ${labels[edge.to] ?? edge.to}`} items={edge.reads_from_target} />
        </div>
        <List title="What the engine decides" items={edge.engine_decides} />
        <List title="Constants in code" items={edge.constants} />
        <KnowledgeBar ratio={edge.baked_pct} />
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5">
            Held to the code by
          </p>
          <div className="flex flex-wrap gap-1">
            {edge.anchors.map((a) => (
              <code key={a} className="bg-muted px-1 rounded text-[10px] font-mono text-muted-foreground break-all">{a}</code>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

/** The engines the last generated program ran on, and what it placed. */
function LiveBanner({ result, engines }: { result: TracedProgram; engines: Record<string, string> }) {
  const weeks = result.generation_trace?.weeks ?? []
  if (!weeks.length) return null
  const used = [...new Set(weeks.map(engineOf))]
  const archetypes = [...new Set(
    Object.values(weeks[0].sessions ?? {}).flat().map((s) => s.archetype?.selected_id).filter(Boolean) as string[],
  )]
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-md border border-primary/20 bg-primary/5 px-3 py-2 text-xs">
      <span className="text-muted-foreground">The last generated program ran on:</span>
      {used.map((e) => <Badge key={e} variant="outline" className="text-[10px]">{engines[e] ?? e}</Badge>)}
      <span className="text-muted-foreground">week 1:</span>
      {archetypes.slice(0, 6).map((a) => (
        <Badge key={a} variant="secondary" className="text-[10px] font-mono">{a}</Badge>
      ))}
      {archetypes.length > 6 && <span className="text-muted-foreground">+{archetypes.length - 6}</span>}
    </div>
  )
}

export function ModelMapSection({ map, result }: { map: ModelMap; result?: TracedProgram | null }) {
  // The engine the last program ran on, else the one most tracks run on.
  const lastEngine = result?.generation_trace?.weeks?.[0] ? engineOf(result.generation_trace.weeks[0]) : null
  const busiest = [...ENGINE_ORDER].sort((a, b) => (map.usage[b]?.tracks ?? 0) - (map.usage[a]?.tracks ?? 0))[0]
  const [engine, setEngine] = useState<TraceEngine>(lastEngine ?? busiest)
  const path = map.edges.filter((e) => e.engine === null || e.engine === engine)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const selected = path.find((e) => e.id === selectedId) ?? path.find((e) => e.engine === engine) ?? path[0]
  const labels = Object.fromEntries(map.nodes.map((n) => [n.id, n.label]))
  const [openRow, setOpenRow] = useState<string | null>(null)

  return (
    <div className="space-y-6">
      {result && <LiveBanner result={result} engines={map.engines} />}

      <div>
        <SectionTitle>How a program is built — one engine at a time</SectionTitle>
        <p className="text-xs text-muted-foreground max-w-3xl mb-3">
          A track of a philosophy is an ordered list of phases, and each phase names the framework that builds its
          weeks. What builds a week is decided by the package's data: a training contract, a week template, or —
          with neither — the modality scheduler. Several tracks make a composition, each on its own engine.
        </p>
        <div className="mb-2">
          <SubTabs
            label="Engine"
            tabs={ENGINE_ORDER.map((e) => ({ id: e, label: map.engines[e] ?? e, badge: map.usage[e]?.tracks }))}
            active={engine}
            onChange={(e) => { setEngine(e); setSelectedId(null) }}
          />
        </div>
        <p className="text-[11px] text-muted-foreground mb-3">
          {map.usage[engine]
            ? `${map.usage[engine].tracks} ${map.usage[engine].tracks === 1 ? 'track runs' : 'tracks run'} on it`
              + (map.usage[engine].packages.length ? `: ${map.usage[engine].packages.join(', ')}.` : ' — no shipped package does.')
            : 'Any two contract or templated tracks; each keeps its own engine.'}
        </p>

        <ol className="space-y-1">
          {path.map((edge) => (
            <li key={edge.id}>
              <button
                onClick={() => setSelectedId(edge.id)}
                aria-current={edge.id === selected?.id ? 'step' : undefined}
                className={cn(
                  'w-full flex flex-wrap items-center gap-2 rounded-md border px-3 py-2 text-left transition-colors',
                  edge.id === selected?.id ? 'border-primary/40 bg-primary/10' : 'border-border/60 hover:bg-muted',
                )}
              >
                <span className="text-[11px] text-muted-foreground shrink-0">
                  {labels[edge.from] ?? edge.from} <ChevronRight className="inline size-3" /> {labels[edge.to] ?? edge.to}
                </span>
                <span className="text-xs text-foreground">{edge.title}</span>
                {edge.engine && <Badge variant="outline" className="text-[10px]">{map.engines[edge.engine]}</Badge>}
                <span className="ml-auto flex h-1 w-12 rounded-full overflow-hidden shrink-0"
                      aria-label={`${edge.baked_pct}% engine code`}>
                  <span className="bg-sky-500" style={{ width: `${100 - edge.baked_pct}%` }} />
                  <span className="bg-orange-500" style={{ width: `${edge.baked_pct}%` }} />
                </span>
              </button>
            </li>
          ))}
        </ol>
        <p className="text-[10px] text-muted-foreground mt-1.5">
          Blue is what the package's data decides, orange what the engine does. Checked against the code on {map.checked};
          each interaction's anchors are checked on every push.
        </p>
      </div>

      {selected && <EdgeDetail edge={selected} labels={labels} />}

      <div>
        <SectionTitle>Authoring — what can be written where</SectionTitle>
        <div className="rounded-lg border border-border overflow-x-auto">
          <table className="w-full text-xs min-w-[560px]">
            <thead>
              <tr className="border-b border-border bg-muted/30 text-muted-foreground">
                <th className="text-left px-3 py-2 font-medium">What</th>
                <th className="px-3 py-2 font-medium">Create</th>
                <th className="px-3 py-2 font-medium">Edit</th>
                <th className="px-3 py-2 font-medium">Remove</th>
                <th className="text-left px-3 py-2 font-medium">Writes</th>
              </tr>
            </thead>
            <tbody>
              {map.authoring.map((row) => (
                <tr key={row.type} className="border-b border-border/50 last:border-0 align-top">
                  <td className="px-3 py-2.5">
                    <button
                      className="text-left font-medium hover:underline underline-offset-2"
                      aria-expanded={openRow === row.type}
                      onClick={() => setOpenRow(openRow === row.type ? null : row.type)}
                    >
                      {row.type}
                    </button>
                    {openRow === row.type && (
                      <ul className="mt-1.5 space-y-1 text-[11px] text-muted-foreground list-disc pl-4">
                        {row.notes.map((n, i) => <li key={i}>{n}</li>)}
                      </ul>
                    )}
                  </td>
                  <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.create} /></div></td>
                  <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.edit} /></div></td>
                  <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.remove} /></div></td>
                  <td className="px-3 py-2.5 text-muted-foreground">{row.writes}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground mt-1.5">
          Every write needs a signed-in user and the authoring gate. What a package can bring, and what stands between
          a folder and a package written while the app runs: Builder readiness.
        </p>
      </div>
    </div>
  )
}

interface Props {
  result?: TracedProgram | null
}

export function ModelInteractionPanel({ result }: Props) {
  const { data, isLoading, error } = useModelMap()
  return (
    <div className="px-4 md:px-6 py-4 max-w-5xl">
      {isLoading
        ? <p className="text-xs text-muted-foreground">Reading the map…</p>
        : error || !data
          ? (
            <p className="text-xs text-muted-foreground">
              The model map needs the local API (or AUTHORING_ENABLED):{' '}
              <code className="bg-muted px-1 rounded">GET /api/dev/model-map</code>.
            </p>
          )
          : <ModelMapSection map={data} result={result} />}
    </div>
  )
}
