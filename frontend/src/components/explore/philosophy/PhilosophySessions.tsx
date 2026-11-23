import { useState } from 'react'
import { ChevronDown, ExternalLink, FlaskConical } from 'lucide-react'
import { InlinePanel, ModalityGlyph } from './Glance'
import { Advice } from './Advice'
import { BlockStrip, WorkoutBlocks } from '@/components/blocks/WorkoutBlocks'
import { Collapse } from '@/components/motion/Collapse'
import { EditableText, useMethodEditing } from '@/components/methods/MethodEdit'
import type { DescribedSession, DescribedSessionGroup, PhilosophyDescription } from '@/api/types'
import { useExploreNavigate } from '@/components/explore/topics'
import { cn } from '@/lib/utils'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'

function Session({ session: s }: { session: DescribedSession }) {
  const [open, setOpen] = useState(false)
  const [notes, setNotes] = useState(false)
  const go = useExploreNavigate()
  const accent = modalityHex(s.modality)
  const blocks = s.blocks ?? []
  const editing = useMethodEditing()
  return (
    <li className="rounded-lg border border-border/50 bg-card/40">
      {editing && (
        // The name is edited outside the card's own button.
        <div className="px-3 pt-2 text-xs font-medium">
          <EditableText value={s.name} label="Session name" edits={(name) => ({ sessions: { [s.id]: { name } } })} />
        </div>
      )}
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        aria-label={editing ? `${s.name}, its blocks` : undefined}
        className="flex w-full flex-col gap-1.5 rounded-lg px-3 py-2 text-left hover:bg-muted/20">
        <span className="flex w-full items-center gap-2">
          {s.test && <FlaskConical className="size-3.5 shrink-0 text-muted-foreground" aria-label="test" />}
          <span className="flex-1 truncate text-xs font-medium">{editing ? '' : s.name}</span>
          {s.minutes != null && <span className="font-mono text-[10px] text-muted-foreground">{s.minutes} min</span>}
          <ChevronDown className={cn('size-3.5 shrink-0 text-muted-foreground/60', open && 'rotate-180')} aria-hidden />
        </span>
        <BlockStrip blocks={blocks} accent={accent} className="w-full" />
      </button>
      <Collapse open={open}>
        <div className="space-y-2.5 border-t border-border/30 px-3 py-2.5">
          {blocks.length > 0 ? (
            <WorkoutBlocks blocks={blocks} accent={accent} onExercise={(id) => go('exercises', id)}
              renderNote={editing ? (role, note) => (
                <EditableText value={note} label="Note" multiline
                  edits={(notes) => ({ sessions: { [s.id]: { slots: { [role]: { notes } } } } })} />
              ) : undefined} />
          ) : (
            // An older server sends no blocks: the slots, one a line.
            <ul className="space-y-1">
              {s.slots.map((slot, i) => (
                <li key={`${slot.role}-${i}`} className="text-[11px]">
                  {slot.name}
                  {slot.prescription && <span className="font-mono text-[10px] text-muted-foreground"> {slot.prescription}</span>}
                </li>
              ))}
            </ul>
          )}
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-muted-foreground">
            {s.levels.length > 0 && <span>{s.levels.join(' · ')}</span>}
            {s.equipment.length > 0 && <span>Needs {s.equipment.join(', ').toLowerCase()}</span>}
            {(s.note || editing) && (
              <button type="button" onClick={() => setNotes((n) => !n)} aria-expanded={notes} className="hover:text-foreground">
                About this session
              </button>
            )}
            <button type="button" onClick={() => go('archetypes', s.id)} className="inline-flex items-center gap-1 hover:text-foreground">
              Open as an archetype <ExternalLink className="size-2.5" />
            </button>
          </div>
          <Collapse open={notes}>
            <p className="text-[11px] leading-relaxed text-muted-foreground">
              <EditableText value={s.note} label="Session notes" multiline placeholder="Add a note for this session"
                edits={(notes) => ({ sessions: { [s.id]: { notes } } })} />
            </p>
          </Collapse>
        </div>
      </Collapse>
    </li>
  )
}

function groupLabel(g: DescribedSessionGroup): string {
  if (g.name) return g.name
  return modalityLabel(g.modality) || 'Other'
}

/** One group as a tile: its modality's icon and colour, its name, how many. */
function GroupTile({ group, selected, onOpen }: { group: DescribedSessionGroup; selected: boolean; onOpen: () => void }) {
  return (
    <button type="button" onClick={onOpen} aria-expanded={selected}
      className={cn('flex items-center gap-2 rounded-md border px-2.5 py-2 text-left transition-colors hover:border-primary/40',
        selected ? 'border-primary/50 bg-primary/10' : 'border-border/50 bg-card/60')}
      style={group.modality ? { borderLeftColor: modalityHex(group.modality), borderLeftWidth: 3 } : undefined}>
      {group.kind === 'tests'
        ? <FlaskConical className="size-4 shrink-0 text-muted-foreground" />
        : <ModalityGlyph modality={group.modality} className="size-4" />}
      <span className="min-w-0 flex-1 truncate text-xs font-medium">{groupLabel(group)}</span>
      <span className="font-mono text-[11px] text-muted-foreground tabular-nums">{group.sessions.length}</span>
    </button>
  )
}

/**
 * Every session the package writes, as tiles grouped as the method groups
 * them — a template's day categories in the source's order, a contract's
 * modules, the rest by modality, tests last. A tile opens its sessions in
 * place, under the tiles; each slot lists the exercises the generator can
 * give it (the server applies the selector's rule).
 */
export function PhilosophySessions({ doc }: { doc: PhilosophyDescription }) {
  const [openKey, setOpenKey] = useState<string | null>(null)
  const key = (g: DescribedSessionGroup) => `${g.kind}-${g.id}`
  const open = doc.groups.find((g) => key(g) === openKey)
  return (
    <div className="space-y-2">
      <div className="grid gap-1.5 grid-cols-[repeat(auto-fill,minmax(11rem,1fr))]">
        {doc.groups.map((g) => (
          <GroupTile key={key(g)} group={g} selected={key(g) === openKey}
            onOpen={() => setOpenKey((cur) => (cur === key(g) ? null : key(g)))} />
        ))}
      </div>
      {open && (
        <InlinePanel key={openKey} accent={open.modality ? modalityHex(open.modality) : undefined}
          onClose={() => setOpenKey(null)}
          title={<span className="flex items-center gap-2">
            {open.modality && <ModalityGlyph modality={open.modality} className="size-4" />}
            {groupLabel(open)}
          </span>}
          subtitle={<>
            {open.sessions.length} session{open.sessions.length === 1 ? '' : 's'}
            {open.name && open.modality ? ` · ${modalityLabel(open.modality)}` : ''}
            {open.warmUp ? ' · opens a day' : ''}
          </>}>
          <Advice advice={open.advice} byLevel={open.adviceByLevel} className="mb-2 text-[11px]" />
          <ul className="grid items-start gap-2 md:grid-cols-2">
            {open.sessions.map((id) => doc.sessions[id] && <Session key={id} session={doc.sessions[id]} />)}
          </ul>
        </InlinePanel>
      )}
    </div>
  )
}
