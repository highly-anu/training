import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'

const CATEGORIES = [
  { id: '', label: 'All' },
  { id: 'barbell', label: 'Barbell' },
  { id: 'kettlebell', label: 'Kettlebell' },
  { id: 'bodyweight', label: 'Bodyweight' },
  { id: 'aerobic', label: 'Aerobic' },
  { id: 'loaded_carry', label: 'Carries' },
  { id: 'sandbag', label: 'Sandbag' },
  { id: 'mobility', label: 'Mobility' },
  { id: 'skill', label: 'Skill' },
  { id: 'rehab', label: 'Rehab' },
]

interface ExerciseFiltersProps {
  category: string
  onCategoryChange: (c: string) => void
}

export function ExerciseFilters({ category, onCategoryChange }: ExerciseFiltersProps) {
  return (
    <Tabs value={category || ''} onValueChange={onCategoryChange}>
      <TabsList className="h-8 flex-wrap gap-1 bg-muted/50">
        {CATEGORIES.map(({ id, label }) => (
          <TabsTrigger
            key={id}
            value={id}
            className="h-6 px-2.5 text-xs"
          >
            {label}
          </TabsTrigger>
        ))}
      </TabsList>
    </Tabs>
  )
}
