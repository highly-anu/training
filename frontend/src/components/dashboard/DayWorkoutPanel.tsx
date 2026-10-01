import { X } from 'lucide-react'
import { SessionPanel } from '@/components/session/SessionPanel'
import { useProgramStore } from '@/store/programStore'
import type { WeekData } from '@/api/types'

interface DayWorkoutPanelProps {
  weekData: WeekData
  weekIndex: number
  day: string
  onClose: () => void
}

/** Home's side panel: a sticky day header over the shared session body. */
export function DayWorkoutPanel({ weekData, weekIndex, day, onClose }: DayWorkoutPanelProps) {
  const sessions = weekData.schedule[day] ?? []
  const currentProgram = useProgramStore((s) => s.currentProgram)

  if (sessions.length === 0 || !currentProgram) return null

  return (
    <>
      {/* Sticky header */}
      <div className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-border bg-card/95 px-5 py-3 backdrop-blur-sm">
        <div>
          <p className="text-sm font-semibold">{day}</p>
          <p className="text-[11px] text-muted-foreground">
            Week {weekData.week_number}
            <span className="ml-1 capitalize">
              · {sessions.filter((s) => s.archetype).map((s) => s.modality.replace(/_/g, ' ')).join(' + ')}
            </span>
          </p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="shrink-0 rounded-md p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
          aria-label="Close"
        >
          <X className="size-4" />
        </button>
      </div>

      <SessionPanel program={currentProgram} weekData={weekData} weekIndex={weekIndex} day={day} compact />
    </>
  )
}
