import { useParams, useNavigate, Link } from 'react-router-dom'
import { Page } from '@/components/layout/Page'
import { ChevronLeft, Wand2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { SessionPanel } from '@/components/session/SessionPanel'
import { EmptyState } from '@/components/shared/EmptyState'
import { useCurrentProgram } from '@/api/programs'

export function SessionDetail() {
  const { week, day } = useParams<{ week: string; day: string }>()
  const navigate = useNavigate()
  const program = useCurrentProgram()

  // Every hook runs before the early returns below. They used to sit after
  // them, so the render where `program` arrived called more hooks than the
  // render before it — "Rendered more hooks than during the previous render",
  // on the single most common transition this page has. The session body's
  // own hooks live inside SessionPanel, which only mounts once there is a
  // program to show.

  if (!program) {
    return (
      <Page
        key="session-empty"
        className="p-6"
      >
        <EmptyState
          title="No program loaded"
          description="Generate a program first to view session details."
          action={{ label: 'Build a Program', onClick: () => navigate('/program/new') }}
          icon={<Wand2 className="size-10" />}
        />
      </Page>
    )
  }

  const weekNumber = parseInt(week ?? '1', 10)
  const weekIdx = program.weeks.findIndex((w) => w.week_number === weekNumber)
  const weekData = weekIdx >= 0 ? program.weeks[weekIdx] : undefined
  const sessions = weekData?.schedule[day ?? ''] ?? []

  if (!weekData || sessions.length === 0) {
    return (
      <Page
        key="session-not-found"
        className="p-6"
      >
        <Button variant="ghost" size="sm" asChild className="mb-4 -ml-2">
          <Link to="/program?tab=calendar"><ChevronLeft className="size-4" /> Program</Link>
        </Button>
        <EmptyState
          title="Rest day"
          description={`Week ${weekNumber} — ${day} is a rest day.`}
        />
      </Page>
    )
  }

  return (
    <Page
      key={`session-${week}-${day}`}
      className="flex h-full flex-col"
    >
      {/* Back nav */}
      <div className="border-b bg-card/50 px-6 py-3">
        <Button variant="ghost" size="sm" asChild className="-ml-2">
          <Link to="/program?tab=calendar"><ChevronLeft className="size-4" /> Program</Link>
        </Button>
      </div>

      <div className="flex-1 overflow-y-auto">
        <SessionPanel program={program} weekData={weekData} weekIndex={weekIdx} day={day ?? ''} />
      </div>
    </Page>
  )
}
