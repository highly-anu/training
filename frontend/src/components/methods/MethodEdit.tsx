import { createContext, useContext, useState, type ReactNode } from 'react'
import { Check, Pencil, X } from 'lucide-react'
import { useEditMethod, type MethodEdits } from '@/api/methods'
import { editRefusal, NAME_MAX, TEXT_MAX } from '@/lib/methodBuild'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

/**
 * Editing the words of one's own method where they are read (Explore ▸ a
 * method's page): a name, a summary, a note. Each field saves by itself, at
 * once — no build — through PATCH /api/methods/<id>; numbers and structure
 * are not here (they change with a revise).
 */
const MethodEditContext = createContext<{ id: string } | null>(null)

/** Turns the page's words editable for the method `id`; without it they are read-only. */
export function MethodEditProvider({ id, children }: { id: string | null; children: ReactNode }) {
  return <MethodEditContext.Provider value={id ? { id } : null}>{children}</MethodEditContext.Provider>
}

/** Whether the words around are being edited (a method of the athlete's own, its Edit switch on). */
// eslint-disable-next-line react-refresh/only-export-components
export function useMethodEditing(): boolean {
  return useContext(MethodEditContext) !== null
}

/**
 * A piece of the method's text. Read-only it is its children (else the text);
 * while the page is being edited it carries a pencil that opens a field in
 * place, with Save and Cancel.
 */
export function EditableText({ value, edits, label, multiline = false, placeholder, children, className }: {
  value: string | null | undefined
  /** The edit that writes `text` (an empty one clears an optional note). */
  edits: (text: string) => MethodEdits
  /** What is being edited, for the controls' names: "Session name". */
  label: string
  multiline?: boolean
  /** Shown, while editing, where there is no text yet: "Add a note". */
  placeholder?: string
  children?: ReactNode
  className?: string
}) {
  const ctx = useContext(MethodEditContext)
  const [open, setOpen] = useState(false)
  const [text, setText] = useState('')
  const edit = useEditMethod()
  const shown = children ?? value
  if (!ctx) return <>{shown}</>

  const start = () => { setText(value ?? ''); edit.reset(); setOpen(true) }
  const trimmed = text.trim()
  const invalid = multiline ? trimmed.length > TEXT_MAX : trimmed.length < 1 || trimmed.length > NAME_MAX
  const save = () => {
    if (invalid) return
    if (trimmed === (value ?? '').trim()) { setOpen(false); return }
    edit.mutate({ id: ctx.id, edits: edits(trimmed) }, { onSuccess: () => setOpen(false) })
  }

  const focus = (el: HTMLInputElement | HTMLTextAreaElement | null) => { if (el && document.activeElement !== el) el.focus() }
  const escape = (e: React.KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }

  if (!open) {
    return (
      <span className={cn('inline-flex max-w-full items-start gap-1', className)}>
        {shown ? <span className="min-w-0">{shown}</span>
          : <span className="text-muted-foreground/60">{placeholder ?? label}</span>}
        <Tip label={`Edit ${label.toLowerCase()}`}>
          <button type="button" onClick={start} aria-label={`Edit ${label.toLowerCase()}`}
            className="flex size-5 shrink-0 items-center justify-center rounded text-muted-foreground/70 hover:bg-muted/50 hover:text-foreground">
            <Pencil className="size-3" aria-hidden />
          </button>
        </Tip>
      </span>
    )
  }
  return (
    <form className={cn('flex w-full flex-col gap-1.5', className)}
      onSubmit={(e) => { e.preventDefault(); e.stopPropagation(); save() }}>
      {/* The field takes the focus its pencil had; Escape leaves it as it was. */}
      {multiline
        ? <Textarea value={text} onChange={(e) => setText(e.target.value)} rows={3} aria-label={label}
            ref={focus} onKeyDown={escape} className="text-xs" />
        : <Input value={text} onChange={(e) => setText(e.target.value)} aria-label={label}
            ref={focus} onKeyDown={escape} className="h-8 text-sm" />}
      <span className="flex items-center gap-1.5">
        <Button type="submit" size="sm" disabled={invalid} loading={edit.isPending}>
          <Check className="mr-1 size-3.5" /> Save
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setOpen(false)}>
          <X className="mr-1 size-3.5" /> Cancel
        </Button>
        {edit.isError && <span role="alert" className="text-[11px] text-bad">{editRefusal(edit.error)}</span>}
      </span>
    </form>
  )
}
