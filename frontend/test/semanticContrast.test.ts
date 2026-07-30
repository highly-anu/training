/**
 * Contrast regression guard for the semantic colour systems.
 *
 * Why this exists: the app is dark-first but `:root` holds the LIGHT palette, so
 * a bare `text-{c}-400` class is what light mode renders. For a long time every
 * semantic badge shipped `text-{c}-400 dark:text-{c}-300` — the `dark:` half
 * brightening an already-passing dark mode while light mode sat at ~2.3:1
 * against a 4.5:1 floor, at text-[10px]. Nothing caught it: it is invisible to
 * tsc, to the build, and to eslint, and it only shows in a theme most
 * development never opens.
 *
 * The test resolves classes against Tailwind's OWN palette (node_modules/
 * tailwindcss/theme.css) and the app's OWN theme tokens (src/styles/globals.css)
 * rather than a hardcoded table, so it stays correct if either changes.
 *
 * See docs/frontend-design.md §8 and docs/frontend-fix-plan.md FIX-1.
 */
import { describe, it, expect } from 'vitest'

import { MODALITY_COLORS } from '../src/lib/modalityColors'
import { PHASE_COLORS } from '../src/lib/phaseColors'
import { COMPLETION } from '../src/lib/completionColors'
import { STATUS_STYLES, STATUS_TEXT } from '../src/lib/statusColors'

import { AA_NORMAL, PALETTE, THEME_BG, parseText, ratioFor } from './contrastUtils'

// ── the cases ────────────────────────────────────────────────────────────────

interface Case { system: string; name: string; text: string; bg: string }

const CASES: Case[] = [
  ...Object.entries(MODALITY_COLORS).map(([name, c]) => ({
    system: 'modality', name, text: c.text, bg: c.bg,
  })),
  ...Object.entries(PHASE_COLORS).map(([name, c]) => ({
    system: 'phase', name, text: c.text, bg: c.bg,
  })),
  { system: 'completion', name: 'surface', text: COMPLETION.text, bg: COMPLETION.bg },
  { system: 'completion', name: 'interactive', text: COMPLETION.text, bg: COMPLETION.bgStrong },
  ...Object.entries(STATUS_STYLES).flatMap(([name, s]) => [
    // The badge string carries its own bg; the score sits directly on the card.
    { system: 'status-badge', name, text: s.badge, bg: s.badge },
    { system: 'status-score', name, text: s.score, bg: '' },
  ]),
  ...Object.entries(STATUS_TEXT).map(([name, text]) => ({
    system: 'status-text', name, text, bg: '',
  })),
]

const THEMES = Object.keys(THEME_BG)

describe('semantic colour contrast', () => {
  it('sources the real Tailwind palette', () => {
    // Guards against the regex silently matching nothing and every test passing.
    expect(Object.keys(PALETTE).length).toBeGreaterThan(200)
    expect(PALETTE['emerald-700']).toBeDefined()
  })

  it('sources every theme background', () => {
    expect(THEMES).toEqual(['light', 'dark', 'military', 'zen'])
  })

  it.each(CASES)('$system/$name clears AA in every theme', (c) => {
    for (const theme of THEMES) {
      const ratio = ratioFor(theme, c.text, c.bg)
      expect(
        ratio,
        `${c.system}/${c.name} in "${theme}": ${ratio.toFixed(2)}:1 (need ${AA_NORMAL}:1)\n` +
        `  text: ${c.text}\n  bg:   ${c.bg || '(theme background)'}`,
      ).toBeGreaterThanOrEqual(AA_NORMAL)
    }
  })
})

describe('semantic colour pairing', () => {
  // The bug was structural, not just numeric: a single mid-shade cannot serve
  // both themes. Every semantic text class must therefore declare both halves.
  const paired: Case[] = CASES.filter((c) => c.system !== 'status-badge')

  it.each(paired)('$system/$name declares both a light and a dark shade', (c) => {
    const { light, dark } = parseText(c.text)
    expect(light, `no bare text-* shade in "${c.text}"`).toBeTruthy()
    expect(dark, `no dark:text-* shade in "${c.text}"`).toBeTruthy()
  })
})
