import { CalendarDays, CalendarRange, Timer } from 'lucide-react'
import type { PhilosophyGlance } from '@/api/types'
import { LevelPips, MixLegend, ModalityGlyph, PhaseBar } from './Glance'
import { ModalityMix } from './ModalityMix'

const range = (r: { min: number; ideal: number } | null) => (!r ? '—' : r.min === r.ideal ? `${r.ideal}` : `${r.min}–${r.ideal}`)

/** A philosophy on Explore's landing, from its glance: the same marks as its
 *  page's header, so cards side by side already compare. `scaleWeeks` is the
 *  longest main track on the landing, which every card's phase bar shares. */
export function PhilosophyCard({ glance: g, scaleWeeks, onSelect }: {
  glance: PhilosophyGlance; scaleWeeks: number; onSelect: () => void
}) {
  const primary = g.tracks.find((t) => t.id === g.primaryTrackId) ?? g.tracks[0]
  return (
    <button type="button" onClick={onSelect}
      className="group flex flex-col items-stretch gap-2.5 rounded-lg border border-border/40 bg-card/50 p-3 text-left transition-all hover:-translate-y-px hover:border-primary/40 hover:shadow-md">
      <div className="flex items-center gap-2">
        <div className="flex shrink-0 gap-0.5">
          {g.bias.slice(0, 3).map((m) => <ModalityGlyph key={m} modality={m} />)}
        </div>
        <p className="min-w-0 flex-1 truncate text-xs font-semibold group-hover:text-primary">{g.name}</p>
      </div>
      <ModalityMix mix={g.mix} legend={false} />
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-muted-foreground">
        <span className="inline-flex items-center gap-1" title="Weeks"><CalendarRange className="size-3" />{range(g.weeks)}</span>
        <span className="inline-flex items-center gap-1" title="Days a week"><CalendarDays className="size-3" />{range(g.daysPerWeek)}</span>
        <span className="inline-flex items-center gap-1" title="Minutes a session"><Timer className="size-3" />{range(g.sessionMinutes)}′</span>
        <LevelPips levels={g.levels} className="ml-auto" />
      </div>
      {primary && (
        <div className="space-y-1">
          <PhaseBar phases={primary.phases} scaleWeeks={scaleWeeks} height="h-1.5" />
          <div className="flex items-center justify-between gap-2 text-[9px] text-muted-foreground/80">
            <span className="truncate">{g.counts.tracks > 1 ? `${g.counts.tracks} tracks` : primary.name}</span>
            <MixLegend mix={g.mix} max={4} />
          </div>
        </div>
      )}
    </button>
  )
}
