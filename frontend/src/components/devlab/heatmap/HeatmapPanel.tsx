import { useCallback, useState } from 'react'
import { HeatmapGraph } from './HeatmapGraph'
import { HeatmapControls } from './HeatmapControls'
import { HeatmapLegend } from './HeatmapLegend'
import { useHeatmapData } from './useHeatmapData'
import { useOntology } from '@/api/ontology'
import { useGoals } from '@/api/goals'
import { useGenerateWithTrace } from '@/api/programs'
import type { TracedProgram, EquipmentId, TrainingLevel, TrainingPhase } from '@/api/types'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Loader2, GitCompare } from 'lucide-react'

interface HeatmapPanelProps {
  program: TracedProgram | null
  /** Constraints from the DevLab form, used when generating comparison program */
  constraints?: {
    equipment: EquipmentId[]
    days_per_week: number
    session_time_minutes: number
    training_level: TrainingLevel
    training_phase: TrainingPhase
    numWeeks: number
  }
}

export function HeatmapPanel({ program, constraints }: HeatmapPanelProps) {
  const { data: ontology, isLoading: ontologyLoading } = useOntology()
  const { data: goals = [] } = useGoals()
  const generateMutation = useGenerateWithTrace()

  // State
  const [weekRange, setWeekRange] = useState<[number, number]>([1, program?.weeks.length ?? 1])
  const [highlightedNode, setHighlightedNode] = useState<string | null>(null)
  const [lockedNode, setLockedNode] = useState<string | null>(null)
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null)

  // Comparison mode
  const [compareMode, setCompareMode] = useState(false)
  const [compareGoalId, setCompareGoalId] = useState<string>('')
  const [compareProgram, setCompareProgram] = useState<TracedProgram | null>(null)
  const [compareWeekRange, setCompareWeekRange] = useState<[number, number]>([1, 1])

  // Build graph data
  const graphData = useHeatmapData(ontology, program, weekRange)
  const compareGraphData = useHeatmapData(ontology, compareProgram, compareWeekRange)

  const totalExercises = ontology?.exercises.length ?? 0

  const handleWeekRangeChange = useCallback((range: [number, number]) => {
    setWeekRange(range)
  }, [])

  const handleCompareWeekRangeChange = useCallback((range: [number, number]) => {
    setCompareWeekRange(range)
  }, [])

  // Node interaction
  const handleHoverNode = useCallback((id: string | null) => {
    if (!lockedNode) setHighlightedNode(id)
  }, [lockedNode])

  const handleClickNode = useCallback((id: string) => {
    // If clicking an exercise group, toggle expansion
    if (id.startsWith('exercise_group::')) {
      setExpandedGroup(prev => prev === id ? null : id)
      return
    }
    // Toggle lock
    setLockedNode(prev => prev === id ? null : id)
  }, [])

  // Generate comparison program
  async function handleGenerateComparison() {
    if (!compareGoalId || !constraints) return
    try {
      const data = await generateMutation.mutateAsync({
        goalId: compareGoalId,
        constraints: {
          equipment: constraints.equipment,
          days_per_week: constraints.days_per_week,
          session_time_minutes: constraints.session_time_minutes,
          training_level: constraints.training_level,
          training_phase: constraints.training_phase,
          periodization_week: 1,
          fatigue_state: 'normal',
          injury_flags: [],
          avoid_movements: [],
        },
        numWeeks: constraints.numWeeks,
      })
      setCompareProgram(data)
      setCompareWeekRange([1, data.weeks.length])
    } catch { /* mutation error handled by TanStack */ }
  }

  // Loading / empty states
  if (ontologyLoading) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground text-sm">
        <Loader2 className="h-4 w-4 animate-spin mr-2" />
        Loading ontology...
      </div>
    )
  }

  if (!program) {
    return (
      <div className="flex flex-col items-center justify-center h-64 text-muted-foreground text-sm gap-2">
        <GitCompare className="h-8 w-8 opacity-30" />
        <p>Generate a program to see the heatmap</p>
      </div>
    )
  }

  if (!graphData) return null

  return (
    <div className="space-y-3">
      {/* Controls */}
      <HeatmapControls
        program={program}
        weekRange={weekRange}
        onWeekRangeChange={handleWeekRangeChange}
        compareMode={compareMode}
        onCompareModeToggle={() => setCompareMode(!compareMode)}
      />

      {/* Graph area */}
      <div className={compareMode ? 'grid grid-cols-2 gap-3' : ''}>
        <div>
          {compareMode && (
            <div className="text-xs font-mono text-muted-foreground mb-1 px-1">
              {program.goal?.name ?? 'Program A'}
            </div>
          )}
          <HeatmapGraph
            data={graphData}
            highlightedNode={highlightedNode}
            lockedNode={lockedNode}
            onHoverNode={handleHoverNode}
            onClickNode={handleClickNode}
            expandedGroup={expandedGroup}
          />
        </div>

        {compareMode && (
          <div>
            {compareProgram && compareGraphData ? (
              <>
                <div className="text-xs font-mono text-muted-foreground mb-1 px-1">
                  {compareProgram.goal?.name ?? 'Program B'}
                </div>
                <HeatmapControls
                  program={compareProgram}
                  weekRange={compareWeekRange}
                  onWeekRangeChange={handleCompareWeekRangeChange}
                  compareMode={false}
                  onCompareModeToggle={() => {}}
                />
                <HeatmapGraph
                  data={compareGraphData}
                  highlightedNode={highlightedNode}
                  lockedNode={lockedNode}
                  onHoverNode={handleHoverNode}
                  onClickNode={handleClickNode}
                  expandedGroup={expandedGroup}
                />
              </>
            ) : (
              <div className="flex flex-col items-center justify-center h-64 border border-dashed border-border rounded-lg gap-3">
                <p className="text-xs text-muted-foreground">Select a goal to compare</p>
                <div className="flex items-center gap-2">
                  <Select value={compareGoalId} onValueChange={setCompareGoalId}>
                    <SelectTrigger className="w-48 h-8 text-xs">
                      <SelectValue placeholder="Choose goal..." />
                    </SelectTrigger>
                    <SelectContent>
                      {goals
                        .filter(g => g.id !== program.goal?.id)
                        .map(g => (
                          <SelectItem key={g.id} value={g.id} className="text-xs">
                            {g.name}
                          </SelectItem>
                        ))}
                    </SelectContent>
                  </Select>
                  <Button
                    size="sm"
                    className="h-8 text-xs"
                    onClick={handleGenerateComparison}
                    disabled={!compareGoalId || generateMutation.isPending}
                  >
                    {generateMutation.isPending ? (
                      <Loader2 className="h-3 w-3 animate-spin" />
                    ) : (
                      'Generate'
                    )}
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Legend */}
      <HeatmapLegend data={graphData} totalExercisesInOntology={totalExercises} />

      {/* Locked node info */}
      {lockedNode && (
        <div className="px-2 py-1.5 text-xs bg-muted/50 rounded border border-border">
          <span className="text-muted-foreground">Selected: </span>
          <span className="font-mono">
            {graphData.nodes.find(n => n.id === lockedNode)?.label ?? lockedNode}
          </span>
          <span className="text-muted-foreground ml-2">
            ({graphData.nodes.find(n => n.id === lockedNode)?.rawCount ?? 0} usages)
          </span>
          <button
            className="ml-2 text-muted-foreground hover:text-foreground"
            onClick={() => setLockedNode(null)}
          >
            ×
          </button>
        </div>
      )}
    </div>
  )
}
