import { NEUTRAL_HEX } from '@/lib/dataColors'
import { Tip } from '@/components/shared/Tip'
import { useEffect, useRef } from 'react'
import { Check, Minus, X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { DescribedMix, GlancePhase, TrainingLevel } from '@/api/types'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { modalityLabel } from '@/lib/modalityColors'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { cn } from '@/lib/utils'
import { TRAINING_LEVELS, TRAINING_LEVEL_LABELS } from '@/lib/gen/clientVocab'

/**
 * The glance vocabulary: the same few marks for every philosophy, so a header,
 * a landing card and (later) a side-by-side comparison read alike. Numbers and
 * symbols; words are on demand. A modality is said by its icon in its colour
 * (ModalityMark, §8.1) and by nothing else — no fill, stripe or border; phase
 * kind (§8.2) and heart-rate zone (§8.7) keep their bars; levels have no
 * colour (§8.1).
 */

const LEVELS: readonly TrainingLevel[] = TRAINING_LEVELS
const levelLabel = (l: TrainingLevel) => TRAINING_LEVEL_LABELS[l] ?? l
/** The compact scale's steps, novice → elite. */
const STEP_HEIGHT = ['h-1.5', 'h-2.5', 'h-3.5', 'h-[1.125rem]']

/** Who a method or a track is written for: every level, always, in the same
 *  place and at the same size — the ones it serves marked, the others left
 *  quiet. `full` names each level (a tick or a dash beside it, so it is never
 *  said by shade alone); `compact`, for a card or a table cell, is four rising
 *  steps, filled where it serves. */
export function LevelScale({ levels, size = 'full', className }: {
  levels: TrainingLevel[]; size?: 'full' | 'compact'; className?: string
}) {
  const on = LEVELS.filter((l) => levels.includes(l))
  const off = LEVELS.filter((l) => !levels.includes(l))
  const label = `Written for ${on.map(levelLabel).join(', ') || 'no level'}`
    + (on.length && off.length ? `; not for ${off.map(levelLabel).join(', ')}` : '')
  if (size === 'compact') {
    return (
      <span className={cn('inline-flex h-[1.125rem] shrink-0 items-end gap-0.5', className)} role="img"
        aria-label={label} title={label}>
        {LEVELS.map((l, i) => (
          <span key={l} className={cn('w-1.5 rounded-[1px]', STEP_HEIGHT[i],
            levels.includes(l) ? 'bg-foreground/80' : 'border border-border')} />
        ))}
      </span>
    )
  }
  return (
    <span className={cn('inline-flex shrink-0 divide-x divide-border/60 overflow-hidden rounded-md border border-border/60 text-[10px] leading-none', className)}
      role="img" aria-label={label}>
      {LEVELS.map((l) => {
        const serves = levels.includes(l)
        const Mark = serves ? Check : Minus
        return (
          <span key={l} className={cn('inline-flex items-center gap-1 px-1.5 py-1',
            serves ? 'bg-foreground/10 font-medium text-foreground' : 'text-muted-foreground/50')}>
            <Mark className="size-2.5" aria-hidden />{levelLabel(l)}
          </span>
        )
      })}
    </span>
  )
}

/** An icon, a number, a small label. */
export function StatTile({ icon: Icon, value, label, title, children, onClick, active = false }: {
  icon: LucideIcon; value?: React.ReactNode; label: string; title?: string; children?: React.ReactNode
  onClick?: () => void; active?: boolean
}) {
  const body = (
    <>
      <Icon className="size-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <div className="text-sm font-semibold leading-tight tabular-nums">{value ?? children}</div>
        <div className="text-[10px] text-muted-foreground leading-tight">{label}</div>
      </div>
    </>
  )
  const cls = 'flex items-center gap-2 rounded-md border border-border/50 bg-card/60 px-2.5 py-2 text-left'
  return onClick
    ? <Tip label={title}><button type="button" onClick={onClick} aria-expanded={active}
        className={cn(cls, 'hover:border-primary/40 hover:bg-muted/30 transition-colors',
          active && 'border-primary/50 bg-primary/10')}>{body}</button></Tip>
    : <div title={title} className={cls}>{body}</div>
}

/** A modality's icon in its colour: the shared mark, at a glance's size. */
export function ModalityGlyph({ modality, className }: { modality: string | null | undefined; className?: string }) {
  return <ModalityMark modality={modality} className={className} />
}

/** The modality mix as icons with ×/wk — the fingerprint's legend. */
export function MixLegend({ mix, max = 6 }: { mix: DescribedMix[]; max?: number }) {
  return (
    <div className="flex flex-wrap gap-x-2.5 gap-y-1">
      {mix.slice(0, max).map((m) => (
        <span key={m.modality} className="inline-flex items-center gap-1" title={`${modalityLabel(m.modality)}: ${m.perWeek}×/wk`}>
          <ModalityGlyph modality={m.modality} />
          <span className="font-mono text-[10px] text-muted-foreground">
            {Number.isInteger(m.perWeek) ? m.perWeek : m.perWeek.toFixed(1)}
          </span>
        </span>
      ))}
    </div>
  )
}

const DAY_LETTERS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']
const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

/** A week as its seven days, training against rest, with the count in words
 *  under it. Where the source writes the week day by day each cell is its
 *  weekday — lettered, filled for training, dashed for rest. Where the days
 *  are the athlete's to place (a contract, a framework) the cells carry no
 *  letter: so many of the seven, never which. */
export function WeekDays({ phase }: { phase: Pick<GlancePhase, 'days' | 'daysPerWeek' | 'sessionsPerWeek'> }) {
  const placed = phase.days?.length === 7 ? phase.days : null
  const training = placed
    ? placed.filter(Boolean).length
    : Math.max(0, Math.min(7, Math.round(phase.daysPerWeek ?? phase.sessionsPerWeek)))
  const rest = 7 - training
  const words = `${training} training day${training === 1 ? '' : 's'}, ${rest} rest`
  return (
    <div className="space-y-1" role="img"
      aria-label={placed
        ? `${words}: trains ${DAY_NAMES.filter((_, i) => placed[i]).join(', ') || 'no day'}`
        : `${words}, on the days you choose`}>
      <div className="grid grid-cols-7 gap-0.5">
        {DAY_LETTERS.map((letter, i) => {
          const on = placed ? Boolean(placed[i]) : i < training
          return (
            <span key={i} aria-hidden
              title={placed ? `${DAY_NAMES[i]}: ${placed[i]?.map(modalityLabel).join(' + ') ?? 'rest'}` : undefined}
              className={cn('flex h-5 items-center justify-center rounded-[3px] text-[9px] font-semibold leading-none',
                on ? 'bg-foreground/75 text-background' : 'border border-dashed border-border text-muted-foreground/50')}>
              {placed ? letter : ''}
            </span>
          )
        })}
      </div>
      <p className="text-[10px] leading-tight text-muted-foreground" aria-hidden>
        <span className="font-medium text-foreground/90">{training}</span> training · {rest} rest
        {!placed && <span className="text-muted-foreground/70"> · your days</span>}
      </p>
    </div>
  )
}

/** A track from its first week to its last: a block a phase, as wide as its
 *  share of the weeks, in its kind's colour, with its name on it and its weeks
 *  under it. A block opens its phase. */
export function PhaseTimeline({ phases, repeats = false, selected, onSelect }: {
  phases: Pick<GlancePhase, 'id' | 'name' | 'kind' | 'weeks'>[]
  repeats?: boolean; selected?: string | null; onSelect: (id: string) => void
}) {
  const rows = phases.map((p, i) => {
    const from = phases.slice(0, i).reduce((n, q) => n + q.weeks, 0) + 1
    return { ...p, from, to: from + p.weeks - 1 }
  })
  const total = phases.reduce((n, p) => n + p.weeks, 0)
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">Timeline</p>
        <p className="font-mono text-[10px] text-muted-foreground">
          {total} week{total === 1 ? '' : 's'}{repeats ? ', then again' : ''}
        </p>
      </div>
      <div className="flex w-full gap-0.5">
        {rows.map((p) => {
          const c = PHASE_COLORS[p.kind]
          const hex = c?.hex ?? NEUTRAL_HEX
          const weeks = p.from === p.to ? `Week ${p.from}` : `Weeks ${p.from}–${p.to}`
          return (
            <Tip key={p.id} label={`${p.name} · ${weeks.toLowerCase()}`}>
              <button type="button" onClick={() => onSelect(p.id)} aria-pressed={selected === p.id}
                aria-label={`${p.name}, ${weeks.toLowerCase()}`}
                className="group min-w-7 basis-0 text-left" style={{ flexGrow: p.weeks }}>
                <span className={cn('block h-6 truncate rounded-[3px] px-1.5 text-[11px] font-medium leading-6 transition-shadow',
                  c?.text, selected === p.id ? 'ring-1 ring-primary/60' : 'group-hover:ring-1 group-hover:ring-border')}
                  style={{ backgroundColor: `color-mix(in srgb, ${hex} 20%, transparent)`, borderBottom: `2px solid ${hex}` }}>
                  {p.name}
                </span>
                <span className="mt-1 block truncate font-mono text-[10px] text-muted-foreground">
                  {p.from === p.to ? `wk ${p.from}` : `wk ${p.from}–${p.to}`}
                </span>
              </button>
            </Tip>
          )
        })}
      </div>
    </div>
  )
}

/** A track's phases as one bar in their kinds' colours, as long as the track
 *  on a shared scale (`scaleWeeks`), so tracks compare by length too. */
export function PhaseBar({ phases, scaleWeeks, selected, onSelect, height = 'h-2.5' }: {
  phases: Pick<GlancePhase, 'id' | 'name' | 'kind' | 'weeks'>[]
  scaleWeeks: number; selected?: string; onSelect?: (id: string) => void; height?: string
}) {
  return (
    <div className="flex w-full gap-px">
      {phases.map((p) => {
        const style = { width: `${(p.weeks / (scaleWeeks || 1)) * 100}%`, backgroundColor: PHASE_COLORS[p.kind]?.hex ?? NEUTRAL_HEX }
        const cls = cn(height, 'rounded-[2px] transition-opacity', selected && selected !== p.id && 'opacity-35')
        return onSelect
          ? <Tip key={p.id} label={`${p.name} · ${p.weeks} wk`}><button type="button" onClick={() => onSelect(p.id)} className={cls} style={style} aria-label={`${p.name}, ${p.weeks} weeks`} /></Tip>
          : <div key={p.id} className={cls} style={style} title={`${p.name} · ${p.weeks} wk`} />
      })}
    </div>
  )
}

/** Easy to hard as one thin bar in the heart-rate zone colours. */
export function IntensityBar({ split, className }: { split: Record<string, number>; className?: string }) {
  const rows = INTENSITY_BUCKETS.map((b) => ({ ...b, pct: split[b.key] ?? 0 })).filter((b) => b.pct > 0)
  if (!rows.length) return <div className={cn('h-1 rounded-full bg-muted', className)} title="No intensity split declared" />
  return (
    <div className={cn('flex h-1 overflow-hidden rounded-full gap-px', className)} role="img"
      aria-label={rows.map((b) => `${b.label} ${Math.round(b.pct * 100)}%`).join(', ')}>
      {rows.map((b) => <div key={b.key} style={{ width: `${b.pct * 100}%`, backgroundColor: b.color }}
        title={`${b.label} ${Math.round(b.pct * 100)}%`} />)}
    </div>
  )
}

/** The split in words: a dot a zone, its share. */
export function IntensityLegend({ split }: { split: Record<string, number> }) {
  const rows = INTENSITY_BUCKETS.map((b) => ({ ...b, pct: split[b.key] ?? 0 })).filter((b) => b.pct > 0)
  return (
    <div className="flex flex-wrap gap-x-3">
      {rows.map((b) => (
        <span key={b.key} className="flex items-center gap-1 text-[10px] text-muted-foreground">
          <span className="size-1.5 rounded-full" style={{ backgroundColor: b.color }} />
          {b.label} {Math.round(b.pct * 100)}%
        </span>
      ))}
    </div>
  )
}

/** Detail opened in place, right under what was clicked — never a drawer at
 *  the edge of the screen, so the eye stays where it was. `accent` is the
 *  axis colour of what opened it (a phase kind, a modality); the panel scrolls
 *  itself into view only as far as it must. */
export function InlinePanel({ title, subtitle, accent, onClose, children }: {
  title: React.ReactNode; subtitle?: React.ReactNode; accent?: string; onClose: () => void; children: React.ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    ref.current?.scrollIntoView?.({ block: 'nearest', behavior: 'smooth' })
  }, [])
  return (
    <div ref={ref} role="region" aria-label={typeof title === 'string' ? title : undefined}
      className="overflow-hidden rounded-lg border border-border/60 bg-card/70 animate-in fade-in-0 slide-in-from-top-1 duration-(--motion-base)">
      {accent && <div className="h-0.5" style={{ backgroundColor: accent }} />}
      <div className="flex items-start justify-between gap-3 px-4 pt-3">
        <div className="min-w-0">
          <div className="text-sm font-semibold">{title}</div>
          {subtitle && <div className="text-[11px] text-muted-foreground">{subtitle}</div>}
        </div>
        <button type="button" onClick={onClose} aria-label="Close"
          className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground">
          <X className="size-3.5" />
        </button>
      </div>
      <div className="px-4 pb-4 pt-3">{children}</div>
    </div>
  )
}
