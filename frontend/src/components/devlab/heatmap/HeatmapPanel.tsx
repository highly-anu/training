import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X, Loader2, ChevronLeft } from 'lucide-react'
import { HeatmapGraph, getConnectedNodeIds, prunePhilosophyScope } from './HeatmapGraph'
import type { HeatmapSortMode } from './HeatmapGraph'
import { HeatmapControls } from './HeatmapControls'
import { useHeatmapData } from './useHeatmapData'
import type { HeatNode, HeatmapGraphData } from './useHeatmapData'
import { useOntology } from '@/api/ontology'
// Goals deprecated
import { useGenerateWithTrace } from '@/api/programs'
import type { TracedProgram, EquipmentId, TrainingLevel, TrainingPhase, ModalityId } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'

// ─── Layer ordering ───────────────────────────────────────────────────────────

const LAYER_ORDER_KEYS = ['philosophy', 'framework', 'modality', 'archetype', 'exercise_group'] as const
type LayerKey = typeof LAYER_ORDER_KEYS[number]

// ─── Node info panel ──────────────────────────────────────────────────────────

function nodeColor(node: HeatNode): string {
  if (node.modalityHint && (node.modalityHint as string) in MODALITY_COLORS) {
    return MODALITY_COLORS[node.modalityHint as ModalityId].hex
  }
  if (node.layer === 'philosophy') return '#a78bfa'
  if (node.layer === 'framework') return '#60a5fa'
  return '#94a3b8'
}

function NodeInfoPanel({
  node,
  graphData,
  onClose,
  isLocked,
  scopedNodeIds,
  activePackage,
}: {
  node: HeatNode
  graphData: HeatmapGraphData
  onClose: () => void
  isLocked: boolean
  scopedNodeIds: Set<string> | null
  activePackage: string | null
}) {
  const color = nodeColor(node)
  const heatPct = Math.round(node.heat * 100)
  const layerLabel = node.layer === 'exercise_group' ? 'movement pattern' : node.layer.replace(/_/g, ' ')

  // Display name: strip the " (N)" count suffix added to exercise_group labels
  const displayName = node.layer === 'exercise_group'
    ? node.label.replace(/\s*\(\d+\)$/, '').trim()
    : node.label

  // Direct parents and children — scoped to the active selection/lock if present
  const inScope = (id: string) => !scopedNodeIds || scopedNodeIds.has(id)

  const parentNodes = graphData.edges
    .filter(e => e.target === node.id && inScope(e.source))
    .map(e => graphData.nodes.find(n => n.id === e.source))
    .filter(Boolean) as HeatNode[]

  const childNodes = graphData.edges
    .filter(e => e.source === node.id && inScope(e.target))
    .map(e => graphData.nodes.find(n => n.id === e.target))
    .filter(Boolean) as HeatNode[]

  // Exercises for exercise_group nodes — scoped to active package when set
  const groupKey = node.id.replace('exercise_group::', '')
  const exercises = node.layer === 'exercise_group'
    ? [...(graphData.exercisesByGroup[groupKey] ?? [])]
        .filter(ex => !activePackage || !ex._package || ex._package === activePackage)
        .sort((a, b) => b.rawCount - a.rawCount)
    : []
  // Modality-only: exercise_groups reachable through scoped child archetypes
  const movementNodes: HeatNode[] = node.layer === 'modality'
    ? [...new Map(
        childNodes
          .filter(c => c.layer === 'archetype')
          .flatMap(arch =>
            graphData.edges
              .filter(e => e.source === arch.id && inScope(e.target))
              .map(e => graphData.nodes.find(n => n.id === e.target))
              .filter((n): n is HeatNode => !!n && n.layer === 'exercise_group')
          )
          .map(n => [n.id, n])
      ).values()]
      .sort((a, b) => b.heat - a.heat)
    : []

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 6 }}
      transition={{ duration: 0.2 }}
      className="rounded-lg border border-border bg-card p-4 space-y-3"
    >
      {/* Header */}
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <span
            className="inline-block text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded mb-1.5"
            style={{ backgroundColor: `${color}20`, color }}
          >
            {layerLabel}
          </span>
          <p className="text-sm font-semibold capitalize">{displayName}</p>
        </div>
        {isLocked && (
          <button
            onClick={onClose}
            className="shrink-0 text-muted-foreground hover:text-foreground transition-colors"
          >
            <X className="size-4" />
          </button>
        )}
      </div>

      {/* Heat bar */}
      <div className="space-y-1">
        {node.rawCount > 0 && (
          <div className="flex items-center justify-between">
            <span className="text-[11px] text-muted-foreground">{node.rawCount} usages</span>
            <span className="text-[11px] font-mono" style={{ color }}>{heatPct}% heat</span>
          </div>
        )}
        <div className="h-1 rounded-full bg-muted overflow-hidden">
          <motion.div
            className="h-full rounded-full"
            style={{ backgroundColor: color }}
            initial={{ width: 0 }}
            animate={{ width: `${heatPct}%` }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
          />
        </div>
      </div>

      {movementNodes.length > 0 && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Movements</p>
          <div className="flex flex-wrap gap-1">
            {movementNodes.map(m => {
              const mColor = nodeColor(m)
              const mName = m.label.replace(/\s*\(\d+\)$/, '').trim()
              const mHeat = Math.round(m.heat * 100)
              return (
                <span
                  key={m.id}
                  className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono border"
                  style={m.heat > 0
                    ? { borderColor: `${mColor}40`, color: mColor, backgroundColor: `${mColor}10` }
                    : { borderColor: 'hsl(var(--border))', color: '#64748b' }
                  }
                >
                  {mName}
                  {mHeat > 0 && <span className="opacity-60">{mHeat}%</span>}
                </span>
              )
            })}
          </div>
        </div>
      )}

      {(parentNodes.length > 0 || childNodes.length > 0) && (
        <div className="grid grid-cols-2 gap-3">
          {parentNodes.length > 0 && (
            <div>
              <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Via</p>
              <div className="space-y-1">
                {parentNodes.slice(0, 4).map(p => (
                  <div key={p.id} className="flex items-center gap-1.5">
                    <div className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: nodeColor(p) }} />
                    <span className="text-[11px] text-foreground truncate">{p.label}</span>
                  </div>
                ))}
                {parentNodes.length > 4 && (
                  <span className="text-[10px] text-muted-foreground">+{parentNodes.length - 4} more</span>
                )}
              </div>
            </div>
          )}
          {childNodes.length > 0 && (
            <div>
              <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Leads to</p>
              <div className="space-y-1">
                {childNodes.slice(0, 4).map(c => {
                  const baseName = c.label.replace(/\s*\(\d+\)$/, '').trim()
                  let countLabel = ''
                  if (c.layer === 'exercise_group') {
                    const gKey = c.id.replace('exercise_group::', '')
                    const allEx = graphData.exercisesByGroup[gKey] ?? []
                    const scopedEx = activePackage
                      ? allEx.filter(ex => !ex._package || ex._package === activePackage)
                      : allEx
                    countLabel = ` (${scopedEx.length})`
                  }
                  return (
                    <div key={c.id} className="flex items-center gap-1.5">
                      <div className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: nodeColor(c) }} />
                      <span className="text-[11px] text-foreground truncate">{baseName}{countLabel}</span>
                    </div>
                  )
                })}
                {childNodes.length > 4 && (
                  <span className="text-[10px] text-muted-foreground">+{childNodes.length - 4} more</span>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Exercise list for exercise_group */}
      {exercises.length > 0 && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">
            Exercises · {exercises.length}
          </p>
          <div className="space-y-2">
            {exercises.slice(0, 8).map(ex => (
              <div key={ex.id} className="space-y-0.5">
                <div className="flex items-center gap-2">
                  <span className="text-[11px] text-foreground flex-1 truncate min-w-0">{ex.name}</span>
                  <div className="w-14 h-1 rounded-full bg-muted overflow-hidden shrink-0">
                    <div
                      className="h-full rounded-full"
                      style={{ width: `${Math.round(ex.heat * 100)}%`, backgroundColor: color }}
                    />
                  </div>
                  <span className="text-[10px] font-mono text-muted-foreground w-4 text-right shrink-0">
                    {ex.rawCount > 0 ? ex.rawCount : ''}
                  </span>
                </div>
                {ex.movement_patterns.length > 0 && (
                  <div className="flex flex-wrap gap-1 pl-0.5">
                    {ex.movement_patterns.map(mp => (
                      <span key={mp} className="text-[9px] font-mono text-muted-foreground/60">
                        {mp.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            ))}
            {exercises.length > 8 && (
              <p className="text-[10px] text-muted-foreground">+{exercises.length - 8} more exercises</p>
            )}
          </div>
        </div>
      )}
    </motion.div>
  )
}

// ─── Panel ────────────────────────────────────────────────────────────────────

interface HeatmapPanelProps {
  program: TracedProgram | null
  constraints?: {
    equipment: EquipmentId[]
    days_per_week: number
    session_time_minutes: number
    training_level: TrainingLevel
    training_phase: TrainingPhase
    numWeeks: number
  }
  initialLockedNode?: string | null
  onBack?: () => void
}

export function HeatmapPanel({ program, constraints, initialLockedNode, onBack }: HeatmapPanelProps) {
  const { data: ontology, isLoading: ontologyLoading } = useOntology()
  // Goals deprecated - philosophy-based only
  const goals: any[] = []
  const generateMutation = useGenerateWithTrace()

  const [weekRange, setWeekRange] = useState<[number, number]>([1, program?.weeks.length ?? 1])
  const [highlightedNode, setHighlightedNode] = useState<string | null>(null)
  const [selectionByLayer, setSelectionByLayer] = useState<Map<LayerKey, string>>(new Map())
  const [lockedNodeId, setLockedNodeId] = useState<string | null>(null) // 2nd click — drives layout centering
  const lockedNodeRef = useRef<string | null>(null)
  lockedNodeRef.current = lockedNodeId

  // Seed initial locked node into the correct layer slot
  useEffect(() => {
    if (!initialLockedNode) return
    const layer = LAYER_ORDER_KEYS.find(l => initialLockedNode.startsWith(`${l}::`))
    if (layer) setSelectionByLayer(new Map([[layer, initialLockedNode]]))
  }, [initialLockedNode])

  // Ordered top-layer first
  const selectedNodes = useMemo(() =>
    LAYER_ORDER_KEYS.filter(l => selectionByLayer.has(l)).map(l => selectionByLayer.get(l)!),
    [selectionByLayer]
  )
  const lowestSelectedId = selectedNodes.at(-1) ?? null

  // ESC: if a node is locked, first Esc just unlocks (keeps selected). Next Esc removes deepest layer.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (lockedNodeRef.current !== null) {
        setLockedNodeId(null)
        return
      }
      setSelectionByLayer(prev => {
        if (prev.size === 0) return prev
        const deepest = [...LAYER_ORDER_KEYS].reverse().find(l => prev.has(l))
        if (!deepest) return prev
        const next = new Map(prev)
        next.delete(deepest)
        return next
      })
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const [sortMode, setSortMode] = useState<HeatmapSortMode>('alpha')
  const [compareMode, setCompareMode] = useState(false)
  const [compareGoalId, setCompareGoalId] = useState<string>('')
  const [compareProgram, setCompareProgram] = useState<TracedProgram | null>(null)
  const [compareWeekRange, setCompareWeekRange] = useState<[number, number]>([1, 1])

  const graphData = useHeatmapData(ontology, program, weekRange)
  const compareGraphData = useHeatmapData(ontology, compareProgram, compareWeekRange)

  const handleWeekRangeChange = useCallback((range: [number, number]) => setWeekRange(range), [])
  const handleCompareWeekRangeChange = useCallback((range: [number, number]) => setCompareWeekRange(range), [])

  const handleHoverNode = useCallback((id: string | null) => {
    setHighlightedNode(id)
  }, [])

  const handleClickNode = useCallback((id: string) => {
    const layer = LAYER_ORDER_KEYS.find(l => id.startsWith(`${l}::`)) ?? null
    if (!layer) return

    setSelectionByLayer(prev => {
      const alreadySelected = prev.get(layer) === id
      if (alreadySelected && lockedNodeRef.current === id) {
        // 3rd click on locked node: deselect + unlock
        setLockedNodeId(null)
        const next = new Map(prev)
        next.delete(layer)
        return next
      }
      if (alreadySelected) {
        // 2nd click on selected node: promote to locked (layout reorganizes)
        setLockedNodeId(id)
        return prev  // selection unchanged
      }
      // 1st click (or new node at same layer): select, clear lock if layer changes
      if (lockedNodeRef.current !== null) {
        const lockedLayer = LAYER_ORDER_KEYS.find(l => lockedNodeRef.current!.startsWith(`${l}::`))
        if (lockedLayer !== layer) setLockedNodeId(null)
      }
      const next = new Map(prev)
      next.set(layer, id)
      return next
    })
  }, [])

  // Remove the deepest active selection (and unlock if the cleared node was locked)
  const clearLowest = useCallback(() => {
    setSelectionByLayer(prev => {
      const deepest = [...LAYER_ORDER_KEYS].reverse().find(l => prev.has(l))
      if (!deepest) return prev
      const removedId = prev.get(deepest)
      if (removedId && lockedNodeRef.current === removedId) setLockedNodeId(null)
      const next = new Map(prev)
      next.delete(deepest)
      return next
    })
  }, [])

  async function handleGenerateComparison() {
    if (!compareGoalId || !constraints) return
    try {
      const data = await generateMutation.mutateAsync({
        philosophyId: compareGoalId,
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
    } catch { /* handled by TanStack mutation */ }
  }

  // Scoped connected set — mirrors HeatmapGraph's connectedSet logic.
  // Used to filter NodeInfoPanel's parent/child/movement lists to only in-scope nodes.
  const scopedNodeIds = useMemo(() => {
    if (!graphData || selectedNodes.length === 0) return null
    let result: Set<string> | null = null
    for (const nodeId of selectedNodes) {
      const raw = getConnectedNodeIds(nodeId, graphData.edges)
      if (nodeId.startsWith('philosophy::')) {
        prunePhilosophyScope(raw, nodeId.slice('philosophy::'.length), graphData.nodes, graphData.edges)
      }
      if (result === null) {
        result = raw
      } else {
        for (const id of [...result]) {
          if (!raw.has(id)) result.delete(id)
        }
      }
    }
    return result
  }, [selectedNodes, graphData])

  const activePackage = useMemo(() => {
    const philNode = selectedNodes.find(n => n.startsWith('philosophy::'))
    return philNode ? philNode.slice('philosophy::'.length) : null
  }, [selectedNodes])

  if (ontologyLoading) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground text-sm">
        <Loader2 className="h-4 w-4 animate-spin mr-2" />
        Loading ontology...
      </div>
    )
  }

  if (!graphData) return null

  const hasHeat = graphData.maxHeat > 0
  const lowestSelectedNodeData = lowestSelectedId ? graphData.nodes.find(n => n.id === lowestSelectedId) ?? null : null
  const hoveredNodeData = highlightedNode ? graphData.nodes.find(n => n.id === highlightedNode) ?? null : null
  const infoNode = hoveredNodeData ?? lowestSelectedNodeData

  return (
    <div className="space-y-3">
      {onBack && (
        <button
          onClick={onBack}
          className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
        >
          <ChevronLeft className="size-3" />
          Object Browser
        </button>
      )}
      {program && (
        <HeatmapControls
          program={program}
          weekRange={weekRange}
          onWeekRangeChange={handleWeekRangeChange}
          compareMode={compareMode}
          onCompareModeToggle={() => setCompareMode(!compareMode)}
        />
      )}

      {/* Breadcrumb chips — active multi-layer selection */}
      {selectedNodes.length > 0 && (
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="text-[10px] text-muted-foreground/60 uppercase tracking-wider shrink-0">Selection</span>
          {selectedNodes.map(nodeId => {
            const layer = LAYER_ORDER_KEYS.find(l => nodeId.startsWith(`${l}::`))!
            const node = graphData.nodes.find(n => n.id === nodeId)
            const label = node?.label ?? nodeId.replace(`${layer}::`, '')
            return (
              <button
                key={nodeId}
                onClick={() => setSelectionByLayer(prev => { const n = new Map(prev); n.delete(layer); return n })}
                className="flex items-center gap-1 px-2 py-0.5 rounded border border-border/60 text-[10px] font-mono text-muted-foreground hover:text-foreground hover:border-muted-foreground/50 transition-colors group"
              >
                <span className="text-muted-foreground/40 group-hover:text-muted-foreground/60">{layer}</span>
                <span className="text-foreground/80">{label}</span>
                <X className="size-2.5 opacity-40 group-hover:opacity-70" />
              </button>
            )
          })}
          {selectedNodes.length > 1 && (
            <button
              onClick={() => setSelectionByLayer(new Map())}
              className="px-1.5 py-0.5 text-[10px] text-muted-foreground/40 hover:text-muted-foreground transition-colors"
            >
              clear all
            </button>
          )}
        </div>
      )}

      {/* Sort control */}
      <div className="flex items-center gap-1.5">
        <span className="text-[10px] text-muted-foreground uppercase tracking-wider">Sort</span>
        <button
          onClick={() => setSortMode('alpha')}
          className={`px-2 py-0.5 rounded text-[10px] font-mono transition-colors border ${
            sortMode === 'alpha'
              ? 'border-primary/50 bg-primary/10 text-primary'
              : 'border-border text-muted-foreground hover:text-foreground hover:border-muted-foreground/40'
          }`}
        >
          A→Z
        </button>
        <button
          onClick={() => setSortMode(sortMode === 'heat-desc' ? 'heat-asc' : 'heat-desc')}
          className={`px-2 py-0.5 rounded text-[10px] font-mono transition-colors border ${
            sortMode !== 'alpha'
              ? 'border-primary/50 bg-primary/10 text-primary'
              : 'border-border text-muted-foreground hover:text-foreground hover:border-muted-foreground/40'
          }`}
          title={!hasHeat ? 'Sorts by incoming connections (generate a program to sort by heat)' : undefined}
        >
          {sortMode === 'heat-asc' ? 'Cold→Hot' : 'Hot→Cold'}
        </button>
      </div>

      <div className={compareMode && program ? 'grid grid-cols-2 gap-3' : ''}>
        <div>
          {compareMode && program && (
            <div className="text-xs font-mono text-muted-foreground mb-1 px-1">
              {program.goal?.name ?? 'Program A'}
            </div>
          )}
          <HeatmapGraph
            data={graphData}
            highlightedNode={highlightedNode}
            selectedNodes={selectedNodes}
            lockedNode={lockedNodeId}
            onHoverNode={handleHoverNode}
            onClickNode={handleClickNode}
            sortMode={sortMode}
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
                  selectedNodes={selectedNodes}
                  lockedNode={lockedNodeId}
                  onHoverNode={handleHoverNode}
                  onClickNode={handleClickNode}
                  sortMode={sortMode}
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
                        .filter(g => g.id !== program?.goal?.id)
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

      {/* Node info panel — shows on hover; frozen on selection; X appears when any selection active.
          Key changes when selection changes (not on hover) so it remounts correctly. */}
      <AnimatePresence>
        {infoNode && (
          <NodeInfoPanel
            key={selectedNodes.join(',') || '__hover__'}
            node={infoNode}
            graphData={graphData}
            onClose={clearLowest}
            isLocked={lockedNodeId !== null}
            scopedNodeIds={scopedNodeIds}
            activePackage={activePackage}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
