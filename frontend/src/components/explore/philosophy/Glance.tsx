import { createElement, useEffect, useRef } from 'react'
import { X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { DescribedMix, GlancePhase, TrainingLevel } from '@/api/types'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { modalityIcon } from '@/lib/modalityIcons'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { cn } from '@/lib/utils'
import { TRAINING_LEVELS } from '@/lib/gen/clientVocab'

/**
 * The glance vocabulary: the same few marks for every philosophy, so a header,
 * a landing card and (later) a side-by-side comparison read alike. Numbers and
 * symbols; words are on demand. Colour stays on its axis — modality (§8.1),
 * phase kind (§8.2), heart-rate zone (§8.7); levels have none (§8.1).
 */

const LEVELS: readonly TrainingLevel[] = TRAINING_LEVELS
const LEVEL_LETTER: Record<TrainingLevel, string> = { novice: 'N', intermediate: 'I', advanced: 'A', elite: 'E' }

/** Four pips, novice → elite, filled where the method is written for it. */
export function LevelPips({ levels, className }: { levels: TrainingLevel[]; className?: string }) {
  return (
    <span className={cn('inline-flex gap-0.5', className)} role="img"
      aria-label={`Levels: ${levels.join(', ') || 'none'}`} title={levels.join(' · ')}>
      {LEVELS.map((l) => (
        <span key={l} className={cn('flex size-3.5 items-center justify-center rounded-sm text-[8px] font-semibold',
          levels.includes(l) ? 'bg-foreground/80 text-background' : 'border border-border text-muted-foreground/40')}>
          {LEVEL_LETTER[l]}
        </span>
      ))}
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
    ? <button type="button" onClick={onClick} title={title} aria-expanded={active}
        className={cn(cls, 'hover:border-primary/40 hover:bg-muted/30 transition-colors',
          active && 'border-primary/50 bg-primary/10')}>{body}</button>
    : <div title={title} className={cls}>{body}</div>
}

/** A modality's icon in its colour. */
export function ModalityGlyph({ modality, className }: { modality: string | null | undefined; className?: string }) {
  return createElement(modalityIcon(modality), {
    className: cn('size-3.5 shrink-0', className), style: { color: modalityHex(modality) },
    'aria-label': modalityLabel(modality),
  })
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

/** A week at a glance: seven cells for the source's own days, each split by
 *  the modalities it holds, rest days empty; without days (a contract, a
 *  framework), one dot per session a week in its modality's colour. */
export function WeekGlyph({ phase, size = 'md' }: { phase: Pick<GlancePhase, 'days' | 'mix'>; size?: 'sm' | 'md' }) {
  const cell = size === 'sm' ? 'h-2.5 w-2' : 'h-4 w-3'
  if (phase.days) {
    return (
      <div className="flex gap-0.5" role="img" aria-label="The week, day by day">
        {phase.days.map((d, i) => (
          <div key={i} className={cn(cell, 'flex flex-col overflow-hidden rounded-[2px]', d ? '' : 'border border-dashed border-border/70')}
            title={d ? d.map(modalityLabel).join(' + ') : 'Rest'}>
            {d?.map((m, j) => <div key={j} className="flex-1" style={{ backgroundColor: modalityHex(m) }} />)}
          </div>
        ))}
      </div>
    )
  }
  const dots = phase.mix.flatMap((m) => Array.from({ length: Math.round(m.perWeek) }, () => m.modality))
  return (
    <div className="flex flex-wrap gap-0.5" role="img" aria-label="Sessions a week">
      {dots.map((m, i) => (
        <div key={i} className={cn(size === 'sm' ? 'size-2' : 'size-3', 'rounded-full')}
          style={{ backgroundColor: modalityHex(m) }} title={modalityLabel(m)} />
      ))}
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
        const style = { width: `${(p.weeks / (scaleWeeks || 1)) * 100}%`, backgroundColor: PHASE_COLORS[p.kind]?.hex ?? '#94a3b8' }
        const cls = cn(height, 'rounded-[2px] transition-opacity', selected && selected !== p.id && 'opacity-35')
        return onSelect
          ? <button key={p.id} type="button" onClick={() => onSelect(p.id)} className={cls} style={style}
              title={`${p.name} · ${p.weeks} wk`} aria-label={`${p.name}, ${p.weeks} weeks`} />
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
      className="overflow-hidden rounded-lg border border-border/60 bg-card/70 animate-in fade-in-0 slide-in-from-top-1 duration-200">
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
