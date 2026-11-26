import { useState, type ReactNode } from 'react'
import {
  ChevronDown, Clock, CornerLeftUp, Dumbbell, Flag, Hourglass, type LucideIcon, Pause, Repeat, Route, Sparkles,
  StickyNote, Timer, TrendingUp, Triangle, Zap,
} from 'lucide-react'
import type { BlockMovement, BlockShape, BlockStage, SessionBlock } from '@/api/types'
import { Collapse } from '@/components/motion/Collapse'
import { countColumn, isLoop, STAGE_ORDER, stageRuns } from '@/lib/blocks'
import { cn } from '@/lib/utils'

/**
 * A workout as blocks (src/session_blocks.py): what opens it, what repeats in
 * rounds or every minute, the rests, what closes it. Explore draws an
 * archetype with it and the session panel a program's session, so a round's
 * movements sit inside their round on both. Every word is the server's; this
 * lays it out (docs/frontend-design.md §13.12).
 */

const SHAPE_ICON: Record<BlockShape, LucideIcon> = {
  sets: Dumbbell, rounds: Repeat, for_time: Flag, amrap: Hourglass, emom: Timer, interval: Zap,
  ladder: TrendingUp, pyramid: Triangle, timed: Clock, distance: Route, hold: Pause, practice: Sparkles, note: StickyNote,
}

/** A rep scheme as steps: a ladder climbs, a pyramid comes back down, 21-15-9 falls. */
export function SchemeBars({ scheme, className }: { scheme: number[]; className?: string }) {
  const max = Math.max(...scheme, 1)
  return (
    <span className={cn('inline-flex h-4 items-end gap-px', className)} role="img" aria-label={scheme.join('-')}>
      {scheme.slice(0, 12).map((n, i) => (
        <span key={i} className="w-1 rounded-[1px] bg-current" style={{ height: `${Math.max(15, (n / max) * 100)}%` }} />
      ))}
    </span>
  )
}

function ShapeMark({ block, accent }: { block: SessionBlock; accent?: string }) {
  const scheme = block.repeat?.scheme
  const Icon = SHAPE_ICON[block.shape] ?? Dumbbell
  return (
    <span className="flex size-7 shrink-0 items-center justify-center rounded-md bg-muted/60 text-muted-foreground"
      style={accent && block.stage === 'main' ? { color: accent } : undefined}>
      {scheme && scheme.length > 1 ? <SchemeBars scheme={scheme} /> : <Icon className="size-3.5" aria-hidden />}
    </span>
  )
}

function Chip({ children }: { children: ReactNode }) {
  return <span className="rounded bg-muted/60 px-1.5 py-0.5 text-[10px] text-muted-foreground">{children}</span>
}

/** One movement: its count a round, its name, and — on demand — its note and
 *  what else may fill the slot. */
function MovementRow({ movement: m, countWidth, onExercise, renderNote }: {
  movement: BlockMovement
  /** The block's count column: as wide as its longest count ("10-15-20-15-10"), so none wraps. */
  countWidth: string
  onExercise?: (id: string) => void; renderNote?: NoteRenderer
}) {
  const [open, setOpen] = useState(false)
  const others = m.listed ? m.exercises.slice(1) : m.exercises
  const hasMore = Boolean(m.note) || others.length > 0
  const first = m.listed ? m.exercises[0] : undefined
  const line = (
    <>
      <span className="shrink-0 whitespace-nowrap text-right font-mono text-[11px] text-primary tabular-nums"
        style={{ width: countWidth }}>{m.count ?? ''}</span>
      <span className="min-w-0 flex-1 truncate text-xs">
        {m.name}
        {m.eachSide && <span className="text-muted-foreground"> · each side</span>}
      </span>
      {hasMore && <ChevronDown className={cn('size-3 shrink-0 text-muted-foreground/60', open && 'rotate-180')} aria-hidden />}
    </>
  )
  return (
    <li>
      {hasMore ? (
        <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
          className="flex w-full items-center gap-2 rounded px-1 py-1 text-left hover:bg-muted/30">
          {line}
        </button>
      ) : (
        <div className="flex items-center gap-2 px-1 py-1">{line}</div>
      )}
      <Collapse open={open}>
        <div className="space-y-1.5 pb-1.5 pr-1" style={{ paddingLeft: `calc(${countWidth} + 0.75rem)` }}>
          {m.note && <p className="text-[11px] leading-relaxed text-muted-foreground">{renderNote ? renderNote(m.role, m.note) : m.note}</p>}
          {(first || others.length > 0) && (
            <div className="flex flex-wrap items-center gap-1">
              {!m.listed && <span className="text-[10px] text-muted-foreground/70">Any of</span>}
              {m.listed && others.length > 0 && first && (
                <ExerciseChip id={first.id} name={first.name} onExercise={onExercise} />
              )}
              {m.listed && others.length > 0 && <span className="text-[10px] text-muted-foreground/70">or</span>}
              {others.map((e) => <ExerciseChip key={e.id} id={e.id} name={e.name} onExercise={onExercise} />)}
              {m.more > 0 && <span className="text-[10px] text-muted-foreground/70">+{m.more} more</span>}
            </div>
          )}
        </div>
      </Collapse>
    </li>
  )
}

function ExerciseChip({ id, name, onExercise }: { id: string; name: string; onExercise?: (id: string) => void }) {
  const cls = 'rounded border border-border/50 px-1.5 py-0.5 text-[10px] text-muted-foreground'
  return onExercise
    ? <button type="button" onClick={() => onExercise(id)} className={cn(cls, 'hover:border-primary/50 hover:text-foreground')}>{name}</button>
    : <span className={cls}>{name}</span>
}

/** The rail a round runs down, and the way back to its top. */
function Loop({ block, accent, children }: { block: SessionBlock; accent?: string; children: ReactNode }) {
  const foot = [block.rest?.between === 'rounds' ? block.rest.text : null, block.again].filter(Boolean).join(' · ')
  return (
    <div className="ml-3.5 border-l-2 border-border pl-2" style={accent ? { borderLeftColor: accent } : undefined}>
      {children}
      {foot && (
        <p className="flex items-center gap-1.5 px-1 pt-1 text-[10px] text-muted-foreground">
          <CornerLeftUp className="size-3 shrink-0" aria-hidden />
          {foot}
        </p>
      )}
    </div>
  )
}

/** Draws a slot's note in the caller's own way (an editable one, on the athlete's own method). */
type NoteRenderer = (role: string, note: string) => ReactNode

interface BlockProps {
  block: SessionBlock
  renderNote?: NoteRenderer
  /** The session's modality colour: the rail and the main work's mark. */
  accent?: string
  onExercise?: (id: string) => void
  /** Draws a movement's row itself (the session panel's exercise row, with its logger). */
  renderMovement?: (movement: BlockMovement, block: SessionBlock) => ReactNode
}

/** One block: its mark and headline, the movements, the rest; notes on demand. */
export function BlockCard({ block: b, accent, onExercise, renderMovement, renderNote }: BlockProps) {
  const [open, setOpen] = useState(false)
  const loop = isLoop(b)
  const single = b.movements.length === 1 ? b.movements[0] : null
  const restChip = b.rest && !(loop && b.rest.between === 'rounds') ? b.rest.text : null
  // A caller's rows carry their own notes and load; the header keeps to the round.
  const details = renderMovement ? [] : [b.note, b.load && b.load.length > 60 ? b.load : null].filter(Boolean) as string[]
  const shortLoad = !renderMovement && b.load && b.load.length <= 60 ? b.load : null
  // A block of one movement is named by it; a piece keeps its own title.
  const name = single && !loop ? single.name : b.title
  const rows = renderMovement
    ? b.movements.map((m) => <li key={m.role}>{renderMovement(m, b)}</li>)
    : b.movements.map((m) => (
      <MovementRow key={m.role} movement={m} countWidth={countColumn(b.movements)} onExercise={onExercise} renderNote={renderNote} />
    ))

  // A caller's own rows say a lone movement's numbers themselves: no header
  // over one row, only over a round.
  if (renderMovement && !loop) return <ul className="space-y-2" data-block={b.id} data-shape={b.shape}>{rows}</ul>

  return (
    <div className="rounded-lg border border-border/60 bg-card/60 p-2.5" data-block={b.id} data-shape={b.shape}>
      <div className="flex items-start gap-2.5">
        <ShapeMark block={b} accent={accent} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-baseline gap-x-2">
            {b.headline && <span className="font-mono text-xs font-semibold text-foreground">{b.headline}</span>}
            <span className="min-w-0 truncate text-xs text-foreground/80">
              {name}
              {single && !loop && single.eachSide && !b.headline.includes('each side') && (
                <span className="text-muted-foreground"> · each side</span>
              )}
            </span>
          </div>
          {(shortLoad || b.intensity || b.rpe || b.cap || restChip) && (
            <div className="mt-1 flex flex-wrap gap-1">
              {shortLoad && <Chip>{shortLoad}</Chip>}
              {b.intensity && <Chip>{b.intensity}</Chip>}
              {b.rpe != null && <Chip>RPE {b.rpe}</Chip>}
              {b.cap && <Chip>{b.cap}</Chip>}
              {restChip && <Chip>{restChip}</Chip>}
            </div>
          )}
        </div>
        {details.length > 0 && (
          <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
            aria-label={`${open ? 'Hide' : 'Show'} notes for ${name || b.headline}`}
            className="flex size-6 shrink-0 items-center justify-center rounded text-muted-foreground hover:bg-muted/40 hover:text-foreground">
            <ChevronDown className={cn('size-3.5', open && 'rotate-180')} aria-hidden />
          </button>
        )}
      </div>
      <Collapse open={open}>
        <div className="space-y-1 pl-[2.375rem] pt-1.5">
          {details.map((d, i) => (
            <p key={i} className="text-[11px] leading-relaxed text-muted-foreground">
              {renderNote && d === b.note ? renderNote(b.id, d) : d}
            </p>
          ))}
        </div>
      </Collapse>
      {loop ? (
        <div className="mt-2">
          <Loop block={b} accent={accent}><ul className={renderMovement ? 'space-y-2' : undefined}>{rows}</ul></Loop>
        </div>
      ) : single && (single.note || single.exercises.length > (single.listed ? 1 : 0)) ? (
        <SingleExtras movement={single} onExercise={onExercise} />
      ) : null}
    </div>
  )
}

/** What a lone movement may be swapped for, or which exercises a filter takes. */
function SingleExtras({ movement: m, onExercise }: { movement: BlockMovement; onExercise?: (id: string) => void }) {
  const shown = m.listed ? m.exercises.slice(0, 1) : m.exercises
  const others = m.listed ? m.exercises.slice(1) : []
  const [open, setOpen] = useState(false)
  return (
    <div className="mt-1.5 pl-[2.375rem]">
      <div className="flex flex-wrap items-center gap-1">
        {!m.listed && shown.length > 0 && <span className="text-[10px] text-muted-foreground/70">Any of</span>}
        {shown.map((e) => <ExerciseChip key={e.id} id={e.id} name={e.name} onExercise={onExercise} />)}
        {m.more > 0 && <span className="text-[10px] text-muted-foreground/70">+{m.more} more</span>}
        {(others.length > 0 || m.note) && (
          <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
            className="rounded px-1 text-[10px] text-muted-foreground hover:text-foreground">
            {others.length > 0 ? `${others.length} substitute${others.length === 1 ? '' : 's'}` : 'Notes'}
          </button>
        )}
      </div>
      <Collapse open={open}>
        <div className="space-y-1 pt-1">
          {m.note && <p className="text-[11px] leading-relaxed text-muted-foreground">{m.note}</p>}
          {others.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {others.map((e) => <ExerciseChip key={e.id} id={e.id} name={e.name} onExercise={onExercise} />)}
            </div>
          )}
        </div>
      </Collapse>
    </div>
  )
}

/** Blocks tied by `group` (a superset, alternating sets) under one bracket. */
function grouped(blocks: SessionBlock[]): SessionBlock[][] {
  const out: SessionBlock[][] = []
  for (const b of blocks) {
    const last = out[out.length - 1]
    if (b.group && last && last[0].group?.id === b.group.id) last.push(b)
    else out.push([b])
  }
  return out
}

const GROUP_LABEL = { superset: 'Superset', alternate: 'Alternate sets' } as const

/** A session's blocks, in stages: the start, the main work, a finisher, the
 *  cool-down. A stage is labelled only when the session has more than one. */
export function WorkoutBlocks({ blocks, accent, onExercise, renderMovement, renderNote, className }: {
  blocks: SessionBlock[]
  accent?: string
  onExercise?: (id: string) => void
  renderMovement?: BlockProps['renderMovement']
  renderNote?: NoteRenderer
  className?: string
}) {
  const runs = stageRuns(blocks)
  const labelled = runs.length > 1
  return (
    <div className={cn('space-y-3', className)}>
      {runs.map((run, i) => (
        <section key={`${run.stage}-${i}`} aria-label={run.label} className="space-y-1.5">
          {labelled && (
            <h4 className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">{run.label}</h4>
          )}
          {grouped(run.blocks).map((set) => set.length === 1 ? (
            <BlockCard key={set[0].id} block={set[0]} accent={accent} onExercise={onExercise} renderMovement={renderMovement} renderNote={renderNote} />
          ) : (
            <div key={set[0].id} className="space-y-1.5 rounded-lg border-l-2 border-border pl-2"
              style={accent ? { borderLeftColor: accent } : undefined}>
              <p className="text-[10px] text-muted-foreground">{GROUP_LABEL[set[0].group!.kind]}</p>
              {set.map((b) => (
                <BlockCard key={b.id} block={b} accent={accent} onExercise={onExercise} renderMovement={renderMovement} renderNote={renderNote} />
              ))}
            </div>
          ))}
        </section>
      ))}
    </div>
  )
}

/** The session's shape in one line: a segment a block, the main work in the
 *  session's colour, the start and the cool-down quiet. */
export function BlockStrip({ blocks, accent, className }: { blocks: SessionBlock[]; accent?: string; className?: string }) {
  if (blocks.length === 0) return null
  const count = (s: BlockStage) => blocks.filter((b) => b.stage === s).length
  const label = STAGE_ORDER.filter((s) => count(s) > 0)
    .map((s) => `${blocks.find((b) => b.stage === s)!.stageLabel} ${count(s)}`).join(', ')
  return (
    <span className={cn('flex h-1.5 gap-0.5', className)} role="img" aria-label={`Blocks: ${label}`}>
      {blocks.map((b) => (
        <span key={b.id}
          className={cn('min-w-1 rounded-full', b.stage === 'main' ? 'bg-foreground/60' : 'bg-muted-foreground/30',
            b.stage === 'finisher' && 'bg-foreground/35')}
          style={{ flexGrow: Math.max(1, b.movements.length), ...(accent && b.stage === 'main' ? { backgroundColor: accent } : {}) }} />
      ))}
    </span>
  )
}
