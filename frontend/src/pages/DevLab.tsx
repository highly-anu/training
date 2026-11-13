import { PageHeader } from '@/components/layout/PageHeader'
import { SubTabs } from '@/components/layout/SubTabs'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Page } from '@/components/layout/Page'
import { Terminal, Play } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { usePhilosophies } from '@/api/philosophies'
import { useGenerateWithTrace } from '@/api/programs'
import { useInjuryFlags } from '@/api/constraints'
import { resolveTrack, tracksOf } from '@/lib/tracks'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import { ValidationPanel } from '@/components/devlab/ValidationPanel'
import { SchedulerPanel } from '@/components/devlab/SchedulerPanel'
import { SessionsPanel } from '@/components/devlab/SessionsPanel'
import { PipelineFlowPanel } from '@/components/devlab/PipelineFlowPanel'
import { ObjectBrowser } from '@/components/objectbrowser/ObjectBrowser'
import { HeatmapPanel } from '@/components/devlab/heatmap/HeatmapPanel'
import { ModelInteractionPanel } from '@/components/devlab/ModelInteractionPanel'
import { ReadinessPanel } from '@/components/devlab/ReadinessPanel'
import { ImpactPanel } from '@/components/devlab/ImpactPanel'
import type { GenerateParams } from '@/api/programs'
import type { EquipmentId, FatigueState, InjuryFlagId, TrainingLevel, TracedProgram, WeekData } from '@/api/types'
import { TRAINING_LEVELS } from '@/lib/gen/clientVocab'
import { useEquipmentGroups } from '@/lib/useEquipmentVocabulary'
import { ENGINE_LABEL, engineOf } from '@/components/devlab/engine'

// ─── Equipment picker options ─────────────────────────────────────────────────

const FATIGUE_STATES: FatigueState[] = ['fresh', 'normal', 'accumulated', 'overreached']

// ─── StepMeta annotation banner ──────────────────────────────────────────────

function StepMeta({ reads, outputs, description }: { reads: string[], outputs: string[], description: string }) {
  return (
    <div className="mb-4 rounded-lg border border-border/40 bg-muted/20 p-3 space-y-2">
      <p className="text-xs text-muted-foreground">{description}</p>
      <div className="flex flex-wrap gap-x-6 gap-y-1.5">
        <div className="flex items-start gap-2">
          <span className="text-[10px] uppercase tracking-wider text-muted-foreground/50 shrink-0 mt-0.5">reads</span>
          <div className="flex flex-wrap gap-1">
            {reads.map(r => <span key={r} className="px-1.5 py-0.5 rounded bg-muted text-[10px] font-mono text-muted-foreground">{r}</span>)}
          </div>
        </div>
        <div className="flex items-start gap-2">
          <span className="text-[10px] uppercase tracking-wider text-muted-foreground/50 shrink-0 mt-0.5">outputs</span>
          <div className="flex flex-wrap gap-1">
            {outputs.map(o => <span key={o} className="px-1.5 py-0.5 rounded bg-primary/10 text-[10px] font-mono text-primary/70">{o}</span>)}
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Inputs Panel ─────────────────────────────────────────────────────────────

function InputsPanel({ program }: { program: TracedProgram }) {
  const { goal, constraints } = program
  const trace = program.generation_trace

  const sortedPriorities = Object.entries(goal.priorities)
    .filter(([, v]) => v > 0)
    .sort(([, a], [, b]) => b - a)

  const primarySources = trace?.primary_sources || goal.primary_sources || []
  const isPhilosophyMode = !!(goal.primary_sources && goal.primary_sources.length > 0)
  // What builds the weeks, and so what of the inputs below is read.
  const engines = [...new Set((trace?.weeks ?? []).map(engineOf))]
  const scheduled = engines.includes('scheduler')
  const lanes = (trace?.lanes ?? []) as Array<{ key?: string; philosophy_id?: string; track_id?: string; weight?: number; share?: number }>

  return (
    <div className="space-y-4 max-w-2xl">
      {/* Philosophy Sources */}
      {primarySources.length > 0 && (
        <Card className="border-violet-500/30 bg-violet-500/5">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <CardTitle className="text-sm">Philosophy Sources</CardTitle>
              {engines.map(e => (
                <Badge key={e} className="text-[10px] bg-violet-500/20 text-violet-700 dark:text-violet-300 border-violet-500/40">
                  {ENGINE_LABEL[e]}
                </Badge>
              ))}
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-1">
              {primarySources.map(s => (
                <Badge key={s} variant="outline" className="text-xs border-violet-500/40 bg-violet-500/10 text-violet-700 dark:text-violet-300 font-mono">
                  {s}
                </Badge>
              ))}
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              Sessions and exercises come only from these packages and the ones each declares it borrows from;
              what a package cannot fill is left empty and reported.
            </p>
            {lanes.length > 1 && (
              <ul className="mt-2 space-y-0.5 text-xs">
                {lanes.map((l, i) => (
                  <li key={l.key ?? i} className="font-mono">
                    {l.key ?? `${l.philosophy_id}/${l.track_id}`}
                    {typeof (l.share ?? l.weight) === 'number' && (
                      <span className="text-muted-foreground"> · {Math.round(((l.share ?? l.weight) as number) * 100)}%</span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      )}

      {/* Goal / Priorities */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{isPhilosophyMode ? 'Generated Priorities' : goal.name}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {!isPhilosophyMode && goal.description && (
            <p className="text-xs text-muted-foreground">{goal.description}</p>
          )}
          {!scheduled && engines.length > 0 && (
            <p className="text-xs text-muted-foreground">
              Derived from the framework's sessions a week. Nothing places this program by them: a training
              contract places its modules and a week template writes the source's days. Only the modality
              scheduler allocates sessions from priorities.
            </p>
          )}
          <div className="space-y-1.5">
            {sortedPriorities.map(([mod, prio]) => (
              <div key={mod} className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground w-40 truncate">
                  {mod.replace(/_/g, ' ')}
                </span>
                <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className="h-full bg-primary rounded-full transition-all"
                    style={{ width: `${prio * 100}%` }}
                  />
                </div>
                <span className="text-xs font-mono text-muted-foreground w-8 text-right">
                  {(prio * 100).toFixed(0)}%
                </span>
              </div>
            ))}
          </div>
          {goal.phase_sequence && goal.phase_sequence.length > 0 && (
            <div className="flex flex-wrap gap-1 mt-2">
              <span className="text-xs text-muted-foreground self-center">Phases:</span>
              {goal.phase_sequence.map((p, i) => (
                <Badge key={i} variant="outline" className="text-[10px]">
                  {p.phase} · {p.weeks}w
                </Badge>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Constraints */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Constraints</CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid grid-cols-2 gap-x-6 gap-y-1.5 text-xs">
            <dt className="text-muted-foreground">Days/week</dt>
            <dd className="font-mono">{constraints.days_per_week}</dd>
            <dt className="text-muted-foreground">Session time</dt>
            <dd className="font-mono">{constraints.session_time_minutes} min</dd>
            <dt className="text-muted-foreground">Level</dt>
            <dd className="font-mono">{constraints.training_level}</dd>
            <dt className="text-muted-foreground">Track</dt>
            <dd className="font-mono">{goal.track?.name ?? constraints.track_id ?? '—'}</dd>
            <dt className="text-muted-foreground">Start phase</dt>
            <dd className="font-mono">{program.weeks[0]?.phase_name ?? constraints.start_phase ?? '—'}</dd>
            <dt className="text-muted-foreground">Fatigue state</dt>
            <dd className="font-mono">{constraints.fatigue_state}</dd>
            <dt className="text-muted-foreground">Injuries</dt>
            <dd className="flex flex-wrap gap-0.5 mt-0.5">
              {constraints.injury_flags.length === 0 && <span className="font-mono">none</span>}
              {constraints.injury_flags.map(f => (
                <span key={f} className="bg-muted rounded px-1 py-0.5 text-[10px] font-mono">
                  {f}
                </span>
              ))}
            </dd>
            <dt className="text-muted-foreground">Equipment</dt>
            <dd className="flex flex-wrap gap-0.5 mt-0.5">
              {constraints.equipment.length === 0 && <span className="font-mono">none</span>}
              {constraints.equipment.map(e => (
                <span key={e} className="bg-muted rounded px-1 py-0.5 text-[10px] font-mono">
                  {e}
                </span>
              ))}
            </dd>
          </dl>
        </CardContent>
      </Card>
    </div>
  )
}

// ─── What the program says about itself ───────────────────────────────────────

function ProgramOutputs({ program }: { program: TracedProgram }) {
  const compromises = program.compromises ?? []
  const coverage = (program.coverage_report ?? {}) as Record<string, unknown[] | undefined>
  const held = program.held_back
  const rows: Array<[string, string]> = [
    ['unfilled_sessions', 'Sessions the package could not fill'],
    ['unfilled_slots', 'Slots left empty'],
    ['substituted_sessions', 'Sessions substituted'],
    ['borrowed_sessions', 'Sessions borrowed from another package'],
    ['placed_tests', 'Tests placed'],
    ['skipped_tests', 'Tests skipped'],
  ]
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">What the program says about itself</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-xs">
        <dl className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-1">
          {rows.map(([key, label]) => (
            <div key={key} className="flex justify-between gap-3">
              <dt className="text-muted-foreground">{label}</dt>
              <dd className="font-mono">{(coverage[key] ?? []).length}</dd>
            </div>
          ))}
          {held && (
            <div className="flex justify-between gap-3">
              <dt className="text-muted-foreground">Held back by the constraints</dt>
              <dd className="font-mono">{held.sessions} sessions · {held.slots} slots</dd>
            </div>
          )}
        </dl>
        {compromises.length > 0 ? (
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground mb-1">Compromises</p>
            <ul className="space-y-0.5 list-disc pl-4">
              {compromises.map((c, i) => <li key={i}>{c}</li>)}
            </ul>
          </div>
        ) : (
          <p className="text-muted-foreground">No compromise: the program is as its package writes it.</p>
        )}
      </CardContent>
    </Card>
  )
}

// ─── DevLab page ──────────────────────────────────────────────────────────────

type DevTab = 'pipeline' | 'impact' | 'browser' | 'heatmap' | 'interactions' | 'readiness'

const DEV_TABS: { id: DevTab; label: string }[] = [
  { id: 'pipeline', label: 'Pipeline Trace' },
  { id: 'impact', label: 'Impact' },
  { id: 'browser', label: 'Object Browser' },
  { id: 'heatmap', label: 'Ontology' },
  { id: 'interactions', label: 'Model Interactions' },
  { id: 'readiness', label: 'Builder readiness' },
]

export function DevLab() {
  const { data: philosophies = [], isLoading: loadingPhilosophies } = usePhilosophies()
  const { data: injuryFlagOptions = [] } = useInjuryFlags()
  const generateMutation = useGenerateWithTrace()
  // The equipment an athlete can tick: the commons' list (generated) and what
  // the athlete's own packages add — never a list typed here — plus open space,
  // which the pickers assume and this form lets be taken away.
  const equipmentGroups = useEquipmentGroups()
  const equipmentOptions = useMemo(
    () => [...equipmentGroups.flatMap(g => g.items), { id: 'open_space' as EquipmentId, label: 'Open space' }],
    [equipmentGroups],
  )

  // The tab is in the URL (`?tab=readiness`), as on every other page, so a
  // tool can be linked to. A trace can be linked to as well: the form starts
  // from `?philosophy=&track=&second=&second_track=&level=&days=&minutes=&weeks=
  // &equipment=all&step=` and `run=1` generates once on arrival.
  const [searchParams, setSearchParams] = useSearchParams()
  const [linked] = useState(() => ({
    philosophy: searchParams.get('philosophy') ?? '',
    track: searchParams.get('track'),
    second: searchParams.get('second'),
    secondTrack: searchParams.get('second_track'),
    level: searchParams.get('level') as TrainingLevel | null,
    days: Number(searchParams.get('days')) || null,
    minutes: Number(searchParams.get('minutes')) || null,
    weeks: Number(searchParams.get('weeks')) || null,
    allEquipment: searchParams.get('equipment') === 'all',
    step: searchParams.get('step'),
    run: searchParams.get('run') === '1',
  }))

  // Form state
  const [philosophyId, setPhilosophyId] = useState<string>(linked.philosophy)
  // null = the philosophy's primary track / the track's first phase, as the builder sends.
  const [trackId, setTrackId] = useState<string | null>(linked.track)
  const [startPhaseId, setStartPhaseId] = useState<string | null>(null)
  // A second track makes the request a composition (`lanes`): two tracks of
  // different methods, or two of one, each on its own engine.
  const [second, setSecond] = useState<{ philosophyId: string; trackId: string | null } | null>(
    linked.second ? { philosophyId: linked.second, trackId: linked.secondTrack } : null,
  )
  const [level, setLevel] = useState<TrainingLevel>(linked.level ?? 'intermediate')
  const [fatigue, setFatigue] = useState<FatigueState>('normal')
  const [injuryFlags, setInjuryFlags] = useState<InjuryFlagId[]>([])
  const [days, setDays] = useState(linked.days ?? 4)
  const [sessionTime, setSessionTime] = useState(linked.minutes ?? 60)
  const [numWeeks, setNumWeeks] = useState(linked.weeks ?? 2)
  const [equipment, setEquipment] = useState<EquipmentId[]>([
    'barbell',
    'kettlebell',
    'pull_up_bar',
    'open_space',
  ])

  // Result
  const [result, setResult] = useState<TracedProgram | null>(null)
  const [activeStep, setActiveStep] = useState('inputs')
  const [outputWeekIdx, setOutputWeekIdx] = useState(0)

  const philosophy = philosophies.find(p => p.id === philosophyId)
  const tracks = tracksOf(philosophy)
  const track = resolveTrack(philosophy, trackId)
  const startPhase = track?.phases.find(p => p.id === startPhaseId) ?? track?.phases[0]
  const secondPhilosophy = philosophies.find(p => p.id === second?.philosophyId)
  const secondTracks = tracksOf(secondPhilosophy)
  const secondTrack = resolveTrack(secondPhilosophy, second?.trackId ?? null)

  function selectPhilosophy(id: string) {
    setPhilosophyId(id)
    setTrackId(null)
    setStartPhaseId(null)
  }

  function selectTrack(id: string) {
    setTrackId(id)
    setStartPhaseId(null)
  }

  function toggleEquipment(id: EquipmentId) {
    setEquipment(prev =>
      prev.includes(id) ? prev.filter(e => e !== id) : [...prev, id]
    )
  }

  function toggleInjury(id: InjuryFlagId) {
    setInjuryFlags(prev =>
      prev.includes(id) ? prev.filter(f => f !== id) : [...prev, id]
    )
  }

  /** The form as a generate request (Pipeline Trace and Impact send the same one). */
  function requestOf(useAll = false): GenerateParams | null {
    if (!philosophyId || (second && !second.philosophyId)) return null
    return {
        philosophyId,
        ...(second?.philosophyId ? {
          lanes: [
            { philosophyId, trackId: track?.id ?? null, weight: 0.5, startPhaseId: startPhase?.id ?? null },
            { philosophyId: second.philosophyId, trackId: secondTrack?.id ?? null, weight: 0.5 },
          ],
        } : {}),
        trackId: track?.id ?? null,
        startPhaseId: startPhase?.id ?? null,
        constraints: {
          equipment: useAll ? equipmentOptions.map(o => o.id) : equipment,
          days_per_week: days,
          session_time_minutes: sessionTime,
          training_level: level,
          injury_flags: injuryFlags,
          avoid_movements: [],
          periodization_week: 1,
          fatigue_state: fatigue,
        },
        numWeeks,
        customInjuryFlags: [],
    }
  }

  async function handleGenerate(useAll = false) {
    const request = requestOf(useAll)
    if (!request) return
    try {
      const data = await generateMutation.mutateAsync(request)
      setResult(data)
      setActiveStep(useAll && linked.step ? linked.step : 'inputs')
      setOutputWeekIdx(0)
    } catch (_) {
      // error shown via mutation.isError
    }
  }

  const trace = result?.generation_trace
  const canGenerate = !!philosophyId && (!second || !!second.philosophyId) && !generateMutation.isPending

  // A linked trace (`run=1`) generates once, when the philosophies it names are known.
  const ran = useRef(false)
  useEffect(() => {
    if (!linked.run || ran.current || !philosophy || (second?.philosophyId && !secondPhilosophy)) return
    ran.current = true
    void handleGenerate(linked.allEquipment)
    // Once, on arrival: later edits to the form are generated by the button.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [philosophy, secondPhilosophy])

  const requested = searchParams.get('tab')
  const devTab: DevTab = DEV_TABS.some(t => t.id === requested) ? (requested as DevTab) : 'pipeline'
  function setDevTab(tab: DevTab) {
    const next = new URLSearchParams(searchParams)
    next.set('tab', tab)
    setSearchParams(next, { replace: true })
  }
  const [ontologyNodeId, setOntologyNodeId] = useState<string | null>(null)
  const [ontologyFromBrowser, setOntologyFromBrowser] = useState(false)

  function openInOntology(nodeId: string) {
    setOntologyNodeId(nodeId)
    setOntologyFromBrowser(true)
    setDevTab('heatmap')
  }

  return (
    <Page
      key="devlab"
      className="flex flex-col h-full min-h-0"
    >
      <PageHeader
        icon={Terminal}
        title="Dev Lab"
        tabs={<SubTabs label="Dev Lab tools" tabs={DEV_TABS} active={devTab} onChange={setDevTab} />}
      />

      {devTab === 'browser' && (
        <div className="flex-1 min-h-0">
          <ObjectBrowser onOpenInOntology={openInOntology} />
        </div>
      )}

      {devTab === 'heatmap' && (
        <div className="flex-1 overflow-y-auto px-6 py-4" style={{ scrollbarGutter: 'stable' }}>
          <HeatmapPanel
            program={result}
            constraints={result ? {
              equipment,
              days_per_week: days,
              session_time_minutes: sessionTime,
              training_level: level,
              injury_flags: injuryFlags,
              fatigue_state: fatigue,
              numWeeks,
            } : undefined}
            initialLockedNode={ontologyNodeId}
            onBack={ontologyFromBrowser ? () => { setDevTab('browser'); setOntologyFromBrowser(false) } : undefined}
          />
        </div>
      )}

      {devTab === 'interactions' && (
        <div className="flex-1 overflow-y-auto">
          <ModelInteractionPanel result={result} />
        </div>
      )}

      {devTab === 'readiness' && (
        <div className="flex-1 overflow-y-auto">
          <ReadinessPanel />
        </div>
      )}


      {(devTab === 'pipeline' || devTab === 'impact') && <div className="flex-1 overflow-y-auto">
        {/* ── Program Selector ── */}
        <div className="border-b bg-muted/20 px-6 py-4 shrink-0">
          <div className="max-w-5xl space-y-3">
            <div className="flex flex-wrap items-end gap-3">
              {/* Philosophy */}
              <div className="min-w-[200px]">
                <Label className="text-xs mb-1 block">Philosophy</Label>
                <Select value={philosophyId} onValueChange={selectPhilosophy} disabled={loadingPhilosophies}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue placeholder="Select philosophy…" />
                  </SelectTrigger>
                  <SelectContent>
                    {philosophies.map(p => (
                      <SelectItem key={p.id} value={p.id} className="text-xs">
                        {p.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Level */}
              <div className="min-w-[130px]">
                <Label className="text-xs mb-1 block">Level</Label>
                <Select value={level} onValueChange={v => setLevel(v as TrainingLevel)}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {TRAINING_LEVELS.map(l => (
                      <SelectItem key={l} value={l} className="text-xs">{l}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Track */}
              <div className="min-w-[180px]">
                <Label className="text-xs mb-1 block">Track</Label>
                <Select value={track?.id ?? ''} onValueChange={selectTrack} disabled={tracks.length < 2}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue placeholder="—" />
                  </SelectTrigger>
                  <SelectContent>
                    {tracks.map(t => (
                      <SelectItem key={t.id} value={t.id} className="text-xs">{t.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Start phase */}
              <div className="min-w-[200px]">
                <Label className="text-xs mb-1 block">Start phase</Label>
                <Select value={startPhase?.id ?? ''} onValueChange={setStartPhaseId} disabled={!track}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue placeholder="—" />
                  </SelectTrigger>
                  <SelectContent>
                    {(track?.phases ?? []).map(p => (
                      <SelectItem key={p.id} value={p.id} className="text-xs">
                        {p.name} <span className="text-muted-foreground">· {p.kind} · {p.weeks}w · {p.framework_id}</span>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Fatigue */}
              <div className="min-w-[120px]">
                <Label className="text-xs mb-1 block">Fatigue</Label>
                <Select value={fatigue} onValueChange={v => setFatigue(v as FatigueState)}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {FATIGUE_STATES.map(f => (
                      <SelectItem key={f} value={f} className="text-xs">{f}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Days */}
              <div>
                <Label className="text-xs mb-1 block">Days/wk</Label>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setDays(d => Math.max(2, d - 1))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    −
                  </button>
                  <span className="w-6 text-center text-sm font-mono">{days}</span>
                  <button
                    onClick={() => setDays(d => Math.min(7, d + 1))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    +
                  </button>
                </div>
              </div>

              {/* Session time */}
              <div>
                <Label className="text-xs mb-1 block">Session (min)</Label>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setSessionTime(t => Math.max(30, t - 15))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    −
                  </button>
                  <span className="w-8 text-center text-sm font-mono">{sessionTime}</span>
                  <button
                    onClick={() => setSessionTime(t => Math.min(120, t + 15))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    +
                  </button>
                </div>
              </div>

              {/* Weeks */}
              <div>
                <Label className="text-xs mb-1 block">Weeks</Label>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setNumWeeks(w => Math.max(1, w - 1))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    −
                  </button>
                  <span className="w-6 text-center text-sm font-mono">{numWeeks}</span>
                  <button
                    onClick={() => setNumWeeks(w => Math.min(8, w + 1))}
                    className="size-8 rounded border text-sm hover:bg-muted transition-colors"
                  >
                    +
                  </button>
                </div>
              </div>

              {/* Generate */}
              <Button
                size="sm"
                onClick={() => handleGenerate()}
                disabled={!canGenerate}
                loading={generateMutation.isPending}
                className="h-8 ml-auto"
              >
                <Play className="size-3" />
                Generate
              </Button>
            </div>

            {/* A second track: the request becomes a composition */}
            <div className="flex flex-wrap items-end gap-3">
              {second ? (
                <>
                  <div className="min-w-[200px]">
                    <Label className="text-xs mb-1 block">Second track — philosophy</Label>
                    <Select value={second.philosophyId} onValueChange={v => setSecond({ philosophyId: v, trackId: null })}>
                      <SelectTrigger className="h-8 text-xs">
                        <SelectValue placeholder="Select philosophy…" />
                      </SelectTrigger>
                      <SelectContent>
                        {philosophies.map(p => (
                          <SelectItem key={p.id} value={p.id} className="text-xs">{p.name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="min-w-[180px]">
                    <Label className="text-xs mb-1 block">Its track</Label>
                    <Select value={secondTrack?.id ?? ''} disabled={secondTracks.length < 2}
                            onValueChange={v => setSecond({ philosophyId: second.philosophyId, trackId: v })}>
                      <SelectTrigger className="h-8 text-xs">
                        <SelectValue placeholder="—" />
                      </SelectTrigger>
                      <SelectContent>
                        {secondTracks.map(t => (
                          <SelectItem key={t.id} value={t.id} className="text-xs">{t.name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <Button size="sm" variant="ghost" className="h-8 text-xs" onClick={() => setSecond(null)}>
                    Remove the second track
                  </Button>
                  <p className="text-[10px] text-muted-foreground basis-full">
                    Two tracks are a composition, half the week each: every track runs its own phases on its own
                    engine (a contract track or a templated one; a scheduler track cannot be composed).
                  </p>
                </>
              ) : (
                <Button size="sm" variant="ghost" className="h-7 text-xs px-2" onClick={() => setSecond({ philosophyId: '', trackId: null })}>
                  + Add a second track (a composition)
                </Button>
              )}
            </div>

            {/* Equipment */}
            <div className="flex flex-wrap gap-1.5 items-center">
              <span className="text-xs text-muted-foreground">Equipment:</span>
              <button
                onClick={() => setEquipment(equipmentOptions.map(o => o.id))}
                className="px-2 py-0.5 rounded text-xs text-muted-foreground underline-offset-2 hover:underline"
              >
                all
              </button>
              <button
                onClick={() => setEquipment([])}
                className="px-2 py-0.5 rounded text-xs text-muted-foreground underline-offset-2 hover:underline"
              >
                none
              </button>
              {equipmentOptions.map(opt => (
                <button
                  key={opt.id}
                  onClick={() => toggleEquipment(opt.id)}
                  className={cn(
                    'px-2 py-0.5 rounded text-xs border transition-colors',
                    equipment.includes(opt.id)
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}
                >
                  {opt.label}
                </button>
              ))}
            </div>

            {/* Injuries */}
            <div className="flex flex-wrap gap-1.5 items-center">
              <span className="text-xs text-muted-foreground">Injuries:</span>
              {injuryFlagOptions.map(flag => (
                <button
                  key={flag.id}
                  onClick={() => toggleInjury(flag.id)}
                  title={flag.description}
                  className={cn(
                    'px-2 py-0.5 rounded text-xs border transition-colors',
                    injuryFlags.includes(flag.id)
                      ? 'bg-destructive/15 border-destructive/40 text-destructive'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}
                >
                  {flag.name}
                </button>
              ))}
            </div>

            {generateMutation.isError && (
              <p className="text-xs text-destructive">
                Generation failed. Check the API server is running.
              </p>
            )}
          </div>
        </div>

        {devTab === 'impact' && <ImpactPanel params={requestOf()} />}

        {/* ── Pipeline Steps ── */}
        {devTab === 'pipeline' && <div className="px-6 py-4">
          {!result ? (
            <div className="flex flex-col items-center justify-center py-20 text-muted-foreground">
              <Terminal className="size-12 mb-4 opacity-20" />
              <p className="text-sm">Select a philosophy and click Generate to see the full pipeline trace</p>
            </div>
          ) : (
            <Tabs value={activeStep} onValueChange={setActiveStep}>
              <TabsList className="mb-4">
                <TabsTrigger value="inputs" className="text-xs">① Inputs</TabsTrigger>
                <TabsTrigger value="validation" className="text-xs">② Validation</TabsTrigger>
                <TabsTrigger value="schedule" className="text-xs">③ Schedule</TabsTrigger>
                <TabsTrigger value="sessions" className="text-xs">④ Sessions</TabsTrigger>
                <TabsTrigger value="output" className="text-xs">⑤ Output</TabsTrigger>
              </TabsList>

              {/* ① Inputs */}
              <TabsContent value="inputs">
                <StepMeta
                  reads={['philosophy and track (or several: a composition)', 'athlete constraints']}
                  outputs={['phase sequence', 'primary_sources (package filter)', 'priority weights', 'constraint envelope']}
                  description="A track of a philosophy becomes the goal: its phases in order, each naming the framework that builds its weeks, and the packages the program may draw from. The priority weights are derived from the framework's sessions a week and are read only by the modality scheduler — a training contract and a week template place their weeks themselves. Constraints say what the athlete can do."
                />
                <InputsPanel program={result} />
              </TabsContent>

              {/* ② Validation */}
              <TabsContent value="validation">
                <StepMeta
                  reads={['goal priorities', 'archetypes', 'modalities', 'equipment', 'injury flags']}
                  outputs={['feasibility flag', 'equipment warnings', 'time-cap checks', 'injury conflicts']}
                  description="The pre-flight check of a scheduler or templated track: equipment, days, session time, injuries, phases. A training contract refuses for itself, as it builds — a week whose required modules do not fit is an error here with no weeks — and a composition is checked track by track as it is composed; what a templated week could not fit is a compromise on the program, not a refusal."
                />
                <ValidationPanel validation={result.validation} />
              </TabsContent>

              {/* ③ Schedule */}
              <TabsContent value="schedule">
                <StepMeta
                  reads={['phase priority weights', 'framework.sessions_per_week', 'framework.cadence_options', 'modality.recovery_cost / recovery_hours_min', 'modality.incompatible_in_session_with', 'phase.week_templates', 'training contract modules']}
                  outputs={['session counts per modality', 'day-of-week assignment', 'deload flag']}
                  description="Converts priority weights into session counts via the framework, then places them on the framework's cadence days, hardest first: a modality keeps its recovery window from itself and two high-cost modalities 48 h apart, checked against the days before and after and last week's end. A phase that writes its own week (week_templates) takes the source's days instead, and a training contract places its modules itself — alternating them, spacing each module's sessions and keeping heavily loaded body regions apart. Every shipped package does one or the other, and a composition runs each of its tracks on its own; the scheduler builds only a package with neither. Each week's card says which engine built it and what it decided."
                />
                {trace ? (
                  <SchedulerPanel weeks={trace.weeks} />
                ) : (
                  <p className="text-sm text-muted-foreground">No scheduler trace in response.</p>
                )}
              </TabsContent>

              {/* ④ Sessions */}
              <TabsContent value="sessions">
                <StepMeta
                  reads={['assigned modality', 'the package and the packages it borrows from', 'training phase', 'equipment', 'archetypes', 'exercises', 'injury flags', 'progression model']}
                  outputs={['selected archetype', 'exercises per slot', 'load prescriptions']}
                  description="Each session gets its archetype: a template day the next named workout of its category the athlete can do as written, a contract its module's, a test its own. Only a session left to choose is scored — after the hard filters (modality, phase, level, equipment, time): +10 preferred, +6 equipment met, −3 used in the last 14, +3 or −2 day fit, injury and blocked-equipment penalties, −2/−1 per body region a session a day or two before loaded heavily; ties go to the least recently used, then the first authored. Slots fill from the archetype's own package and those its philosophy borrows from: named exercises (in order where the slot says so) or its pattern and category, filtered by equipment, injury, level unlocks, phase exclusions and the taper rule; −2 per recent use, +0.5 for a pattern and for an unlock, ties to the first authored. A main lift stays the same through a phase. Load comes from the framework's progression model for the modality where it overrides one, else the modality's."
                />
                {trace ? (
                  <>
                    <PipelineFlowPanel program={result} weeks={trace.weeks} />
                    <hr className="border-border/30 my-4" />
                    <SessionsPanel weeks={trace.weeks} />
                  </>
                ) : (
                  <p className="text-sm text-muted-foreground">No session trace in response.</p>
                )}
              </TabsContent>

              {/* ⑤ Output */}
              <TabsContent value="output">
                <StepMeta
                  reads={['populated sessions', 'week/phase metadata']}
                  outputs={['weekly calendar', 'compromises', 'coverage report', 'held-back count']}
                  description="The program as the clients get it, and what it says about itself: what was compromised, what the package could not fill, what was substituted, which tests were placed or skipped, and how much the athlete's constraints held back."
                />
                <div className="space-y-4">
                  <ProgramOutputs program={result} />
                  <div className="flex flex-wrap gap-1">
                    {result.weeks.map((w, i) => (
                      <button
                        key={w.week_number}
                        onClick={() => setOutputWeekIdx(i)}
                        className={cn(
                          'px-3 py-1 text-xs rounded-md border transition-colors',
                          i === outputWeekIdx
                            ? 'bg-primary text-primary-foreground border-primary'
                            : 'border-border text-muted-foreground hover:bg-muted'
                        )}
                      >
                        W{w.week_number} · {w.phase}
                      </button>
                    ))}
                  </div>
                  {result.weeks[outputWeekIdx] && (
                    <WeekCalendar weekData={result.weeks[outputWeekIdx] as WeekData} isCurrentWeek={false} />
                  )}
                </div>
              </TabsContent>
            </Tabs>
          )}
        </div>}
      </div>}
    </Page>
  )
}
