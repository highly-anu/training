export interface MovementColor {
  hex: string
  bg: string
  text: string
  border: string
  label: string
}

// By the analytics group a movement counts toward (src/analytics/movement.ROLLUPS),
// so the two pushes share orange the way two barbell lifts share red; a pattern
// outside every group is slate. Text shades are the -700/-800 light, -300 dark
// pair of §8.1. Web only: the phone has no Explore (docs/frontend-design.md §8.11).
export const MOVEMENT_GROUP_COLORS: Record<string, MovementColor> = {
  push:       { hex: '#f97316', bg: 'bg-orange-500/15',  text: 'text-orange-800 dark:text-orange-300',   border: 'border-orange-500/40',  label: 'Push' },
  pull:       { hex: '#3b82f6', bg: 'bg-blue-500/15',    text: 'text-blue-700 dark:text-blue-300',       border: 'border-blue-500/40',    label: 'Pull' },
  hinge:      { hex: '#eab308', bg: 'bg-yellow-500/15',  text: 'text-yellow-800 dark:text-yellow-300',   border: 'border-yellow-500/40',  label: 'Hinge' },
  squat:      { hex: '#10b981', bg: 'bg-emerald-500/15', text: 'text-emerald-800 dark:text-emerald-300', border: 'border-emerald-500/40', label: 'Squat' },
  carry:      { hex: '#d97706', bg: 'bg-amber-600/15',   text: 'text-amber-800 dark:text-amber-300',     border: 'border-amber-600/40',   label: 'Carry' },
  locomotion: { hex: '#0ea5e9', bg: 'bg-sky-500/15',     text: 'text-sky-700 dark:text-sky-300',         border: 'border-sky-500/40',     label: 'Locomotion' },
  rotation:   { hex: '#8b5cf6', bg: 'bg-violet-500/15',  text: 'text-violet-700 dark:text-violet-300',   border: 'border-violet-500/40',  label: 'Rotation' },
  isometric:  { hex: '#14b8a6', bg: 'bg-teal-500/15',    text: 'text-teal-800 dark:text-teal-300',       border: 'border-teal-500/40',    label: 'Isometric' },
  ballistic:  { hex: '#ef4444', bg: 'bg-red-500/15',     text: 'text-red-700 dark:text-red-300',         border: 'border-red-500/40',     label: 'Ballistic' },
  olympic:    { hex: '#ec4899', bg: 'bg-pink-500/15',    text: 'text-pink-800 dark:text-pink-300',       border: 'border-pink-500/40',    label: 'Olympic' },
}

export const MOVEMENT_OTHER_COLOR: MovementColor = {
  hex: '#94a3b8', bg: 'bg-slate-500/15', text: 'text-slate-700 dark:text-slate-300', border: 'border-slate-500/40', label: 'Other',
}

export function movementColor(rollup: string | null | undefined): MovementColor {
  return (rollup && MOVEMENT_GROUP_COLORS[rollup]) || MOVEMENT_OTHER_COLOR
}
