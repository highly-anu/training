import { motion } from 'framer-motion'
import { useGoals } from '@/api/goals'
import { GoalCard } from './GoalCard'
import { LoadingGrid } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'

interface GoalGridProps {
  selectedIds: string[]
  onToggle: (id: string) => void
}

const containerVariants = {
  animate: { transition: { staggerChildren: 0.06 } },
}
const itemVariants = {
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.25 } },
}

export function GoalGrid({ selectedIds, onToggle }: GoalGridProps) {
  const { data: goals, isLoading, error } = useGoals()

  if (isLoading) return <LoadingGrid count={7} />
  if (error) return <ErrorBanner error={error as Error} title="Failed to load goals" />

  return (
    <motion.div
      variants={containerVariants}
      initial="initial"
      animate="animate"
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 items-stretch"
    >
      {goals?.map((goal) => (
        <motion.div key={goal.id} variants={itemVariants} className="h-full">
          <GoalCard
            goal={goal}
            selected={selectedIds.includes(goal.id)}
            onSelect={() => onToggle(goal.id)}
          />
        </motion.div>
      ))}
    </motion.div>
  )
}
