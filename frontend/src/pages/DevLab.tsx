import { useState } from 'react'
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
import { useGoals } from '@/api/goals'
import { useGenerateWithTrace } from '@/api/programs'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import { ValidationPanel } from '@/components/devlab/ValidationPanel'
import { SchedulerPanel } from '@/components/devlab/SchedulerPanel'
import { SessionsPanel } from '@/components/devlab/SessionsPanel'
import { ObjectBrowser } from '@/components/objectbrowser/ObjectBrowser'
import type { EquipmentId, TrainingLevel, TrainingPhase, TracedProgram, WeekData } from '@/api/types'

// ─── Equipment picker options ─────────────────────────────────────────────────

const EQUIPMENT_OPTIONS: { id: EquipmentId; label: string }[] = [
  { id: 'barbell', label: 'Barbell' },
  { id: 'rack', label: 'Rack' },
  { id: 'plates', label: 'Plates' },
  { id: 'kettlebell', label: 'Kettlebell' },
  { id: 'dumbbell', label: 'Dumbbell' },
  { id: 'pull_up_bar', label: 'Pull-up Bar' },
  { id: 'ruck_pack', label: 'Ruck Pack' },
  { id: 'open_space', label: 'Open Space' },
  { id: 'rings', label: 'Rings' },
  { id: 'sandbag', label: 'Sandbag' },
]

// ─── Inputs Panel ─────────────────────────────────────────────────────────────

function InputsPanel({ program }: { program: TracedProgram }) {
  const { goal, constraints } = program

  const sortedPriorities = Object.entries(goal.priorities)
    .filter(([, v]) => v > 0)
    .sort(([, a], [, b]) => b - a)

  return (
    <div className="space-y-4 max-w-2xl">
      {/* Goal */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{goal.name}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-xs text-muted-foreground">{goal.description}</p>
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
            <dt className="text-muted-foreground">Phase</dt>
            <dd className="font-mono">{constraints.training_phase}</dd>
            <dt className="text-muted-foreground">Fatigue state</dt>
            <dd className="font-mono">{constraints.fatigue_state}</dd>
            <dt className="text-muted-foreground">Equipment</dt>
            <dd className="flex flex-wrap gap-0.5 mt-0.5">
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
  const { data: goals = [], isLoading: loadingGoals } = useGoals()
  const generateMutation = useGenerateWithTrace()

  // Form state
  const [goalId, setGoalId] = useState<string>('')
  const [level, setLevel] = useState<TrainingLevel>('intermediate')
  const [phase, setPhase] = useState<TrainingPhase>('base')
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

  function toggleEquipment(id: EquipmentId) {
    setEquipment(prev =>
      prev.includes(id) ? prev.filter(e => e !== id) : [...prev, id]
    )
  }

  async function handleGenerate() {
    if (!goalId) return
    try {
      const data = await generateMutation.mutateAsync({
        goalId,
        constraints: {
          equipment,
          days_per_week: days,
          session_time_minutes: sessionTime,
          training_level: level,
          injury_flags: [],
          avoid_movements: [],
          training_phase: phase,
          periodization_week: 1,
          fatigue_state: 'normal',
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
  const canGenerate = !!goalId && !generateMutation.isPending

  const [devTab, setDevTab] = useState<'pipeline' | 'browser'>('pipeline')

  return (
    <div className="flex flex-col h-full min-h-0">
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
        </div>
      </div>

      {devTab === 'browser' && (
        <div className="flex-1 min-h-0">
          <ObjectBrowser />
        </div>
      )}

      {devTab === 'pipeline' && <div className="flex-1 overflow-y-auto">
        {/* ── Program Selector ── */}
        <div className="border-b bg-muted/20 px-6 py-4 shrink-0">
          <div className="max-w-5xl space-y-3">
            <div className="flex flex-wrap items-end gap-3">
              {/* Goal */}
              <div className="min-w-[200px]">
                <Label className="text-xs mb-1 block">Goal</Label>
                <Select value={goalId} onValueChange={setGoalId} disabled={loadingGoals}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue placeholder="Select goal…" />
                  </SelectTrigger>
                  <SelectContent>
                    {goals.map(g => (
                      <SelectItem key={g.id} value={g.id} className="text-xs">
                        {g.name}
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
                    {(['novice', 'intermediate', 'advanced', 'elite'] as TrainingLevel[]).map(l => (
                      <SelectItem key={l} value={l} className="text-xs">{l}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Phase */}
              <div className="min-w-[130px]">
                <Label className="text-xs mb-1 block">Phase</Label>
                <Select value={phase} onValueChange={v => setPhase(v as TrainingPhase)}>
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {(
                      ['base', 'build', 'peak', 'taper', 'deload', 'maintenance', 'rehab'] as TrainingPhase[]
                    ).map(p => (
                      <SelectItem key={p} value={p} className="text-xs">{p}</SelectItem>
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
              <p className="text-sm">Select a goal and click Generate to see the full pipeline trace</p>
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
                <InputsPanel program={result} />
              </TabsContent>

              {/* ② Validation */}
              <TabsContent value="validation">
                <ValidationPanel validation={result.validation} />
              </TabsContent>

              {/* ③ Schedule */}
              <TabsContent value="schedule">
                {trace ? (
                  <SchedulerPanel weeks={trace.weeks} />
                ) : (
                  <p className="text-sm text-muted-foreground">No scheduler trace in response.</p>
                )}
              </TabsContent>

              {/* ④ Sessions */}
              <TabsContent value="sessions">
                {trace ? (
                  <SessionsPanel weeks={trace.weeks} />
                ) : (
                  <p className="text-sm text-muted-foreground">No session trace in response.</p>
                )}
              </TabsContent>

              {/* ⑤ Output */}
              <TabsContent value="output">
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
    </div>
  )
}
