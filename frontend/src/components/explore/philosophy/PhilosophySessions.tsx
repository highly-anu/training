import { useState } from 'react'
import { ChevronDown, ChevronRight, ExternalLink, FlaskConical } from 'lucide-react'
import type { DescribedSession, DescribedSessionGroup, PhilosophyDescription } from '@/api/types'
import { useExploreNavigate } from '@/components/explore/topics'
import { cn } from '@/lib/utils'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'

const EXERCISES_SHOWN = 6

function Session({ session: s }: { session: DescribedSession }) {
  const [open, setOpen] = useState(false)
  const go = useExploreNavigate()
  return (
    <li className="rounded-md border border-border/40 bg-card/40">
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        className="flex w-full items-center gap-2 px-2.5 py-1.5 text-left hover:bg-muted/20">
        {open ? <ChevronDown className="size-3 shrink-0 text-muted-foreground/60" />
          : <ChevronRight className="size-3 shrink-0 text-muted-foreground/60" />}
        {s.test && <FlaskConical className="size-3 shrink-0 text-muted-foreground" aria-label="test" />}
        <span className="flex-1 truncate text-[11px] font-medium">{s.name}</span>
        {s.minutes != null && <span className="font-mono text-[10px] text-muted-foreground">{s.minutes} min</span>}
      </button>
      {open && (
        <div className="space-y-2 border-t border-border/30 px-3 py-2">
          {s.note && <p className="text-[10px] leading-relaxed text-muted-foreground">{s.note}</p>}
          <ul className="space-y-1.5">
            {s.slots.map((slot, i) => (
              <li key={`${slot.role}-${i}`} className={cn('text-[11px]', slot.parent && 'pl-3')}>
                <span className="text-foreground/90">{slot.name}</span>
                {slot.prescription && <span className="font-mono text-[10px] text-muted-foreground"> {slot.prescription}</span>}
                {slot.technique ? (
                  <span className="text-[10px] text-muted-foreground/70"> · technique, no set exercise</span>
                ) : slot.exercises.length === 0 ? (
                  <span className="text-[10px] text-muted-foreground/70"> · nothing in the package fits</span>
                ) : (
                  <div className="mt-0.5 flex flex-wrap gap-1">
                    {slot.exercises.slice(0, EXERCISES_SHOWN).map((e) => (
                      <button key={e.id} type="button" onClick={() => go('exercises', e.id)}
                        className="rounded border border-border/50 px-1.5 py-0.5 text-[10px] text-muted-foreground hover:border-primary/50 hover:text-foreground">
                        {e.name}
                      </button>
                    ))}
                    {slot.exercises.length > EXERCISES_SHOWN && (
                      <span className="px-1 text-[10px] text-muted-foreground/70">
                        +{slot.exercises.length - EXERCISES_SHOWN} {slot.listed ? 'substitutes' : 'more'}
                      </span>
                    )}
                  </div>
                )}
                {slot.note && <p className="text-[10px] text-muted-foreground/80 leading-relaxed">{slot.note}</p>}
              </li>
            ))}
          </ul>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-muted-foreground">
            {s.levels.length > 0 && <span>{s.levels.join(' · ')}</span>}
            {s.equipment.length > 0 && <span>Needs {s.equipment.join(', ').toLowerCase()}</span>}
            <button type="button" onClick={() => go('archetypes', s.id)} className="inline-flex items-center gap-1 hover:text-foreground">
              Open as an archetype <ExternalLink className="size-2.5" />
            </button>
          </div>
        </div>
      )}
    </li>
  )
}

function groupLabel(g: DescribedSessionGroup): string {
  if (g.name) return g.name
  return modalityLabel(g.modality) || 'Other'
}

function Group({ group, sessions, defaultOpen }: {
  group: DescribedSessionGroup; sessions: Record<string, DescribedSession>; defaultOpen: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)
  const hex = modalityHex(group.modality)
  return (
    <div className="rounded-lg border border-border/40 overflow-hidden" style={{ borderLeftColor: group.modality ? hex : undefined, borderLeftWidth: group.modality ? 3 : 1 }}>
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-muted/20">
        {open ? <ChevronDown className="size-3.5 shrink-0 text-muted-foreground/60" />
          : <ChevronRight className="size-3.5 shrink-0 text-muted-foreground/60" />}
        <span className="flex-1 text-xs font-semibold">{groupLabel(group)}</span>
        {group.warmUp && <span className="text-[9px] rounded bg-muted px-1 text-muted-foreground">warm-ups</span>}
        {group.name && group.modality && (
          <span className="text-[10px]" style={{ color: hex }}>{modalityLabel(group.modality)}</span>
        )}
        <span className="font-mono text-[10px] text-muted-foreground">{group.sessions.length}</span>
      </button>
      {open && (
        <div className="space-y-1.5 border-t border-border/30 px-3 py-2">
          {group.advice && <p className="text-[10px] italic text-muted-foreground">{group.advice}</p>}
          <ul className="space-y-1">
            {group.sessions.map((id) => sessions[id] && <Session key={id} session={sessions[id]} />)}
          </ul>
        </div>
      )}
    </div>
  )
}

/**
 * Every session the package writes, grouped as the method groups them: a
 * template's day categories in the source's order, a contract's modules, the
 * rest by modality, tests apart. Each slot lists the exercises the generator
 * can give it (the server applies the selector's rule).
 */
export function PhilosophySessions({ doc }: { doc: PhilosophyDescription }) {
  const total = doc.groups.reduce((n, g) => n + g.sessions.length, 0)
  return (
    <div className="space-y-1.5">
      {doc.groups.map((g) => (
        <Group key={`${g.kind}-${g.id}`} group={g} sessions={doc.sessions} defaultOpen={total <= 8} />
      ))}
    </div>
  )
}
