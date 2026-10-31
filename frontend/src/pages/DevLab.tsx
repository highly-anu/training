import { useState } from 'react'
import { motion } from 'framer-motion'
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
import type { EquipmentId, FatigueState, InjuryFlagId, TrainingLevel, TracedProgram, WeekData } from '@/api/types'
import { TRAINING_LEVELS } from '@/lib/gen/clientVocab'

// ─── Equipment picker options ─────────────────────────────────────────────────

// Every id an exercise uses (EquipmentPicker leaves out the ones none does).
const EQUIPMENT_OPTIONS: { id: EquipmentId; label: string }[] = [
  { id: 'barbell', label: 'Barbell' },
  { id: 'rack', label: 'Rack' },
  { id: 'plates', label: 'Plates' },
  { id: 'kettlebell', label: 'Kettlebell' },
  { id: 'dumbbell', label: 'Dumbbell' },
  { id: 'pull_up_bar', label: 'Pull-up Bar' },
  { id: 'rings', label: 'Rings' },
  { id: 'parallettes', label: 'Parallettes' },
  { id: 'rope', label: 'Rope Climb' },
  { id: 'box', label: 'Box' },
  { id: 'rower', label: 'Rower' },
  { id: 'bike', label: 'Assault Bike' },
  { id: 'ski_erg', label: 'Ski Erg' },
  { id: 'pool', label: 'Pool' },
  { id: 'ruck_pack', label: 'Ruck Pack' },
  { id: 'sandbag', label: 'Sandbag' },
  { id: 'jump_rope', label: 'Jump Rope' },
  { id: 'resistance_band', label: 'Band' },
  { id: 'sled', label: 'Sled' },
  { id: 'tire', label: 'Tire' },
  { id: 'dip_belt', label: 'Dip Belt' },
  { id: 'ghd', label: 'GHD' },
  { id: 'medicine_ball', label: 'Medicine Ball' },
  { id: 'hangboard', label: 'Hangboard' },
  { id: 'sledgehammer', label: 'Sledgehammer' },
  { id: 'cable_machine', label: 'Cable Machine' },
  { id: 'hurdles', label: 'Hurdles' },
  { id: 'agility_ladder', label: 'Agility Ladder' },
  { id: 'training_partner', label: 'Training Partner' },
  { id: 'open_space', label: 'Open Space' },
]

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
  const isPhilosophyMode = trace?.philosophy_mode === 'synthetic_goal' || (goal.primary_sources && goal.primary_sources.length > 0)

  return (
    <div className="space-y-4 max-w-2xl">
      {/* Philosophy Sources */}
      {primarySources.length > 0 && (
        <Card className="border-violet-500/30 bg-violet-500/5">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <CardTitle className="text-sm">Philosophy Sources</CardTitle>
              {isPhilosophyMode && (
                <Badge className="text-[10px] bg-violet-500/20 text-violet-700 dark:text-violet-300 border-violet-500/40">
                  {trace?.philosophy_mode === 'synthetic_goal' ? 'Synthetic Goal' : 'Direct'}
                </Badge>
              )}
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
              Exercises and archetypes are filtered to only those from these philosophy packages.
            </p>
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

// ─── DevLab page ──────────────────────────────────────────────────────────────

export function DevLab() {
  const { data: philosophies = [], isLoading: loadingPhilosophies } = usePhilosophies()
  const { data: injuryFlagOptions = [] } = useInjuryFlags()
  const generateMutation = useGenerateWithTrace()

  // Form state
  const [philosophyId, setPhilosophyId] = useState<string>('')
  // null = the philosophy's primary track / the track's first phase, as the builder sends.
  const [trackId, setTrackId] = useState<string | null>(null)
  const [startPhaseId, setStartPhaseId] = useState<string | null>(null)
  const [level, setLevel] = useState<TrainingLevel>('intermediate')
  const [fatigue, setFatigue] = useState<FatigueState>('normal')
  const [injuryFlags, setInjuryFlags] = useState<InjuryFlagId[]>([])
  const [days, setDays] = useState(4)
  const [sessionTime, setSessionTime] = useState(60)
  const [numWeeks, setNumWeeks] = useState(2)
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

  async function handleGenerate() {
    if (!philosophyId) return
    try {
      const data = await generateMutation.mutateAsync({
        philosophyId,
        trackId: track?.id ?? null,
        startPhaseId: startPhase?.id ?? null,
        constraints: {
          equipment,
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
      })
      setResult(data)
      setActiveStep('inputs')
      setOutputWeekIdx(0)
    } catch (_) {
      // error shown via mutation.isError
    }
  }

  const trace = result?.generation_trace
  const canGenerate = !!philosophyId && !generateMutation.isPending

  const [devTab, setDevTab] = useState<'pipeline' | 'browser' | 'heatmap' | 'interactions'>('pipeline')
  const [ontologyNodeId, setOntologyNodeId] = useState<string | null>(null)
  const [ontologyFromBrowser, setOntologyFromBrowser] = useState(false)

  function openInOntology(nodeId: string) {
    setOntologyNodeId(nodeId)
    setOntologyFromBrowser(true)
    setDevTab('heatmap')
  }

  return (
    <motion.div
      key="devlab"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex flex-col h-full min-h-0"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <Terminal className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Dev Lab</h1>
        <div className="ml-4 flex gap-1">
          <button
            onClick={() => setDevTab('pipeline')}
            className={cn(
              'px-3 py-1 rounded text-xs border transition-colors',
              devTab === 'pipeline'
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            Pipeline Trace
          </button>
          <button
            onClick={() => setDevTab('browser')}
            className={cn(
              'px-3 py-1 rounded text-xs border transition-colors',
              devTab === 'browser'
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            Object Browser
          </button>
          <button
            onClick={() => setDevTab('heatmap')}
            className={cn(
              'px-3 py-1 rounded text-xs border transition-colors',
              devTab === 'heatmap'
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            Ontology
          </button>
          <button
            onClick={() => setDevTab('interactions')}
            className={cn(
              'px-3 py-1 rounded text-xs border transition-colors',
              devTab === 'interactions'
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            Model Interactions
          </button>
        </div>
      </div>

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


      {devTab === 'pipeline' && <div className="flex-1 overflow-y-auto">
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
                onClick={handleGenerate}
                disabled={!canGenerate}
                className="h-8 ml-auto"
              >
                <Play className="size-3 mr-1.5" />
                {generateMutation.isPending ? 'Running…' : 'Generate'}
              </Button>
            </div>

            {/* Equipment */}
            <div className="flex flex-wrap gap-1.5 items-center">
              <span className="text-xs text-muted-foreground">Equipment:</span>
              <button
                onClick={() => setEquipment(EQUIPMENT_OPTIONS.map(o => o.id))}
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
              {EQUIPMENT_OPTIONS.map(opt => (
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

        {/* ── Pipeline Steps ── */}
        <div className="px-6 py-4">
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
                  reads={['philosophy selection', 'athlete constraints']}
                  outputs={['priority weights', 'phase sequence', 'primary_sources (package filter)', 'constraint envelope']}
                  description="Philosophy selection generates priority weights and primary_sources (package IDs). These define what to optimize for and which exercises/archetypes are allowed. Constraints define what the athlete can do. All feed every downstream stage."
                />
                <InputsPanel program={result} />
              </TabsContent>

              {/* ② Validation */}
              <TabsContent value="validation">
                <StepMeta
                  reads={['goal priorities', 'archetypes', 'modalities', 'equipment', 'injury flags']}
                  outputs={['feasibility flag', 'equipment warnings', 'time-cap checks', 'injury conflicts']}
                  description="Pre-flight check before building any sessions. Fails fast on impossible constraints so the generator never runs on infeasible inputs."
                />
                <ValidationPanel validation={result.validation} />
              </TabsContent>

              {/* ③ Schedule */}
              <TabsContent value="schedule">
                <StepMeta
                  reads={['phase priority weights', 'framework.sessions_per_week', 'framework.cadence_options', 'modality.recovery_cost / recovery_hours_min', 'modality.incompatible_in_session_with', 'phase.week_templates', 'training contract modules']}
                  outputs={['session counts per modality', 'day-of-week assignment', 'deload flag']}
                  description="Converts priority weights into session counts via the framework, then places them on the framework's cadence days, hardest first: a modality keeps its recovery window from itself and two high-cost modalities 48 h apart, checked against the days before and after and last week's end. A phase that writes its own week (week_templates) takes the source's days instead, and a training contract places its modules itself — alternating them, spacing each module's sessions and keeping heavily loaded body regions apart. Every shipped package does one or the other; the scheduler places blends a contract philosophy leads and packages with neither."
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
                  description="Each session gets its archetype: a template day the next named workout of its category the athlete can do as written, a contract its module's, a test its own. Only a session left to choose is scored — after the hard filters (modality, phase, level, equipment, time): +6 equipment met, −3 used in the last 14, ±3 day fit, injury and blocked-equipment penalties, −2/−1 per body region a session a day or two before loaded heavily; ties go to the least recently used, then the first authored. Slots fill from the archetype's own package and those its philosophy borrows from: named exercises (in order where the slot says so) or its pattern and category, filtered by equipment, injury, level unlocks, phase exclusions and the taper rule; −2 per recent use, +0.5 for a pattern and for an unlock, ties to the first authored. A main lift stays the same through a phase. Load comes from the framework's progression model for the modality where it overrides one, else the modality's."
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
                  reads={['populated sessions', 'week/phase metadata', 'complementary recovery work']}
                  outputs={['weekly calendar', 'volume summary']}
                  description="Final program — all ontology decisions resolved into a weekly training calendar."
                />
                <div className="space-y-4">
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
        </div>
      </div>}
    </motion.div>
  )
}
