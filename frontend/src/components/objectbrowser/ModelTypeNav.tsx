import { Dumbbell, Layers, Gauge, Network, BookOpen, BarChart2, Shield, Package } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { ModelType } from './types'

interface ModelTypeNavProps {
  selected: ModelType
  onSelect: (type: ModelType) => void
  counts: Record<ModelType, number>
}

const MODEL_TYPES: { type: ModelType; label: string; icon: React.ElementType }[] = [
  { type: 'exercises', label: 'Exercises', icon: Dumbbell },
  { type: 'archetypes', label: 'Archetypes', icon: Layers },
  { type: 'modalities', label: 'Modalities', icon: Gauge },
  { type: 'frameworks', label: 'Frameworks', icon: Network },
  { type: 'philosophies', label: 'Philosophies', icon: BookOpen },
  { type: 'benchmarks', label: 'Benchmarks', icon: BarChart2 },
  { type: 'injuryFlags', label: 'Injury Flags', icon: Shield },
  { type: 'equipmentProfiles', label: 'Equipment Profiles', icon: Package },
]

export function ModelTypeNav({ selected, onSelect, counts }: ModelTypeNavProps) {
  return (
    <div className="flex flex-col h-full border-r bg-muted/10">
      <div className="px-3 py-3 border-b">
        <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
          Model Types
        </p>
      </div>
      <div className="flex-1 overflow-y-auto py-1">
        {MODEL_TYPES.map(({ type, label, icon: Icon }) => (
          <button
            key={type}
            onClick={() => onSelect(type)}
            className={cn(
              'w-full flex items-center gap-2.5 px-3 py-2 text-sm transition-colors text-left',
              selected === type
                ? 'bg-primary/10 border-l-2 border-primary text-primary font-medium'
                : 'border-l-2 border-transparent text-muted-foreground hover:bg-muted hover:text-foreground'
            )}
          >
            <Icon className="size-4 shrink-0" />
            <span className="flex-1 truncate">{label}</span>
            <span className="text-[10px] font-mono text-muted-foreground bg-muted rounded px-1">
              {counts[type] ?? 0}
            </span>
          </button>
        ))}
      </div>
    </div>
  )
}
