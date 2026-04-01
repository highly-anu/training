import { CrossRefBadge } from '../CrossRefBadge'
import type { EquipmentProfile, Exercise } from '@/api/types'
import type { NavigateToFn } from '../types'

interface EquipmentProfileDetailProps {
  profile: EquipmentProfile
  exercises: Exercise[]
  navigateTo: NavigateToFn
}

export function EquipmentProfileDetail({ profile: p, exercises, navigateTo }: EquipmentProfileDetailProps) {
  const relevantExercises = exercises.filter(ex =>
    ex.equipment.length > 0 &&
    ex.equipment.every(eq => p.equipment.includes(eq))
  ).slice(0, 20)

  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">{p.name}</h2>
        <p className="text-xs text-muted-foreground font-mono mt-0.5">{p.id}</p>
      </div>

      {(p as { description?: string }).description && (
        <p className="text-sm text-muted-foreground">{(p as { description?: string }).description}</p>
      )}

      {/* Equipment list */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">
          Equipment ({p.equipment?.length ?? 0} items)
        </p>
        <div className="flex flex-wrap gap-1">
          {(p.equipment ?? []).map(eq => (
            <span key={eq} className="px-2 py-0.5 rounded text-xs bg-muted border border-border font-mono">
              {eq}
            </span>
          ))}
        </div>
      </div>

      {/* Compatible exercises */}
      {relevantExercises.length > 0 && (
        <div className="pt-2 border-t">
          <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">
            Compatible Exercises (first {relevantExercises.length})
          </p>
          <div className="flex flex-wrap gap-1">
            {relevantExercises.map(ex => (
              <CrossRefBadge key={ex.id} label={ex.name} type="exercises" id={ex.id} navigateTo={navigateTo} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
