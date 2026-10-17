import { Link } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useStandardSuggestions } from '@/api/standards'
import { SuggestionRow } from '@/components/standards/SuggestionRow'

/**
 * Today: results logged sessions suggest that are still waiting — a test from
 * an earlier day, or a single that beat the current result. Today's own test
 * shows its results in TestDayCard, so those standards are left out here.
 * Nothing when there is nothing to decide.
 */
export function ResultsToConfirmCard({ exclude = [] }: { exclude?: string[] }) {
  const { data: suggestions = [] } = useStandardSuggestions()
  const rows = suggestions.filter((s) => !exclude.includes(s.benchmarkId))
  if (rows.length === 0) return null
  return (
    <div className="rounded-lg border border-border bg-card p-4 space-y-3">
      <div className="flex items-center gap-2">
        <Trophy className="size-4 text-primary" aria-hidden="true" />
        <p className="text-sm font-semibold">Results to confirm</p>
      </div>
      <div className="space-y-2">
        {rows.slice(0, 3).map((s) => <SuggestionRow key={s.id} suggestion={s} />)}
      </div>
      {rows.length > 3 && (
        <Link to="/profile?tab=standards" className="text-[11px] text-muted-foreground underline underline-offset-2 hover:text-foreground">
          {rows.length - 3} more in Profile ▸ Standards
        </Link>
      )}
    </div>
  )
}
