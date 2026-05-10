import { useRef } from 'react'
import type { MuscleDiagram } from '@/api/types'

interface MuscleHighlightDiagramProps {
  diagram: MuscleDiagram
  className?: string
}

// Maps muscle names from exercise_media.yaml to SVG element IDs in muscle_body.svg
const MUSCLE_ID_MAP: Record<string, string> = {
  // Primary
  quadriceps:       'quad_left,quad_right',
  quad:             'quad_left,quad_right',
  glutes:           'adductor',
  glute_max:        'adductor',
  hamstrings:       'quad_left,quad_right',  // SVG only has front view; hamstrings reuse leg shapes
  adductors:        'adductor',
  adductor:         'adductor',
  calves:           'calf_left,calf_right',
  calf:             'calf_left,calf_right',
  core:             'core,lower_abs',
  abs:              'core,lower_abs',
  lower_abs:        'lower_abs',
  pectorals:        'pec',
  pec:              'pec',
  chest:            'pec',
  deltoids:         'delt_left,delt_right',
  delt:             'delt_left,delt_right',
  delts:            'delt_left,delt_right',
  anterior_delt:    'delt_left,delt_right',
  shoulders:        'delt_left,delt_right',
  biceps:           'bicep_left,bicep_right',
  bicep:            'bicep_left,bicep_right',
  triceps:          'bicep_left,bicep_right',
  forearms:         'forearm_left,forearm_right',
  forearm:          'forearm_left,forearm_right',
  erector_spinae:   'core',
  erector:          'core',
  lats:             'pec',
  upper_back:       'pec',
  traps:            'delt_left,delt_right',
  hip_flexors:      'adductor',
  hip_flexor:       'adductor',
  knees:            'knee_left,knee_right',
}

export function MuscleHighlightDiagram({ diagram, className }: MuscleHighlightDiagramProps) {
  const ref = useRef<HTMLObjectElement>(null)

  const applyHighlights = () => {
    const obj = ref.current
    if (!obj) return
    const doc = (obj as HTMLObjectElement & { contentDocument: Document | null }).contentDocument
    if (!doc) return

    const resolveToIds = (muscles: string[]): string[] =>
      muscles.flatMap((m) =>
        (MUSCLE_ID_MAP[m.toLowerCase()] ?? m).split(',').map((s) => s.trim())
      )

    const primaryIds  = new Set(resolveToIds(diagram.highlight_primary))
    const secondaryIds = new Set(resolveToIds(diagram.highlight_secondary))

    doc.querySelectorAll('[id]').forEach((el) => {
      const id = el.id
      if (primaryIds.has(id)) {
        ;(el as SVGElement).style.fill = 'hsl(var(--primary))'
        ;(el as SVGElement).style.opacity = '0.75'
      } else if (secondaryIds.has(id)) {
        ;(el as SVGElement).style.fill = 'hsl(var(--primary))'
        ;(el as SVGElement).style.opacity = '0.3'
      }
    })
  }

  return (
    <div className={className}>
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">Muscles</p>
      <div className="flex gap-4 items-start">
        <object
          ref={ref}
          data="/icons/muscle_body.svg"
          type="image/svg+xml"
          className="h-40 w-auto"
          onLoad={applyHighlights}
          aria-label="Muscle diagram"
        />
        <div className="text-xs space-y-2 pt-1">
          {diagram.highlight_primary.length > 0 && (
            <div>
              <p className="text-[10px] font-semibold text-muted-foreground uppercase mb-1">Primary</p>
              <div className="flex flex-wrap gap-1">
                {diagram.highlight_primary.map((m) => (
                  <span key={m} className="px-2 py-0.5 rounded-full bg-primary/15 text-primary text-[10px] font-medium capitalize">
                    {m.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}
          {diagram.highlight_secondary.length > 0 && (
            <div>
              <p className="text-[10px] font-semibold text-muted-foreground uppercase mb-1">Secondary</p>
              <div className="flex flex-wrap gap-1">
                {diagram.highlight_secondary.map((m) => (
                  <span key={m} className="px-2 py-0.5 rounded-full bg-muted text-muted-foreground text-[10px] capitalize">
                    {m.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
