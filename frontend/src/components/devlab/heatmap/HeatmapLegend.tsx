import type { HeatmapGraphData } from './useHeatmapData'

interface HeatmapLegendProps {
  data: HeatmapGraphData
  totalExercisesInOntology: number
}

export function HeatmapLegend({ data, totalExercisesInOntology }: HeatmapLegendProps) {
  const coverage = totalExercisesInOntology > 0
    ? Math.round((data.uniqueExercisesUsed / totalExercisesInOntology) * 100)
    : 0
  const activePaths = data.edges.filter(e => e.rawCount > 0).length
  const totalPaths = data.edges.length

  return (
    <div className="flex items-center gap-6 px-2 text-xs text-muted-foreground">
      {/* Color scale */}
      <div className="flex items-center gap-2">
        <span>cold</span>
        <div className="flex h-2.5 rounded-full overflow-hidden w-24">
          {Array.from({ length: 10 }, (_, i) => (
            <div
              key={i}
              className="flex-1"
              style={{
                backgroundColor: `rgba(148, 163, 184, ${0.05 + (i / 9) * 0.95})`,
              }}
            />
          ))}
        </div>
        <span>hot</span>
      </div>

      {/* Stats */}
      <div className="flex items-center gap-4 font-mono">
        <span>
          {data.uniqueExercisesUsed}/{totalExercisesInOntology} exercises ({coverage}%)
        </span>
        <span>
          {activePaths}/{totalPaths} paths active
        </span>
        <span>
          {data.totalExerciseUsages} total usages
        </span>
      </div>
    </div>
  )
}
