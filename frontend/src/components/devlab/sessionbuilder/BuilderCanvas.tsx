import { useDroppable } from '@dnd-kit/core'
import { Plus } from 'lucide-react'
import type { Exercise } from '@/api/types'
import {
  BLOCK_KINDS, KIND_ORDER, STAGES, blocksOfStage, problemsAt,
  type BlockKind, type BlockStage, type BuilderProblem, type DraftBlock, type DraftSession,
} from '@/lib/sessionBuilder'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { BlockEditor, type BlockActions } from './BlockEditor'

/** Where a dragged exercise or block lands between two blocks of a stage. */
function Gap({ stage, at, label, dragging, alone }: { stage: BlockStage; at: number; label: string; dragging: boolean; alone: boolean }) {
  const { setNodeRef, isOver } = useDroppable({ id: `gap|${stage}|${at}`, data: { type: 'gap', stage, at, title: label } })
  return (
    <div ref={setNodeRef} aria-hidden={!dragging}
      className={cn('rounded-md text-center text-xs text-muted-foreground',
        dragging ? 'my-1 bg-muted py-2' : alone ? 'bg-muted/40 py-3' : 'h-1.5',
        isOver && 'bg-primary/15 text-foreground ring-2 ring-primary/40')}>
      {dragging ? `Drop ${label}` : alone ? 'Drop an exercise here, or add a block' : null}
    </div>
  )
}

export function BuilderCanvas({ draft, exercises, catalog, problems, dragging, actionsFor, onAddBlock }: {
  draft: DraftSession
  exercises: Exercise[]
  catalog: Record<string, Exercise>
  problems: BuilderProblem[]
  /** Something is being dragged: the gaps open. */
  dragging: boolean
  actionsFor: (block: DraftBlock) => BlockActions
  onAddBlock: (kind: BlockKind, stage: BlockStage) => void
}) {
  return (
    <div className="flex flex-col gap-4">
      {STAGES.map((stage) => {
        const blocks = blocksOfStage(draft, stage.id)
        const where = (k: number) => (blocks.length === 0 ? `in ${stage.label}`
          : k === 0 ? `first in ${stage.label}` : k === blocks.length ? `last in ${stage.label}` : `at place ${k + 1} of ${stage.label}`)
        return (
          <section key={stage.id} aria-label={stage.label} className="flex flex-col">
            <div className="mb-1 flex items-center justify-between">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{stage.label}</h3>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="sm" aria-label={`Add a block to ${stage.label}`}>
                    <Plus className="size-4" /> Add block
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  {KIND_ORDER.map((kind) => (
                    <DropdownMenuItem key={kind} onSelect={() => onAddBlock(kind, stage.id)} className="flex flex-col items-start">
                      <span>{BLOCK_KINDS[kind].label}</span>
                      <span className="text-xs text-muted-foreground">{BLOCK_KINDS[kind].hint}</span>
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
            <Gap stage={stage.id} at={0} label={where(0)} dragging={dragging} alone={blocks.length === 0} />
            {blocks.map((block, k) => {
              const index = draft.blocks.indexOf(block)
              return (
                <div key={block.uid}>
                  <BlockEditor block={block} index={index} exercises={exercises} catalog={catalog}
                    actions={actionsFor(block)} problems={problemsAt(problems, index)} />
                  <Gap stage={stage.id} at={k + 1} label={where(k + 1)} dragging={dragging} alone={false} />
                </div>
              )
            })}
          </section>
        )
      })}
    </div>
  )
}
