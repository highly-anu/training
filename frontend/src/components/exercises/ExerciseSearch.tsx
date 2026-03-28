import { Search, X } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

interface ExerciseSearchProps {
  value: string
  onChange: (v: string) => void
}

export function ExerciseSearch({ value, onChange }: ExerciseSearchProps) {
  return (
    <div className="relative">
      <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-3.5 text-muted-foreground" />
      <Input
        placeholder="Search exercises…"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="pl-9 pr-8 h-9 text-sm"
      />
      {value && (
        <Button
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 -translate-y-1/2 size-6"
          onClick={() => onChange('')}
        >
          <X className="size-3" />
        </Button>
      )}
    </div>
  )
}
