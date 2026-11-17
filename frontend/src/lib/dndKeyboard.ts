/**
 * Drag and drop by keyboard (docs/frontend-design.md §11.10): Space or Enter
 * on a handle picks the item up, an arrow key moves it to the nearest drop
 * target that way, Space drops, Escape puts it back.
 *
 * dnd-kit's own keyboard sensor moves 25 px a press, which is right for a
 * free canvas and useless between seven day columns; this getter jumps from
 * target to target.
 */
import { KeyboardCode, type KeyboardCoordinateGetter } from '@dnd-kit/core'

export interface Box {
  left: number
  top: number
  width: number
  height: number
}

export type Direction = 'left' | 'right' | 'up' | 'down'

const centre = (box: Box) => ({ x: box.left + box.width / 2, y: box.top + box.height / 2 })

/**
 * The drop target to move to: of the targets whose centre lies `direction` of
 * `from`'s centre, the nearest — distance along the arrow, with the sideways
 * offset counted double so a column beside wins over one diagonally away.
 * `undefined` at the edge: the item stays where it is.
 */
export function nextDropTarget<T extends Box>(from: Box, targets: readonly T[], direction: Direction): T | undefined {
  const origin = centre(from)
  let best: T | undefined
  let bestScore = Infinity
  for (const target of targets) {
    const c = centre(target)
    const dx = c.x - origin.x
    const dy = c.y - origin.y
    const along = direction === 'left' ? -dx : direction === 'right' ? dx : direction === 'up' ? -dy : dy
    if (along < 1) continue
    const across = Math.abs(direction === 'left' || direction === 'right' ? dy : dx)
    const score = along + 2 * across
    if (score < bestScore) {
      best = target
      bestScore = score
    }
  }
  return best
}

const DIRECTIONS: Partial<Record<string, Direction>> = {
  [KeyboardCode.Left]: 'left',
  [KeyboardCode.Right]: 'right',
  [KeyboardCode.Up]: 'up',
  [KeyboardCode.Down]: 'down',
}

/** `useSensor(KeyboardSensor, { coordinateGetter: dropTargetCoordinates })`. */
export const dropTargetCoordinates: KeyboardCoordinateGetter = (event, { context }) => {
  const direction = DIRECTIONS[event.code]
  const { collisionRect, droppableRects, droppableContainers } = context
  if (!direction || !collisionRect) return undefined
  event.preventDefault()
  const targets = droppableContainers
    .getEnabled()
    .map((container) => droppableRects.get(container.id))
    .filter((rect): rect is NonNullable<typeof rect> => rect != null)
  const target = nextDropTarget(collisionRect, targets, direction)
  if (!target) return undefined
  // The dragged item, centred on the target.
  return {
    x: target.left + (target.width - collisionRect.width) / 2,
    y: target.top + (target.height - collisionRect.height) / 2,
  }
}
