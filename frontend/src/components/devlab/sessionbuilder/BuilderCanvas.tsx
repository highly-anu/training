import type { ReactNode } from 'react'
import { useDroppable } from '@dnd-kit/core'
import { Plus } from 'lucide-react'
import type { Exercise } from '@/api/types'
import {
  BLOCK_KINDS, KIND_ORDER, STAGES, blockReady, blocksOfStage, canNudge, problemsAt,
  type BlockKind, type BlockStage, type BuilderProblem, type DraftBlock, type DraftSession,
} from '@/lib/sessionBuilder'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { BlockEditor, type BlockActions } from './BlockEditor'
import { ExerciseCombobox } from './ExerciseCombobox'

/** Where a dragged exercise or block lands between two blocks of a part. Only a drag shows it. */
function Gap({ stage, at, label, dragging }: { stage: BlockStage; at: number; label: string; dragging: boolean }) {
  const { setNodeRef, isOver } = useDroppable({ id: `gap|${stage}|${at}`, data: { type: 'gap', stage, at, title: label } })
  return (
    <div ref={setNodeRef} aria-hidden={!dragging}
      className={cn('rounded-md text-center text-xs text-muted-foreground', dragging ? 'bg-muted py-2' : 'h-1.5',
        isOver && 'bg-primary/15 text-foreground ring-2 ring-primary/40')}>
      {dragging ? `Drop ${label}` : null}
    </div>
  )
}

/**
 * The session as one list of blocks. A block's part (Start, Main work, Finisher,
 * Cool-down) is its own choice; a part's heading shows once a block is in it,
 * and none while everything is Main work. The next block is offered once every
 * block has its exercise.
 */
export function BuilderCanvas({ draft, exercises, catalog, problems, dragging, actionsFor, onAddBlock, onFirstExercise, onMenuClosed }: {
  draft: DraftSession
  exercises: Exercise[]
  catalog: Record<string, Exercise>
  problems: BuilderProblem[]
  /** Something is being dragged: the gaps open. */
  dragging: boolean
  actionsFor: (block: DraftBlock) => BlockActions
  onAddBlock: (kind: BlockKind) => void
  /** The exercise typed into an empty session. */
  onFirstExercise: (exercise: Exercise) => void
  /** A menu closed: keeps the focus where the action put it. */
  onMenuClosed: (e: Event) => void
}) {
  const parts = draft.blocks.some((b) => b.stage !== 'main')
  const rows: ReactNode[] = []
  for (const stage of STAGES) {
    const blocks = blocksOfStage(draft, stage.id)
    if (blocks.length === 0 && !(stage.id === 'main' && draft.blocks.length === 0)) continue
    const where = (k: number) => (blocks.length === 0 ? `in ${stage.label}`
      : k === 0 ? `first in ${stage.label}` : k === blocks.length ? `last in ${stage.label}` : `at place ${k + 1} of ${stage.label}`)
    if (parts) {
      rows.push(
        <h3 key={`part|${stage.id}`} className="mt-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground first:mt-0">
          {stage.label}
        </h3>,
      )
    }
    rows.push(<Gap key={`gap|${stage.id}|0`} stage={stage.id} at={0} label={where(0)} dragging={dragging} />)
    blocks.forEach((block, k) => {
      const index = draft.blocks.indexOf(block)
      rows.push(
        <div key={block.uid}>
          <BlockEditor block={block} index={index} exercises={exercises} catalog={catalog}
            actions={actionsFor(block)} problems={problemsAt(problems, index)}
            canEarlier={canNudge(draft, block.uid, -1)} canLater={canNudge(draft, block.uid, 1)} onMenuClosed={onMenuClosed} />
          <Gap stage={stage.id} at={k + 1} label={where(k + 1)} dragging={dragging} />
        </div>,
      )
    })
  }

  return (
    <div data-canvas className="flex flex-col">
      {draft.blocks.length === 0 && (
        <ExerciseCombobox exercises={exercises} onPick={onFirstExercise} label="The first exercise"
          placeholder="Type the first exercise…" />
      )}
      {rows}
      {draft.blocks.length > 0 && draft.blocks.every(blockReady) && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" data-focus="add-block" className="mt-2 self-start">
              <Plus className="size-4" /> Add block
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" onCloseAutoFocus={onMenuClosed}>
            {KIND_ORDER.map((kind) => (
              <DropdownMenuItem key={kind} onSelect={() => onAddBlock(kind)} className="flex flex-col items-start">
                <span>{BLOCK_KINDS[kind].label}</span>
                <span className="text-xs text-muted-foreground">{BLOCK_KINDS[kind].hint}</span>
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </div>
  )
}
