import type { ModalityId } from '@/api/types'

export interface ModalityColor {
  hex: string
  bg: string
  text: string
  border: string
  label: string
}

// Text shades are a PAIR pulling away from their own background: -700 for light
// mode (on a /15 tint over white), -300 for dark. Nothing lighter than -600
// clears WCAG AA 4.5:1 on the light end — these render at text-[10px]/text-xs.
// See docs/frontend-design.md §8.1. `hex` is mirrored into the iOS + watchOS
// ModalityStyle.swift files (§8.9) — changing it is a three-file commit.
export const MODALITY_COLORS: Record<ModalityId, ModalityColor> = {
  max_strength: {
    hex: '#ef4444',
    bg: 'bg-red-500/15',
    text: 'text-red-700 dark:text-red-300',
    border: 'border-red-500/40',
    label: 'Max Strength',
  },
  strength_endurance: {
    hex: '#f97316',
    bg: 'bg-orange-500/15',
    text: 'text-orange-800 dark:text-orange-300',
    border: 'border-orange-500/40',
    label: 'Strength Endurance',
  },
  relative_strength: {
    hex: '#f43f5e',
    bg: 'bg-rose-500/15',
    text: 'text-rose-800 dark:text-rose-300',
    border: 'border-rose-500/40',
    label: 'Relative Strength',
  },
  aerobic_base: {
    hex: '#0ea5e9',
    bg: 'bg-sky-500/15',
    text: 'text-sky-700 dark:text-sky-300',
    border: 'border-sky-500/40',
    label: 'Aerobic Base',
  },
  anaerobic_intervals: {
    hex: '#06b6d4',
    bg: 'bg-cyan-500/15',
    text: 'text-cyan-800 dark:text-cyan-300',
    border: 'border-cyan-500/40',
    label: 'Anaerobic Intervals',
  },
  mixed_modal_conditioning: {
    hex: '#8b5cf6',
    bg: 'bg-violet-500/15',
    text: 'text-violet-700 dark:text-violet-300',
    border: 'border-violet-500/40',
    label: 'Mixed Modal',
  },
  power: {
    hex: '#eab308',
    bg: 'bg-yellow-500/15',
    text: 'text-yellow-800 dark:text-yellow-300',
    border: 'border-yellow-500/40',
    label: 'Power',
  },
  mobility: {
    hex: '#10b981',
    bg: 'bg-emerald-500/15',
    text: 'text-emerald-800 dark:text-emerald-300',
    border: 'border-emerald-500/40',
    label: 'Mobility',
  },
  movement_skill: {
    hex: '#14b8a6',
    bg: 'bg-teal-500/15',
    text: 'text-teal-800 dark:text-teal-300',
    border: 'border-teal-500/40',
    label: 'Movement / Skill',
  },
  durability: {
    hex: '#f59e0b',
    bg: 'bg-amber-500/15',
    text: 'text-amber-800 dark:text-amber-300',
    border: 'border-amber-500/40',
    label: 'Durability',
  },
  combat_sport: {
    hex: '#ec4899',
    bg: 'bg-pink-500/15',
    text: 'text-pink-800 dark:text-pink-300',
    border: 'border-pink-500/40',
    label: 'Combat Sport',
  },
  rehab: {
    hex: '#84cc16',
    bg: 'bg-lime-500/15',
    text: 'text-lime-800 dark:text-lime-300',
    border: 'border-lime-500/40',
    label: 'Rehab',
  },
}
