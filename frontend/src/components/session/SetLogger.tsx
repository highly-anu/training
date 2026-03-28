import { useState } from 'react'
import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'

interface SetLoggerProps {
  sets: number
  exerciseId: string
  sessionKey: string
}

export function SetLogger({ sets, exerciseId, sessionKey }: SetLoggerProps) {
  const storeKey = `${sessionKey}-${exerciseId}`
  const stored = useProfileStore((s) => s.sessionLogs[storeKey])
  const setSessionLog = useProfileStore((s) => s.setSessionLog)
  const [completed, setCompleted] = useState<boolean[]>(
    stored ?? Array(sets).fill(false)
  )

  function toggle(i: number) {
    setCompleted((prev) => {
      const next = [...prev]
      next[i] = !next[i]
      setSessionLog(storeKey, next)
      return next
    })
  }

  const doneCount = completed.filter(Boolean).length

  return (
    <div className="flex items-center gap-1.5">
      {completed.map((done, i) => (
        <motion.button
          key={`${exerciseId}-set-${i}`}
          whileTap={{ scale: 1.3 }}
          onClick={() => toggle(i)}
          animate={{ backgroundColor: done ? 'var(--color-primary)' : undefined }}
          transition={{ duration: 0.15 }}
          className={cn(
            'size-6 rounded-md border transition-colors text-[10px] font-bold',
            done
              ? 'border-primary bg-primary text-primary-foreground'
              : 'border-border bg-muted text-muted-foreground hover:border-primary/60'
          )}
          aria-label={`Set ${i + 1} ${done ? 'completed' : 'pending'}`}
        >
          {i + 1}
        </motion.button>
      ))}
      <span className="ml-1 text-xs text-muted-foreground">
        {doneCount}/{sets}
      </span>
    </div>
  )
}
