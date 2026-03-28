import { useState } from 'react'
import { motion } from 'framer-motion'
import { useExercises } from '@/api/exercises'
import { useDebounce } from '@/hooks/useDebounce'
import { ExerciseSearch } from '@/components/exercises/ExerciseSearch'
import { ExerciseFilters } from '@/components/exercises/ExerciseFilters'
import { ExerciseCard } from '@/components/exercises/ExerciseCard'
import { ExerciseDrawer } from '@/components/exercises/ExerciseDrawer'
import { LoadingGrid } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { EmptyState } from '@/components/shared/EmptyState'
import type { Exercise, ExerciseFilters as Filters } from '@/api/types'

const containerVariants = {
  animate: { transition: { staggerChildren: 0.03 } },
}
const itemVariants = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.2 } },
}

export function ExerciseCatalog() {
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('')
  const [selectedExercise, setSelectedExercise] = useState<Exercise | null>(null)

  const debouncedSearch = useDebounce(search, 250)

  const filters: Filters = {
    search: debouncedSearch || undefined,
    category: category || undefined,
  }

  const { data: exercises, isLoading, error } = useExercises(filters)
  const { data: allExercises } = useExercises()

  function handleNavigateExercise(id: string) {
    const ex = allExercises?.find((e) => e.id === id)
    if (ex) setSelectedExercise(ex)
  }

  return (
    <motion.div
      key="exercises"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="border-b bg-card/50 px-6 py-4 space-y-3">
        <div>
          <h1 className="text-xl font-bold tracking-tight">Exercises</h1>
          <p className="text-sm text-muted-foreground">
            {exercises ? `${exercises.length} exercises` : 'Browse the full exercise library'}
          </p>
        </div>
        <ExerciseSearch value={search} onChange={setSearch} />
        <ExerciseFilters category={category} onCategoryChange={setCategory} />
      </div>

      {/* Grid */}
      <div className="flex-1 overflow-y-auto p-6">
        {isLoading ? (
          <LoadingGrid count={9} />
        ) : error ? (
          <ErrorBanner error={error as Error} />
        ) : !exercises?.length ? (
          <EmptyState
            title="No exercises found"
            description="Try adjusting your search or filters."
            action={{ label: 'Clear filters', onClick: () => { setSearch(''); setCategory('') } }}
          />
        ) : (
          <motion.div
            variants={containerVariants}
            initial="initial"
            animate="animate"
            className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
          >
            {exercises.map((exercise) => (
              <motion.div key={exercise.id} variants={itemVariants}>
                <ExerciseCard
                  exercise={exercise}
                  onClick={() => setSelectedExercise(exercise)}
                />
              </motion.div>
            ))}
          </motion.div>
        )}
      </div>

      {/* Detail drawer */}
      <ExerciseDrawer
        exercise={selectedExercise}
        allExercises={allExercises ?? []}
        open={!!selectedExercise}
        onClose={() => setSelectedExercise(null)}
        onNavigate={handleNavigateExercise}
      />
    </motion.div>
  )
}
