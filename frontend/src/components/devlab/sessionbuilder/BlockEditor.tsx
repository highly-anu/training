import { useId, type ReactNode } from 'react'
import { useDraggable, useDroppable } from '@dnd-kit/core'
import { ChevronDown, ChevronUp, GripVertical, MoreHorizontal, Trash2 } from 'lucide-react'
import type { Exercise } from '@/api/types'
import {
  BLOCK_KINDS, FIELD_LABELS, INTENSITY_LABELS, KIND_ORDER, LOAD_INTENSITIES, STAGES, ZONE_INTENSITIES, countText, withCount,
  type BlockKind, type BlockStage, type BuilderProblem, type DraftBlock, type DraftMovement, type ProgressField,
  type ProgressRule,
} from '@/lib/sessionBuilder'
import { NumberField } from '@/components/ui/number-field'
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'
import { ExerciseCombobox } from './ExerciseCombobox'

export interface BlockActions {
  update: (patch: Partial<DraftBlock>) => void
  setKind: (kind: BlockKind) => void
  remove: () => void
  nudge: (by: -1 | 1) => void
  toStage: (stage: BlockStage) => void
  addExercise: (exercise: Exercise) => void
  updateMovement: (uid: string, patch: Partial<DraftMovement>) => void
  replaceMovement: (uid: string, movement: DraftMovement) => void
  removeMovement: (uid: string) => void
  nudgeMovement: (uid: string, by: -1 | 1) => void
}

const STEP: Partial<Record<string, number>> = { start_kg: 2.5, add_kg: 0.5, rest_sec: 15, work_sec: 5, hold_sec: 5, add_sec: 5, distance_m: 50, add_m: 50 }
const iconButton = 'rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-30'
const textInput = 'h-9 rounded-md border border-input bg-background px-2 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'

function TextField({ label, value, onChange, placeholder, invalid, className }: {
  label: string; value: string; onChange: (text: string) => void; placeholder?: string; invalid?: boolean; className?: string
}) {
  const id = useId()
  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <label htmlFor={id} className="text-xs text-muted-foreground">{label}</label>
      <input id={id} value={value} placeholder={placeholder} aria-invalid={invalid || undefined}
        onChange={(e) => onChange(e.target.value)} className={cn(textInput, invalid && 'border-bad')} />
    </div>
  )
}

function Choice({ label, value, onChange, children, className }: {
  label: string; value: string; onChange: (value: string) => void; children: ReactNode; className?: string
}) {
  const id = useId()
  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <label htmlFor={id} className="text-xs text-muted-foreground">{label}</label>
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)} className={cn(textInput, 'pr-6')}>
        {children}
      </select>
    </div>
  )
}

/** The steps a movement (or a piece) takes each week. Empty fields are no step. */
function ProgressFields({ fields, rule, onChange, about, earnable = false }: {
  fields: ProgressField[]; rule: ProgressRule | undefined; onChange: (rule: ProgressRule | undefined) => void; about: string
  /** Its steps may be earned from the log instead of dated (a movement's, never a piece's). */
  earnable?: boolean
}) {
  const id = useId()
  if (!fields.length) return null
  const set = (field: ProgressField, value: number | undefined) => {
    const next = { ...(rule ?? {}), [field]: value }
    if (value === undefined) delete next[field]
    onChange(Object.keys(next).length ? next : undefined)
  }
  const stepping = fields.some((f) => rule?.[f] !== undefined)
  return (
    <fieldset className="flex flex-wrap items-end gap-2 rounded-md bg-muted/50 px-2 py-1.5">
      <legend className="sr-only">{`Each week: ${about}`}</legend>
      <span className="pb-2 text-xs font-medium text-muted-foreground" aria-hidden>{rule?.earned ? 'Each session made' : 'Each week'}</span>
      {fields.map((field) => (
        <NumberField key={field} label={FIELD_LABELS[field]} value={rule?.[field]} step={STEP[field] ?? 1}
          min={field === 'add_kg' ? 0.5 : 1} onChange={(v) => set(field, v)} className="w-24" />
      ))}
      {earnable && stepping && (
        <label htmlFor={id} className="flex items-center gap-1.5 pb-2 text-xs text-muted-foreground">
          <input id={id} type="checkbox" checked={!!rule?.earned} className="size-3.5 accent-primary"
            onChange={(e) => onChange({ ...(rule ?? {}), earned: e.target.checked || undefined })} />
          Earned from the log: a missed session repeats
        </label>
      )}
    </fieldset>
  )
}

function MovementRow({ block, movement, index, name, actions, problems }: {
  block: DraftBlock; movement: DraftMovement; index: number; name: string; actions: BlockActions; problems: BuilderProblem[]
}) {
  const spec = BLOCK_KINDS[block.kind]
  const mine = problems.filter((p) => p.movement === index)
  const bad = (field: string) => mine.some((p) => p.field === field)
  const set = (patch: Partial<DraftMovement>) => actions.updateMovement(movement.uid, patch)
  return (
    <li className="flex flex-col gap-2 rounded-md border bg-background p-2">
      <div className="flex items-center gap-1">
        <span className="min-w-0 flex-1 truncate text-sm font-medium">{name}</span>
        {block.movements.length > 1 && (
          <>
            <Tip label="Move up"><button type="button" aria-label={`Move ${name} up`} disabled={index === 0}
              onClick={() => actions.nudgeMovement(movement.uid, -1)} className={iconButton}><ChevronUp className="size-4" /></button></Tip>
            <Tip label="Move down"><button type="button" aria-label={`Move ${name} down`} disabled={index === block.movements.length - 1}
              onClick={() => actions.nudgeMovement(movement.uid, 1)} className={iconButton}><ChevronDown className="size-4" /></button></Tip>
          </>
        )}
        <Tip label="Remove"><button type="button" aria-label={`Remove ${name}`} onClick={() => actions.removeMovement(movement.uid)}
          className={iconButton}><Trash2 className="size-4" /></button></Tip>
      </div>
      {spec.movement.length > 0 && (
        <div className="flex flex-wrap items-end gap-2">
          {spec.movement.map((field) => {
            const label = `${FIELD_LABELS[field]}`
            if (field === 'reps') {
              return <TextField key={field} label={label} className="w-24" placeholder="8, max, 8-12" invalid={bad('reps')}
                value={movement.reps === undefined ? '' : String(movement.reps)}
                onChange={(text) => set({ reps: /^\d+$/.test(text.trim()) ? Number(text) : text })} />
            }
            if (field === 'count') {
              return <TextField key={field} label={label} className="w-28" placeholder="10, 21-15-9, 400 m" invalid={bad('reps')}
                value={countText(movement)} onChange={(text) => actions.replaceMovement(movement.uid, withCount(movement, text))} />
            }
            if (field === 'load_text') {
              return <TextField key={field} label={label} className="w-36" placeholder="bodyweight, a pair" value={movement.load_text ?? ''}
                onChange={(text) => set({ load_text: text })} />
            }
            return <NumberField key={field} label={label} value={movement[field]} step={STEP[field] ?? 1} invalid={bad(field)}
              min={field === 'start_kg' || field === 'rest_sec' ? 0 : 1} onChange={(v) => set({ [field]: v })} className="w-24" />
          })}
        </div>
      )}
      <ProgressFields fields={spec.progress.filter((f) => f === 'add_kg' ? movement.start_kg !== undefined
        : f === 'add_reps' || f === 'top_reps' ? typeof movement.reps === 'number' : true)}
        rule={movement.progress} onChange={(progress) => set({ progress })} about={name} earnable />
      {mine.map((p) => <p key={p.message} role="alert" className="text-xs text-bad">{p.message}</p>)}
    </li>
  )
}

/** One block of the session: its kind, its numbers, its exercises. Takes a dropped exercise. */
export function BlockEditor({ block, index, exercises, catalog, actions, problems }: {
  block: DraftBlock
  /** Its place in the session, which is how the server names it in a problem. */
  index: number
  exercises: Exercise[]
  catalog: Record<string, Exercise>
  actions: BlockActions
  problems: BuilderProblem[]
}) {
  const spec = BLOCK_KINDS[block.kind]
  const title = `${spec.label} ${index + 1}`
  const { attributes, listeners, setNodeRef: dragRef, setActivatorNodeRef, isDragging } = useDraggable({
    id: `blk|${block.uid}`, data: { type: 'block', uid: block.uid, title },
  })
  const { setNodeRef: dropRef, isOver, active } = useDroppable({
    id: `block|${block.uid}`, data: { type: 'block', uid: block.uid, title },
  })
  const over = isOver && active?.data.current?.type === 'exercise'
  const own = problems.filter((p) => p.movement === null)
  const bad = (field: string) => own.some((p) => p.field === field)
  const intensities = spec.intensity === 'zone' ? ZONE_INTENSITIES : spec.intensity === 'load' ? LOAD_INTENSITIES
    : spec.intensity === 'both' ? [...ZONE_INTENSITIES, ...LOAD_INTENSITIES] : []
  const full = spec.max !== undefined && block.movements.length >= spec.max

  return (
    <article ref={(node) => { dragRef(node); dropRef(node) }} aria-label={title}
      className={cn('flex flex-col gap-2 rounded-lg border bg-card p-3', over && 'border-primary ring-2 ring-primary/30',
        isDragging && 'opacity-40', problems.length > 0 && 'border-bad')}>
      <header className="flex items-end gap-2">
        <Tip label="Drag to move">
          <button type="button" ref={setActivatorNodeRef} {...attributes} {...listeners}
            aria-label={`Move ${title}`} className={cn(iconButton, 'mb-1.5 cursor-grab touch-none active:cursor-grabbing')}>
            <GripVertical className="size-4" />
          </button>
        </Tip>
        <Choice label="Block" value={block.kind} onChange={(kind) => actions.setKind(kind as BlockKind)} className="w-40">
          {KIND_ORDER.map((kind) => <option key={kind} value={kind}>{BLOCK_KINDS[kind].label}</option>)}
        </Choice>
        {intensities.length > 0 && (
          <Choice label="Intensity" value={block.intensity ?? ''} onChange={(v) => actions.update({ intensity: v || undefined })} className="w-32">
            <option value="">Not set</option>
            {intensities.map((i) => <option key={i} value={i}>{INTENSITY_LABELS[i]}</option>)}
          </Choice>
        )}
        <div className="flex-1" />
        <DropdownMenu>
          <Tip label="Move or delete">
            <DropdownMenuTrigger asChild>
              <button type="button" aria-label={`${title}: move or delete`} className={cn(iconButton, 'mb-1.5')}>
                <MoreHorizontal className="size-4" />
              </button>
            </DropdownMenuTrigger>
          </Tip>
          <DropdownMenuContent align="end">
            <DropdownMenuLabel>Move to</DropdownMenuLabel>
            <DropdownMenuItem onSelect={() => actions.nudge(-1)}>Earlier</DropdownMenuItem>
            <DropdownMenuItem onSelect={() => actions.nudge(1)}>Later</DropdownMenuItem>
            {STAGES.filter((s) => s.id !== block.stage).map((s) => (
              <DropdownMenuItem key={s.id} onSelect={() => actions.toStage(s.id)}>{s.label}</DropdownMenuItem>
            ))}
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={actions.remove}>Delete block</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </header>

      {spec.block.length > 0 && (
        <div className="flex flex-wrap items-end gap-2">
          {spec.block.map((field) => (
            <NumberField key={field} label={FIELD_LABELS[field]} value={block[field]} step={STEP[field] ?? 1} invalid={bad(field)}
              min={field === 'rest_sec' ? 0 : field === 'rest_until_hr_pct' ? 50 : 1} max={field === 'rest_until_hr_pct' ? 90 : undefined}
              onChange={(v) => actions.update({ [field]: v })} className={field === 'rest_until_hr_pct' ? 'w-52' : 'w-28'} />
          ))}
        </div>
      )}
      <ProgressFields fields={spec.blockProgress ?? []} rule={block.progress} onChange={(progress) => actions.update({ progress })} about={title} />

      <ul className="flex flex-col gap-1.5">
        {block.movements.map((movement, i) => (
          <MovementRow key={movement.uid} block={block} movement={movement} index={i} actions={actions} problems={problems}
            name={catalog[movement.exercise_id]?.name ?? movement.exercise_id} />
        ))}
      </ul>
      {!full && (
        <ExerciseCombobox exercises={exercises} onPick={actions.addExercise} label={`Add an exercise to ${title}`}
          placeholder={block.movements.length ? 'Add another exercise…' : 'Type an exercise, or drop one here…'} />
      )}
      <TextField label="Note" value={block.note ?? ''} onChange={(note) => actions.update({ note })} placeholder="Tempo, each side, how to do it" />
      {own.map((p) => <p key={p.message} role="alert" className="text-xs text-bad">{p.message}</p>)}
    </article>
  )
}
