import { cn } from '@/lib/utils'
import type { ModelType } from './types'
import type {
  Exercise, Archetype, Modality, GoalProfile, Framework,
  Philosophy, BenchmarkStandard, InjuryFlag, EquipmentProfile,
} from '@/api/types'

type AnyItem = Exercise | Archetype | Modality | GoalProfile | Framework | Philosophy | BenchmarkStandard | InjuryFlag | EquipmentProfile

function getSubtitle(type: ModelType, item: AnyItem): string {
  switch (type) {
    case 'exercises': {
      const e = item as Exercise
      return `${e.category} · ${e.effort}`
    }
    case 'archetypes': {
      const a = item as Archetype
      return `${a.modality} · ${a.duration_estimate_minutes}min`
    }
    case 'modalities': {
      const m = item as Modality
      return `recovery: ${m.recovery_cost}`
    }
    case 'goals': {
      const g = item as GoalProfile
      const count = Object.keys(g.priorities).length
      return `${count} modalities`
    }
    case 'frameworks': {
      const f = item as Framework
      return `${f.goals_served?.length ?? 0} modalities served`
    }
    case 'philosophies': {
      const p = item as Philosophy
      return `${p.core_principles?.length ?? 0} principles`
    }
    case 'benchmarks': {
      const b = item as BenchmarkStandard
      return `${b.domain ?? b.category} · ${b.unit}`
    }
    case 'injuryFlags': {
      const f = item as InjuryFlag
      return `${f.excluded_movement_patterns?.length ?? 0} excluded patterns`
    }
    case 'equipmentProfiles': {
      const p = item as EquipmentProfile
      return `${p.equipment?.length ?? 0} items`
    }
    default:
      return ''
  }
}

interface ObjectListItemProps {
  type: ModelType
  item: AnyItem
  selected: boolean
  onClick: () => void
}

export function ObjectListItem({ type, item, selected, onClick }: ObjectListItemProps) {
  const name = (item as { name?: string; id: string }).name ?? (item as { id: string }).id
  const subtitle = getSubtitle(type, item)

  return (
    <button
      onClick={onClick}
      className={cn(
        'w-full text-left px-3 py-2.5 border-b border-border/50 transition-colors',
        selected
          ? 'bg-primary/10 text-primary'
          : 'hover:bg-muted/60 text-foreground'
      )}
    >
      <div className="text-sm font-medium truncate">{name}</div>
      {subtitle && (
        <div className="text-[11px] text-muted-foreground mt-0.5 truncate">{subtitle}</div>
      )}
    </button>
  )
}
