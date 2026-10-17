import { Link } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useStandardResults, useStandards } from '@/api/standards'
import { StandardLevelBadge } from './StandardLadder'

/**
 * On a test's scored slot: the standard it measures, where the athlete stands
 * and the number to beat for the next level — so the session says what the
 * effort is for. The words and numbers are the server's.
 */
export function StandardChip({ standardId }: { standardId: string }) {
  const { data: standards = [] } = useStandards()
  const { data: results } = useStandardResults()
  const s = standards.find((x) => x.id === standardId)
  const r = results?.standards[standardId]
  if (!s) return null
  const target = r?.current.next && r.current.nextText
    ? `${r.current.nextText} for ${r.current.next}`
    : !r && s.standardsText?.entry ? `${s.standardsText.entry} for entry` : null
  return (
    <Link to={`/profile?tab=standards&standard=${standardId}`}
          className="mt-1 inline-flex flex-wrap items-center gap-1.5 rounded-md border border-primary/30 bg-primary/5 px-2 py-1 text-[11px] text-muted-foreground hover:border-primary/60">
      <Trophy className="size-3 text-primary" aria-hidden="true" />
      <span className="font-medium text-foreground">{s.name}</span>
      {r ? (
        <>
          <span>· now <span className="font-semibold tabular-nums text-foreground">{r.current.valueText}</span></span>
          <StandardLevelBadge level={r.current.level} domain={s.domain} />
          {r.best.value !== r.current.value && <span>· best {r.best.valueText}</span>}
        </>
      ) : <span>· first result</span>}
      {target && <span>· {target}</span>}
    </Link>
  )
}
