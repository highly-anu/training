import { motion, type HTMLMotionProps } from 'framer-motion'
import { fadeMotion, pageMotion } from '@/lib/motion'

interface PageProps extends Omit<HTMLMotionProps<'div'>, 'initial' | 'animate' | 'exit' | 'transition'> {
  /** `rise` for a page with content; `fade` for a screen that is only waiting. */
  enter?: 'rise' | 'fade'
}

/**
 * The root of every routed page: it carries the page transition, so a page
 * never writes its own (docs/frontend-design.md §11.1). `RootLayout` keys the
 * outlet by path, which is what lets the exit run before the next page enters.
 */
export function Page({ enter = 'rise', ...props }: PageProps) {
  return <motion.div {...(enter === 'fade' ? fadeMotion : pageMotion)} {...props} />
}
