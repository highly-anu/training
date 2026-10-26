import { cn } from '@/lib/utils'
import type { EquipmentId } from '@/api/types'
import { EQUIPMENT_GROUPS } from '@/lib/equipment'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

const EQUIPMENT_PRESETS = [
  {
    id: 'barbell_gym',
    name: 'Full Gym',
    desc: 'Barbell, rack, kettlebells, cardio machines',
    equipment: ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'rings', 'rower', 'box'],
  },
  {
    id: 'home_kb_only',
    name: 'Home — KB',
    desc: 'Kettlebells, pull-up bar, bands',
    equipment: ['kettlebell', 'pull_up_bar', 'resistance_band', 'jump_rope'],
  },
  {
    id: 'bodyweight_only',
    name: 'Bodyweight',
    desc: 'No equipment, calisthenics only',
    equipment: ['pull_up_bar', 'parallettes', 'jump_rope'],
  },
  {
    id: 'outdoor_ruck_only',
    name: 'Outdoor / Ruck',
    desc: 'Ruck pack and open terrain',
    equipment: ['ruck_pack', 'open_space'],
  },
  {
    id: 'home_barbell',
    name: 'Home — Barbell',
    desc: 'Barbell + rack at home + KB',
    equipment: ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar'],
  },
] as const

// Items with no exercises — shown grayed out, non-interactive. Horsemen's
// named workouts use the GHD, medicine ball, sled and tire (2026-10-19).
const NO_EXERCISES = new Set<EquipmentId>([])

// Auto-add these when the key item is checked (one-directional)
const DEPS: Partial<Record<EquipmentId, EquipmentId[]>> = {
  barbell: ['rack', 'plates'],
}

// Structural sentinel — never shown, always present in outgoing array
const SENTINEL: EquipmentId = 'open_space'

interface EquipmentPickerProps {
  selected: EquipmentId[]
  onChange: (equipment: EquipmentId[]) => void
}

export function EquipmentPicker({ selected, onChange }: EquipmentPickerProps) {
  const visibleSelected = selected.filter((e) => e !== SENTINEL)

  const activePreset = EQUIPMENT_PRESETS.find((p) => {
    const presetItems = p.equipment.filter((e) => e !== SENTINEL)
    return (
      presetItems.length === visibleSelected.length &&
      presetItems.every((e) => visibleSelected.includes(e as EquipmentId))
    )
  })

  function emit(items: EquipmentId[]) {
    const without = items.filter((e) => e !== SENTINEL)
    onChange([...without, SENTINEL])
  }

  function selectPreset(equipment: readonly string[]) {
    emit(equipment as EquipmentId[])
  }

  function toggleItem(id: EquipmentId) {
    if (NO_EXERCISES.has(id)) return
    if (selected.includes(id)) {
      emit(selected.filter((e) => e !== id))
    } else {
      const deps = (DEPS[id] ?? []).filter((d) => !selected.includes(d))
      emit([...selected, id, ...deps])
    }
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
        {EQUIPMENT_PRESETS.map((preset) => (
          <button
            key={preset.id}
            type="button"
            onClick={() => selectPreset(preset.equipment)}
            className={cn(
              'rounded-lg border p-3 text-left text-xs transition-colors',
              activePreset?.id === preset.id
                ? 'border-primary bg-primary/10 text-primary'
                : 'border-border bg-card text-muted-foreground hover:border-primary/50 hover:text-foreground'
            )}
          >
            <div className="font-semibold text-[11px] leading-tight mb-0.5">{preset.name}</div>
            <div className="text-[10px] leading-tight opacity-70">{preset.desc}</div>
          </button>
        ))}
      </div>

      <TooltipProvider>
        <div className="space-y-3">
          {EQUIPMENT_GROUPS.map((group) => (
            <div key={group.name}>
              <p className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                {group.name}
              </p>
              <div className="grid grid-cols-2 gap-1 sm:grid-cols-3">
                {group.items.map(({ id, label }) => {
                  const disabled = NO_EXERCISES.has(id)
                  const checked = selected.includes(id)
                  const row = (
                    <div
                      key={id}
                      className={cn(
                        'flex items-center gap-2 rounded px-2 py-1',
                        disabled
                          ? 'cursor-not-allowed opacity-40'
                          : 'cursor-pointer hover:bg-muted/50'
                      )}
                      onClick={() => !disabled && toggleItem(id)}
                    >
                      <Checkbox
                        id={`eq-${id}`}
                        checked={checked}
                        disabled={disabled}
                        onCheckedChange={() => toggleItem(id)}
                        className="pointer-events-none"
                      />
                      <Label
                        htmlFor={`eq-${id}`}
                        className={cn('text-xs', disabled ? 'cursor-not-allowed' : 'cursor-pointer')}
                      >
                        {label}
                      </Label>
                    </div>
                  )
                  return disabled ? (
                    <Tooltip key={id}>
                      <TooltipTrigger asChild>{row}</TooltipTrigger>
                      <TooltipContent side="top" className="text-xs">No exercises yet</TooltipContent>
                    </Tooltip>
                  ) : row
                })}
              </div>
            </div>
          ))}
        </div>
      </TooltipProvider>

      {visibleSelected.length > 0 && (
        <p className="text-xs text-muted-foreground">
          {visibleSelected.length} item{visibleSelected.length !== 1 ? 's' : ''} selected:{' '}
          <span className="text-foreground">
            {visibleSelected.slice(0, 5).join(', ')}
            {visibleSelected.length > 5 ? ` +${visibleSelected.length - 5} more` : ''}
          </span>
        </p>
      )}
    </div>
  )
}
