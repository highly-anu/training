import type { TrainingPhase } from '@/api/types'

export interface PhaseColor {
  hex: string
  bg: string
  text: string
  label: string
}

// Text shades are a PAIR pulling away from their own background: -700 for light
// mode (on a /15 tint over white), -300 for dark. Nothing lighter than -600
// clears WCAG AA 4.5:1 on the light end — these render at text-[10px]/text-xs.
// See docs/frontend-design.md §8.1–8.2. `hex` is mirrored into the iOS + watchOS
// ModalityStyle.swift files (§8.9) — changing it is a three-file commit.
export const PHASE_COLORS: Record<TrainingPhase, PhaseColor> = {
  base: { hex: '#0ea5e9', bg: 'bg-sky-500/15', text: 'text-sky-700 dark:text-sky-300', label: 'Base' },
  build: { hex: '#f59e0b', bg: 'bg-amber-500/15', text: 'text-amber-700 dark:text-amber-300', label: 'Build' },
  peak: { hex: '#ef4444', bg: 'bg-red-500/15', text: 'text-red-700 dark:text-red-300', label: 'Peak' },
  taper: { hex: '#22c55e', bg: 'bg-green-500/15', text: 'text-green-700 dark:text-green-300', label: 'Taper' },
  deload: { hex: '#94a3b8', bg: 'bg-slate-500/15', text: 'text-slate-700 dark:text-slate-300', label: 'Deload' },
  maintenance: { hex: '#a1a1aa', bg: 'bg-zinc-500/15', text: 'text-zinc-700 dark:text-zinc-300', label: 'Maintenance' },
  rehab: { hex: '#84cc16', bg: 'bg-lime-500/15', text: 'text-lime-700 dark:text-lime-300', label: 'Rehab' },
  post_op: { hex: '#a855f7', bg: 'bg-purple-500/15', text: 'text-purple-700 dark:text-purple-300', label: 'Post-Op' },
  active: { hex: '#94a3b8', bg: 'bg-slate-500/15', text: 'text-slate-700 dark:text-slate-300', label: 'Active' },
  transition: { hex: '#8b5cf6', bg: 'bg-violet-500/15', text: 'text-violet-700 dark:text-violet-300', label: 'Transition' },
  specific: { hex: '#f97316', bg: 'bg-orange-500/15', text: 'text-orange-700 dark:text-orange-300', label: 'Specific' },
}
