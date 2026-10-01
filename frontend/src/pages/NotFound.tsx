import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Compass } from 'lucide-react'
import { EmptyState } from '@/components/shared/EmptyState'

export function NotFound() {
  const navigate = useNavigate()
  return (
    <motion.div
      key="not-found"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full items-center justify-center p-6"
    >
      <EmptyState
        title="Page not found"
        description="Nothing lives at this address. Old links to the builder, imports and the bio log redirect; anything else lands here."
        action={{ label: 'Go home', onClick: () => navigate('/') }}
        icon={<Compass className="size-10" />}
        className="max-w-md"
      />
    </motion.div>
  )
}
