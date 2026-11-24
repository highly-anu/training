import { pointerWithin, rectIntersection, type CollisionDetection } from '@dnd-kit/core'

/**
 * Where a drag lands: the drop target under the pointer. dnd-kit's default
 * asks which target the dragged element's own box overlaps most, and a wide
 * card grabbed near one end then drops a column away from the cursor (found
 * dragging a session onto a week's days, 2026-11-24). A keyboard drag has no
 * pointer, so it falls back to the box, which the keyboard sensor moves onto
 * the target itself (`lib/dndKeyboard`).
 */
export const pointerFirst: CollisionDetection = (args) => {
  const under = pointerWithin(args)
  return under.length > 0 ? under : rectIntersection(args)
}
