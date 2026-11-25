import { useNavigate } from 'react-router-dom'
import { CalendarDays, Layers, Wand2 } from 'lucide-react'
import type { ShareDocument } from '@/api/shares'
import { Button } from '@/components/ui/button'
import { NEUTRAL_HEX } from '@/lib/dataColors'
import { PHASE_COLORS } from '@/lib/phaseColors'
import type { PhaseKind } from '@/api/types'
import { draftFromRecipe } from '@/lib/shareRecipe'
import { useBuilderStore } from '@/store/builderStore'
import { MethodsNeeded } from './MethodsNeeded'

const phaseHex = (kind: string | null) => PHASE_COLORS[kind as PhaseKind]?.hex ?? NEUTRAL_HEX

/**
 * A shared program: its shape — weeks, phases, how many days — and the
 * methods it is built from. It travels as a recipe, never as the sharer's
 * weeks: "Build it for me" opens the program builder with the recipe as its
 * source, where the reader's own level, equipment and schedule make it theirs
 * and the preview shows it before anything is started.
 */
export function SharedProgram({ doc }: { doc: ShareDocument }) {
  const navigate = useNavigate()
  const load = useBuilderStore((s) => s.loadFromRecipe)
  const update = useBuilderStore((s) => s.updateConstraints)
  const p = doc.program!
  const a = doc.availability
  const draft = draftFromRecipe(doc.recipe)
  const total = p.weeks || 1

  const build = () => {
    if (!draft) return
    const { contractOptions, ...state } = draft
    load(state)
    if (contractOptions) update({ contract_options: contractOptions })
    navigate('/program/new')
  }

  return (
    <div className="space-y-5">
      <div className="space-y-3">
        <p className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
          <span className="flex items-center gap-1.5"><CalendarDays className="size-3.5" aria-hidden /> {p.weeks} weeks</span>
          {p.daysPerWeek != null && <span>{p.daysPerWeek} days a week</span>}
          {p.sessionsPerWeek != null && p.sessionsPerWeek !== p.daysPerWeek && <span>{p.sessionsPerWeek} sessions a week</span>}
          {p.tracks.length > 1 && <span className="flex items-center gap-1.5"><Layers className="size-3.5" aria-hidden /> {p.tracks.length} tracks</span>}
        </p>
        {p.tracks.length > 0 && (
          <p className="text-xs text-muted-foreground">
            {p.tracks.map((t) => (t.weight != null ? `${t.name} ${Math.round(t.weight * 100)}%` : t.name)).join(' · ')}
          </p>
        )}
        {p.phases.length > 0 && (
          <div className="space-y-1.5">
            <div className="flex h-2.5 overflow-hidden rounded-full" role="img"
              aria-label={p.phases.map((ph) => `${ph.name ?? ph.kind}, ${ph.weeks} weeks`).join('; ')}>
              {p.phases.map((ph, i) => (
                <span key={i} style={{ width: `${(ph.weeks / total) * 100}%`, backgroundColor: phaseHex(ph.kind) }}
                  className="border-r border-background last:border-r-0" />
              ))}
            </div>
            <ol className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
              {p.phases.map((ph, i) => (
                <li key={i} className="flex items-center gap-1.5">
                  <span className="size-2 rounded-full" style={{ backgroundColor: phaseHex(ph.kind) }} aria-hidden />
                  {ph.name ?? ph.kind} · {ph.weeks} wk
                </li>
              ))}
            </ol>
          </div>
        )}
      </div>

      <div className="space-y-2">
        <h2 className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Methods it needs</h2>
        <MethodsNeeded doc={doc} saveLabel="Save the methods it needs" />
      </div>

      {a?.ready && draft && (
        <div className="space-y-1.5">
          <Button size="sm" onClick={build}><Wand2 className="mr-1.5 size-3.5" /> Build it for me</Button>
          <p className="text-xs text-muted-foreground">
            Opens the program builder with this as its source. Your level, equipment and schedule make it yours, and you
            see it before it starts.
          </p>
        </div>
      )}
      {a && !a.ready && <p className="text-xs text-muted-foreground">Save the methods first; then it can be built for you.</p>}
    </div>
  )
}
