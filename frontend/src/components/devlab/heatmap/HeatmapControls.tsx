import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Slider } from '@/components/ui/slider'
import { Badge } from '@/components/ui/badge'
import { Play, Pause, RotateCcw } from 'lucide-react'
import type { TracedProgram } from '@/api/types'

interface HeatmapControlsProps {
  program: TracedProgram | null
  weekRange: [number, number]
  onWeekRangeChange: (range: [number, number]) => void
  compareMode: boolean
  onCompareModeToggle: () => void
}

export function HeatmapControls({
  program,
  weekRange,
  onWeekRangeChange,
  compareMode,
  onCompareModeToggle,
}: HeatmapControlsProps) {
  const [playing, setPlaying] = useState(false)
  const intervalRef = useRef<ReturnType<typeof setInterval>>(undefined)
  const weekRef = useRef(weekRange[1])
  const totalWeeks = program?.weeks.length ?? 0

  // Keep ref in sync with prop
  weekRef.current = weekRange[1]

  // Current phase for the end of the range
  const currentPhase = program?.weeks.find(w => w.week_number === weekRange[1])?.phase

  useEffect(() => {
    if (playing && totalWeeks > 0) {
      intervalRef.current = setInterval(() => {
        const next = weekRef.current >= totalWeeks ? 1 : weekRef.current + 1
        onWeekRangeChange([1, next])
        if (next >= totalWeeks) setPlaying(false)
      }, 800)
    }
    return () => clearInterval(intervalRef.current)
  }, [playing, totalWeeks, onWeekRangeChange])

  if (!program || totalWeeks === 0) return null

  return (
    <div className="flex items-center gap-4 px-2">
      {/* Week animation controls */}
      <div className="flex items-center gap-2 flex-1 min-w-0">
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0"
          onClick={() => setPlaying(!playing)}
        >
          {playing ? <Pause className="h-3.5 w-3.5" /> : <Play className="h-3.5 w-3.5" />}
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0"
          onClick={() => { setPlaying(false); onWeekRangeChange([1, totalWeeks]) }}
        >
          <RotateCcw className="h-3.5 w-3.5" />
        </Button>
        <Slider
          value={[weekRange[1]]}
          min={1}
          max={totalWeeks}
          step={1}
          onValueChange={([v]) => { setPlaying(false); onWeekRangeChange([1, v]) }}
          className="flex-1"
        />
        <span className="text-xs font-mono text-muted-foreground shrink-0 w-20 text-right">
          W1–{weekRange[1]}
        </span>
        {currentPhase && (
          <Badge variant="outline" className="text-[10px] shrink-0">
            {currentPhase}
          </Badge>
        )}
      </div>

      {/* Compare toggle */}
      <Button
        variant={compareMode ? 'default' : 'outline'}
        size="sm"
        className="text-xs h-7 shrink-0"
        onClick={onCompareModeToggle}
      >
        Compare
      </Button>
    </div>
  )
}
