import { useEffect, useId, useRef, useState } from 'react'
import { Plus } from 'lucide-react'
import { Collapse } from '@/components/motion/Collapse'

const input = 'h-9 rounded-md border border-input bg-background px-2 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'

/**
 * A note that is asked for: a button until the athlete wants one, then the
 * field, focused. A note with words is always shown; one left empty folds away.
 */
export function NoteField({ label, addLabel, value, onChange, placeholder }: {
  label: string
  /** The button's words, e.g. "Add a note". */
  addLabel: string
  value: string
  onChange: (text: string) => void
  placeholder?: string
}) {
  const id = useId()
  const [asked, setAsked] = useState(false)
  const field = useRef<HTMLInputElement>(null)
  const open = asked || value !== ''
  useEffect(() => { if (asked) field.current?.focus() }, [asked])
  return (
    <div className="flex flex-col">
      {!open && (
        <button type="button" onClick={() => setAsked(true)}
          className="flex items-center gap-1 self-start rounded text-xs text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <Plus className="size-3" /> {addLabel}
        </button>
      )}
      <Collapse open={open}>
        <div className="flex flex-col gap-1 p-0.5">
          <label htmlFor={id} className="text-xs text-muted-foreground">{label}</label>
          <input id={id} ref={field} value={value} placeholder={placeholder} className={input}
            onChange={(e) => onChange(e.target.value)}
            onBlur={() => { if (value.trim() === '') setAsked(false) }} />
        </div>
      </Collapse>
    </div>
  )
}
