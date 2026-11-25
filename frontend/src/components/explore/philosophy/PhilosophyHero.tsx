import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import {
  CalendarDays, CalendarRange, ChevronLeft, Columns3, Ellipsis, GitBranch, Pencil, Sparkles,
  TextCursorInput, Timer, Wand2,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { PhilosophyDescription } from '@/api/types'
import { EditableText } from '@/components/methods/MethodEdit'
import { Collapse } from '@/components/motion/Collapse'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { MoreToggle } from '@/components/shared/MoreToggle'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { cn } from '@/lib/utils'
import { LevelScale } from './Glance'

const range = (r: { min: number; ideal: number } | null) =>
  !r ? null : r.min === r.ideal ? `${r.ideal}` : `${r.min}–${r.ideal}`

function Fact({ icon: Icon, value, unit }: { icon: LucideIcon; value: string | number | null; unit: string }) {
  if (value == null) return null
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap">
      <Icon className="size-3.5 text-muted-foreground" aria-hidden />
      <span className="font-mono tabular-nums text-foreground">{value}</span>
      <span className="text-muted-foreground">{unit}</span>
    </span>
  )
}

/** The way back to the list. */
export function BackToPhilosophies({ onBack }: { onBack: () => void }) {
  return (
    <button type="button" onClick={onBack}
      className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
      <ChevronLeft className="size-3.5" /> All philosophies
    </button>
  )
}

/**
 * What a philosophy is, before any of its detail: its mark, its name, two
 * lines of what it is for, and the numbers a reader decides by — weeks, days,
 * minutes, levels — on one line. Two actions show (build, compare); an own
 * method's editing sits behind one menu.
 */
export function PhilosophyHero({ doc, editing, canEdit, onEditing, onRename, compareWith, onCompare, onBuild, share }: {
  doc: PhilosophyDescription
  editing: boolean; canEdit: boolean; onEditing: (on: boolean) => void; onRename: () => void
  /** The philosophies to offer for a comparison, most alike first. */
  compareWith: Array<{ id: string; name: string }>
  onCompare?: (id: string) => void
  onBuild?: () => void
  /** The share action, where the page offers one. */
  share?: ReactNode
}) {
  const [more, setMore] = useState(false)
  const g = doc.glance
  const phases = g.tracks.reduce((n, t) => n + t.phases.length, 0)
  const models = [
    doc.models.intensity && `Intensity: ${doc.models.intensity.toLowerCase()}.`,
    doc.models.progression && `Progression: ${doc.models.progression.toLowerCase()}.`,
  ].filter(Boolean).join(' ')
  const hasMore = Boolean(models) || doc.borrows.length > 0 || (doc.summary?.length ?? 0) > 180
  const open = more || editing

  return (
    <header className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
        <div className="flex min-w-0 items-center gap-3">
          <ModalityMark modality={doc.accent ?? g.bias[0]} size="lg" tile />
          <h2 className="min-w-0 text-2xl font-bold leading-tight tracking-tight">{doc.name}</h2>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {canEdit && (editing
            ? (
              <Button size="sm" variant="secondary" onClick={() => onEditing(false)}>
                <Pencil className="mr-1.5 size-3.5" /> Done editing
              </Button>
            )
            : (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button size="icon" variant="outline" className="size-8" aria-label="Change this method">
                    <Ellipsis className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onSelect={() => onEditing(true)}>
                    <Pencil className="mr-2 size-3.5" /> Edit description
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={onRename}>
                    <TextCursorInput className="mr-2 size-3.5" /> Rename
                  </DropdownMenuItem>
                  <DropdownMenuItem asChild>
                    <Link to={`/program/new/method?revise=${encodeURIComponent(doc.id)}`}>
                      <Sparkles className="mr-2 size-3.5" /> Revise
                    </Link>
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            ))}
          {share}
          {onCompare && (
            <Popover>
              <PopoverTrigger asChild>
                <Button size="sm" variant="outline"><Columns3 className="mr-1.5 size-3.5" /> Compare with…</Button>
              </PopoverTrigger>
              <PopoverContent align="end" className="w-64 p-1">
                <p className="px-2 py-1 text-[10px] text-muted-foreground">Most alike first</p>
                {compareWith.map((p) => (
                  <button key={p.id} type="button" onClick={() => onCompare(p.id)}
                    className="block w-full truncate rounded px-2 py-1 text-left text-xs hover:bg-muted">
                    {p.name}
                  </button>
                ))}
              </PopoverContent>
            </Popover>
          )}
          {onBuild && (
            <Button size="sm" onClick={onBuild}>
              <Wand2 className="mr-1.5 size-3.5" /> Build a program
            </Button>
          )}
        </div>
      </div>

      {editing && (
        <p className="text-xs text-muted-foreground">
          Names and notes save as you change them, with no build. Rounds, reps, rests and sessions change with Revise.
        </p>
      )}

      {(doc.summary || editing || hasMore) && (
        <div className="max-w-3xl space-y-1.5">
          {(doc.summary || editing) && (
            <p className={cn('text-sm leading-relaxed text-muted-foreground', !open && 'line-clamp-2')}>
              <EditableText value={doc.summary} label="Summary" multiline placeholder="Say what this method is for"
                edits={(summary) => ({ summary })} />
            </p>
          )}
          <Collapse open={open && (Boolean(models) || doc.borrows.length > 0)}>
            <div className="space-y-1 text-xs text-muted-foreground">
              {models && <p>{models}</p>}
              {doc.borrows.map((b) => (
                <p key={b.package}><span className="text-foreground/90">Borrows from {b.label}.</span> {b.reason}</p>
              ))}
            </div>
          </Collapse>
          {hasMore && !editing && (
            <MoreToggle open={more} onToggle={() => setMore((m) => !m)} />
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 text-xs">
        <Fact icon={CalendarRange} value={range(g.weeks)} unit="weeks" />
        <Fact icon={CalendarDays} value={range(g.daysPerWeek)} unit="days a week" />
        <Fact icon={Timer} value={range(g.sessionMinutes)}
          unit={g.longSessionMinutes ? `min · long ${g.longSessionMinutes}` : 'min a session'} />
        <Fact icon={GitBranch} value={g.counts.tracks}
          unit={`track${g.counts.tracks === 1 ? '' : 's'} · ${phases} phase${phases === 1 ? '' : 's'}`} />
        <LevelScale levels={g.levels} />
      </div>
    </header>
  )
}
