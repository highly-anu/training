import { Search, X } from 'lucide-react'
import { cn } from '@/lib/utils'

/** A list's search: the field, its icon and a way to clear it. */
export function SearchField({ value, onChange, placeholder, label, className }: {
  value: string; onChange: (value: string) => void; placeholder: string
  /** What it searches, for a screen reader; the placeholder otherwise. */
  label?: string; className?: string
}) {
  return (
    <div className={cn('relative', className)}>
      <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3 -translate-y-1/2 text-muted-foreground" aria-hidden />
      <input
        type="search"
        aria-label={label ?? placeholder}
        placeholder={placeholder}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="h-8 w-full rounded-md border border-border bg-background pl-7 pr-7 text-xs [&::-webkit-search-cancel-button]:hidden focus:outline-none focus:ring-1 focus:ring-primary/50"
      />
      {value && (
        <button type="button" onClick={() => onChange('')} aria-label="Clear search"
          className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
          <X className="size-3" />
        </button>
      )}
    </div>
  )
}
