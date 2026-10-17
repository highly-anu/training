import { Link } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useStandardSuggestions } from '@/api/standards'
import { SuggestionRow } from '@/components/standards/SuggestionRow'
import { parseSessionKey } from '@/lib/sessionKeys'

/**
 * Today: results logged sessions suggest that are still waiting — a test from
 * an earlier day, a single that beat the current result, an imported run.
 * What TestDayCard shows — today's test slots, by today's day key — is left
 * out here; anything else on a standard tested today still shows.
 * Nothing when there is nothing to decide.
 */
export function ResultsToConfirmCard({ testDayKey, testStandards = [] }: {
  testDayKey?: string
  testStandards?: string[]
}) {
  const { data: suggestions = [] } = useStandardSuggestions()
  const rows = suggestions.filter((s) => !(s.origin === 'test_slot' && testStandards.includes(s.benchmarkId)
    && parseSessionKey(s.sessionKey ?? '')?.dayKey === testDayKey))
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
