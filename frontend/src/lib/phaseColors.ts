import type { TrainingPhase } from '@/api/types'

export interface PhaseColor {
  hex: string
  bg: string
  text: string
  label: string
}

export const PHASE_COLORS: Record<TrainingPhase, PhaseColor> = {
  base: { hex: '#0ea5e9', bg: 'bg-sky-500/15', text: 'text-sky-400 dark:text-sky-300', label: 'Base' },
  build: { hex: '#f59e0b', bg: 'bg-amber-500/15', text: 'text-amber-500 dark:text-amber-300', label: 'Build' },
  peak: { hex: '#ef4444', bg: 'bg-red-500/15', text: 'text-red-400 dark:text-red-300', label: 'Peak' },
  taper: { hex: '#22c55e', bg: 'bg-green-500/15', text: 'text-green-400 dark:text-green-300', label: 'Taper' },
  deload: { hex: '#94a3b8', bg: 'bg-slate-500/15', text: 'text-slate-400 dark:text-slate-300', label: 'Deload' },
  maintenance: { hex: '#a1a1aa', bg: 'bg-zinc-500/15', text: 'text-zinc-400 dark:text-zinc-300', label: 'Maintenance' },
  rehab: { hex: '#84cc16', bg: 'bg-lime-500/15', text: 'text-lime-400 dark:text-lime-300', label: 'Rehab' },
  post_op: { hex: '#a855f7', bg: 'bg-purple-500/15', text: 'text-purple-400 dark:text-purple-300', label: 'Post-Op' },
  active: { hex: '#94a3b8', bg: 'bg-slate-500/15', text: 'text-slate-400 dark:text-slate-300', label: 'Active' },
  transition: { hex: '#8b5cf6', bg: 'bg-violet-500/15', text: 'text-violet-400 dark:text-violet-300', label: 'Transition' },
  specific: { hex: '#f97316', bg: 'bg-orange-500/15', text: 'text-orange-400 dark:text-orange-300', label: 'Specific' },
}
