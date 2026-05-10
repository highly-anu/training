import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Dumbbell, Wind, Footprints, Heart, Flame, Layers } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { ExerciseAnimation } from '@/api/types'

interface ExerciseAnimationPanelProps {
  animation?: ExerciseAnimation
  exerciseName: string
  category?: string
  className?: string
  variant?: 'drawer' | 'card' | 'row'
}

const CATEGORY_ICONS: Record<string, LucideIcon> = {
  barbell: Dumbbell,
  kettlebell: Dumbbell,
  aerobic: Wind,
  skill: Footprints,
  rehab: Heart,
  mobility: Flame,
}

export function ExerciseAnimationPanel({
  animation,
  exerciseName,
  category,
  className,
  variant = 'drawer',
}: ExerciseAnimationPanelProps) {
  const [imgError, setImgError] = useState(false)

  const isDrawer = variant === 'drawer'
  const isCard   = variant === 'card'

  const wrapperCn = cn(
    'relative overflow-hidden rounded-lg bg-muted',
    isDrawer && 'aspect-video w-full',
    isCard   && 'size-8 rounded-md',
    variant === 'row' && 'aspect-video w-full max-w-xs',
    className,
  )

  const showGif =
    animation?.type === 'gif' &&
    !!animation.gif_url &&
    !imgError

  const showLottie =
    animation?.type === 'lottie' &&
    !!animation.lottie_path

  const showSvg =
    animation?.type === 'svg_css' &&
    !!animation.svg_path

  // Placeholder icon when no animation or on error
  if (!showGif && !showLottie && !showSvg) {
    const Icon = (category && CATEGORY_ICONS[category]) ?? Layers
    return (
      <div className={cn(wrapperCn, 'flex items-center justify-center')}>
        <Icon className={cn('text-muted-foreground/30', isCard ? 'size-4' : 'size-8')} />
      </div>
    )
  }

  if (showGif) {
    return (
      <div className={wrapperCn}>
        <AnimatePresence>
          <motion.img
            key={animation!.gif_url}
            src={animation!.gif_url}
            alt={animation!.gif_alt ?? exerciseName}
            className="h-full w-full object-cover"
            loading="lazy"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.3 }}
            onError={() => setImgError(true)}
          />
        </AnimatePresence>
      </div>
    )
  }

  if (showLottie) {
    // Placeholder until @lottiefiles/dotlottie-react is installed and files exist.
    // To activate: npm install @lottiefiles/dotlottie-react
    //   import { DotLottieReact } from '@lottiefiles/dotlottie-react'
    //   return <div className={wrapperCn}><DotLottieReact src={animation!.lottie_path} loop autoplay /></div>
    return (
      <div className={cn(wrapperCn, 'flex items-center justify-center')}>
        <span className="text-[10px] text-muted-foreground text-center px-2">
          Animation coming soon
        </span>
      </div>
    )
  }

  if (showSvg) {
    return (
      <div className={cn(wrapperCn, 'flex items-center justify-center')}>
        <img
          src={animation!.svg_path}
          alt={exerciseName}
          className="h-full w-full object-contain animate-exercise"
        />
      </div>
    )
  }

  return null
}
