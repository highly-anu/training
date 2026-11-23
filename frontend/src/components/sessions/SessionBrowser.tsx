import { useDeferredValue, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import type { DescribedSession, DescribedSessionGroup, TrainingLevel } from '@/api/types'
import { Advice } from '@/components/shared/Advice'
import { BlockStrip, WorkoutBlocks } from '@/components/blocks/WorkoutBlocks'
import { EmptyState } from '@/components/shared/EmptyState'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { SearchField } from '@/components/shared/SearchField'
import { Tip } from '@/components/shared/Tip'
import { Badge } from '@/components/ui/badge'
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet'
import { TRAINING_LEVELS } from '@/lib/gen/clientVocab'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { browse, groupOf, levelChoices, neighbour, type BrowsedGroup } from '@/lib/sessionBrowser'
import { useMediaQuery } from '@/lib/useMediaQuery'
import { cn } from '@/lib/utils'

/** Where a caller puts its own fields in place of a session's words (a method being edited). */
export interface SessionEditing {
  name?: (session: DescribedSession) => ReactNode
  note?: (session: DescribedSession) => ReactNode
  slotNote?: (session: DescribedSession, role: string, note: string | null) => ReactNode
}

interface SessionBrowserProps {
  /** The sessions' groups, in the order to list them. */
  groups: DescribedSessionGroup[]
  sessions: Record<string, DescribedSession>
  /** The session shown; null shows the first of the list beside it (and, on a narrow screen, the list alone). */
  selectedId: string | null
  onSelect: (id: string | null) => void
  onExercise?: (id: string) => void
  /** Under a session's blocks: where else it leads. */
  detailFooter?: (session: DescribedSession) => ReactNode
  editing?: SessionEditing
  className?: string
}

const LEVEL_WORD: Record<TrainingLevel, string> = {
  novice: 'Novice', intermediate: 'Intermediate', advanced: 'Advanced', elite: 'Elite',
}

const pill = (on: boolean) => cn(
  'shrink-0 whitespace-nowrap rounded-full border px-2.5 py-1 text-[11px] transition-colors',
  on ? 'border-primary/50 bg-primary/10 font-medium text-foreground'
    : 'border-border/60 text-muted-foreground hover:bg-muted/50 hover:text-foreground',
)

/** One session, whole: what it is, then its blocks — what opens it, what repeats, the rests, what closes it. */
export function SessionDetail({ session: s, group, onExercise, footer, editing, headingId }: {
  session: DescribedSession; group?: DescribedSessionGroup; onExercise?: (id: string) => void
  footer?: ReactNode; editing?: SessionEditing; headingId?: string
}) {
  const blocks = s.blocks ?? []
  const accent = modalityHex(s.modality)
  const facts = [
    modalityLabel(s.modality),
    s.minutes != null ? `${s.minutes} min` : null,
    s.levels.length > 0 ? s.levels.map((l) => LEVEL_WORD[l] ?? l).join(' · ') : null,
  ].filter(Boolean)
  const note = editing?.note ? editing.note(s) : s.note
  return (
    <article className="space-y-4" aria-labelledby={headingId}>
      <header className="flex items-start gap-3">
        <ModalityMark modality={s.modality} icon={s.icon} test={s.test} size="lg" tile />
        <div className="min-w-0 flex-1 space-y-0.5">
          <h4 id={headingId} className="flex flex-wrap items-center gap-2 text-base font-semibold leading-snug">
            <span className="min-w-0 break-words">{editing?.name ? editing.name(s) : s.name}</span>
            {s.test && <Badge variant="outline" className="shrink-0">Test</Badge>}
          </h4>
          <p className="text-xs text-muted-foreground">{facts.join(' · ')}</p>
          {s.equipment.length > 0 && (
            <p className="text-xs text-muted-foreground">Needs {s.equipment.join(', ').toLowerCase()}</p>
          )}
        </div>
      </header>

      {group && <Advice advice={group.advice} byLevel={group.adviceByLevel} className="text-xs" />}

      {blocks.length > 0 ? (
        <>
          <BlockStrip blocks={blocks} accent={accent} className="w-full" />
          <WorkoutBlocks blocks={blocks} accent={accent} onExercise={onExercise}
            renderNote={editing?.slotNote ? (role, text) => editing.slotNote?.(s, role, text) : undefined} />
        </>
      ) : (
        // An older server sends no blocks: the slots, one a line.
        <ul className="space-y-1">
          {s.slots.map((slot, i) => (
            <li key={`${slot.role}-${i}`} className="text-xs">
              {slot.name}
              {slot.prescription && <span className="font-mono text-[11px] text-muted-foreground"> {slot.prescription}</span>}
            </li>
          ))}
        </ul>
      )}

      {note && (
        <div className="space-y-1 border-t border-border/50 pt-3">
          <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">About this session</p>
          <div className="max-w-prose text-xs leading-relaxed text-muted-foreground">{note}</div>
        </div>
      )}
      {footer && <div className="text-xs text-muted-foreground">{footer}</div>}
    </article>
  )
}

/** The list: a heading a group, a row a session — its mark, its name, its minutes.
 *  A group of one (a contract's module and its one session) takes no heading:
 *  its name sits under the session's, where the two differ. */
function SessionList({ visible, shownId, onSelect, onStep }: {
  visible: BrowsedGroup[]; shownId: string | null; onSelect: (id: string) => void; onStep: (step: 1 | -1) => void
}) {
  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return
    event.preventDefault()
    onStep(event.key === 'ArrowDown' ? 1 : -1)
  }
  return (
    // The rows take the focus; the list only hears their arrow keys.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div onKeyDown={onKeyDown}>
      {visible.map(({ key, label, group, sessions }) => {
        const alone = group.sessions.length === 1
        return (
        <section key={key} aria-label={label} className={cn(alone && 'first:pt-2')}>
          {!alone && (
            <h4 className="sticky top-0 z-[1] flex items-baseline justify-between gap-2 bg-card/95 px-3 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground backdrop-blur-sm">
              <span className="truncate">{label}{group.warmUp && <span className="font-normal normal-case tracking-normal"> · opens a day</span>}</span>
              <span className="font-mono font-normal tabular-nums">{sessions.length}</span>
            </h4>
          )}
          <ul className="px-1.5">
            {sessions.map((s) => {
              const current = s.id === shownId
              return (
                <li key={s.id}>
                  <button type="button" data-session={s.id} onClick={() => onSelect(s.id)}
                    aria-current={current ? 'true' : undefined}
                    className={cn('flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs transition-colors [@media(pointer:coarse)]:min-h-11',
                      current ? 'bg-muted font-medium text-foreground' : 'text-foreground/85 hover:bg-muted/50')}>
                    <ModalityMark modality={s.modality} icon={s.icon} test={s.test} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate">{s.name}</span>
                      {alone && label !== s.name && (
                        <span className="block truncate text-[10px] font-normal text-muted-foreground">{label}</span>
                      )}
                    </span>
                    {s.minutes != null && (
                      <span className="shrink-0 font-mono text-[10px] text-muted-foreground tabular-nums">{s.minutes}′</span>
                    )}
                  </button>
                </li>
              )
            })}
          </ul>
        </section>
        )
      })}
    </div>
  )
}

/**
 * Every session of a method, browsed: a list on the left — searched, narrowed
 * to a group or a level — and the one picked on the right, drawn in blocks
 * (docs/frontend-design.md §13.13). On a narrow screen the list stands alone
 * and a session opens in a sheet. It knows nothing of where it is mounted: the
 * caller owns the selection (a URL key) and says where a movement or a footer
 * link leads.
 */
export function SessionBrowser({
  groups, sessions, selectedId, onSelect, onExercise, detailFooter, editing, className,
}: SessionBrowserProps) {
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)
  const [level, setLevel] = useState<TrainingLevel | null>(null)
  const wide = useMediaQuery('(min-width: 1024px)')
  const list = useRef<HTMLDivElement>(null)
  // A long method (two hundred workouts) filters a beat behind the typing.
  const typed = useDeferredValue(query)

  const total = useMemo(() => browse(groups, sessions), [groups, sessions])
  const visible = useMemo(() => browse(groups, sessions, { query: typed, group, level }),
    [groups, sessions, typed, group, level])
  const several = total.filter((g) => g.sessions.length > 1)
  const levels = useMemo(() => levelChoices(sessions, TRAINING_LEVELS), [sessions])
  const count = visible.reduce((n, g) => n + g.sessions.length, 0)
  const all = total.reduce((n, g) => n + g.sessions.length, 0)

  const picked = selectedId ? sessions[selectedId] : undefined
  // Beside the list something is always open: the one picked, else the first listed.
  const shown = picked ?? (wide ? visible[0]?.sessions[0] : undefined)

  function step(by: 1 | -1) {
    const next = neighbour(visible, shown?.id ?? null, by)
    if (!next) return
    onSelect(next)
    list.current?.querySelector<HTMLElement>(`[data-session="${CSS.escape(next)}"]`)?.focus()
  }

  const detail = shown && (
    <SessionDetail key={shown.id} session={shown} group={groupOf(groups, shown.id)} onExercise={onExercise}
      footer={detailFooter?.(shown)} editing={editing} headingId={wide ? 'session-browser-detail' : undefined} />
  )

  return (
    <div className={cn('overflow-hidden rounded-xl border border-border bg-card', className)}>
      <div className="space-y-2 border-b border-border/60 p-3">
        <div className="flex flex-wrap items-center gap-2">
          <SearchField value={query} onChange={setQuery} placeholder="Search sessions and movements…"
            label="Search sessions" className="min-w-48 flex-1 sm:max-w-xs" />
          {levels.length > 0 && (
            <div className="flex items-center gap-1" role="group" aria-label="Level">
              {levels.map((l) => (
                <Tip key={l} label={`Written for ${LEVEL_WORD[l].toLowerCase()}`}>
                  <button type="button" aria-pressed={level === l} onClick={() => setLevel(level === l ? null : l)}
                    className={pill(level === l)}>
                    {LEVEL_WORD[l]}
                  </button>
                </Tip>
              ))}
            </div>
          )}
          <span className="ml-auto font-mono text-[10px] text-muted-foreground tabular-nums" aria-live="polite">
            {count === all ? `${all} session${all === 1 ? '' : 's'}` : `${count} of ${all}`}
          </span>
        </div>
        {/* A group of one is its session: only groups that hold several are worth narrowing to. */}
        {several.length > 1 && (
          <div className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-0.5" role="group" aria-label="Group">
            <button type="button" aria-pressed={group === null} onClick={() => setGroup(null)} className={pill(group === null)}>All</button>
            {several.map((g) => (
              <button key={g.key} type="button" aria-pressed={group === g.key}
                onClick={() => setGroup(group === g.key ? null : g.key)} className={pill(group === g.key)}>
                {g.label} <span className="ml-0.5 font-mono text-[10px] text-muted-foreground">{g.sessions.length}</span>
              </button>
            ))}
          </div>
        )}
      </div>

      {count === 0 ? (
        <EmptyState size="compact" className="m-3" title="No session matches"
          description="Try another word, or clear the filters."
          action={{ label: 'Clear', onClick: () => { setQuery(''); setGroup(null); setLevel(null) } }} />
      ) : (
        <div className="lg:grid lg:h-[min(44rem,calc(100vh-15rem))] lg:grid-cols-[19rem_minmax(0,1fr)]">
          <div ref={list} className="pb-2 lg:overflow-y-auto lg:border-r lg:border-border/60">
            <SessionList visible={visible} shownId={shown?.id ?? null} onSelect={onSelect} onStep={step} />
          </div>
          {wide && <div className="overflow-y-auto p-5">{detail}</div>}
        </div>
      )}

      {!wide && (
        <Sheet open={Boolean(picked)} onOpenChange={(open) => { if (!open) onSelect(null) }}>
          <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-lg">
            <SheetTitle className="sr-only">{picked?.name ?? 'Session'}</SheetTitle>
            <SheetDescription className="sr-only">The session in blocks</SheetDescription>
            <div className="pt-4">{detail}</div>
          </SheetContent>
        </Sheet>
      )}
    </div>
  )
}
