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
import { MOVEMENT_GROUP_COLORS, MOVEMENT_OTHER_COLOR } from '../src/lib/movementColors'

import {
  AA_NORMAL, PALETTE, THEME_BG, contrast, hueDistance, over, parseText, ratioFor, themeToken, toRgb,
} from './contrastUtils'

// ── the cases ────────────────────────────────────────────────────────────────

interface Case { system: string; name: string; text: string; bg: string }

const CASES: Case[] = [
  ...Object.entries(MODALITY_COLORS).map(([name, c]) => ({
    system: 'modality', name, text: c.text, bg: c.bg,
  })),
  ...Object.entries(PHASE_COLORS).map(([name, c]) => ({
    system: 'phase', name, text: c.text, bg: c.bg,
  })),
  // Explore ▸ Movements: on its tint, and as a group label straight on the page.
  ...Object.entries({ ...MOVEMENT_GROUP_COLORS, other: MOVEMENT_OTHER_COLOR }).flatMap(([name, c]) => [
    { system: 'movement', name, text: c.text, bg: c.bg },
    { system: 'movement-label', name, text: c.text, bg: '' },
  ]),
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
  const paired: Case[] = CASES

  it.each(paired)('$system/$name declares both a light and a dark shade', (c) => {
    const { light, dark } = parseText(c.text)
    expect(light, `no bare text-* shade in "${c.text}"`).toBeTruthy()
    expect(dark, `no dark:text-* shade in "${c.text}"`).toBeTruthy()
  })
})

/**
 * "Do this" and "done" are two colours in every theme (docs/frontend-design.md
 * §1.7). Military's olive and Zen's sage primaries once sat 33° and 10° of hue
 * from emerald, so a primary button read as a finished one. A new theme, or a
 * retuned one, has to keep them apart to pass.
 */
describe('action and done', () => {
  const MIN_HUE_APART = 55

  it.each(THEMES)('%s keeps the action colour apart from done', (theme) => {
    const action = themeToken(theme, 'action')
    const done = themeToken(theme, 'done')
    const apart = hueDistance(action, done)
    expect(apart, `${theme}: --action and --done are ${apart.toFixed(0)}° of hue apart`).toBeGreaterThanOrEqual(MIN_HUE_APART)
  })

  it.each(THEMES)('%s: text on the action and done fills clears AA', (theme) => {
    for (const [fill, text] of [['action', 'action-foreground'], ['done', 'done-foreground'], ['destructive', 'destructive-foreground']]) {
      const ratio = contrast(toRgb(themeToken(theme, text)), toRgb(themeToken(theme, fill)))
      expect(ratio, `${theme}: --${text} on --${fill} is ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(AA_NORMAL)
    }
  })

  it.each(THEMES)('%s: done reads on the page', (theme) => {
    // As a check, a stripe or a dot: 3:1, WCAG's non-text floor. The action
    // colour is not held to it: Light's amber is the brand's and is 2.2:1 on
    // white, which is why an action is a filled button with dark text, never
    // amber text on the page.
    const ratio = contrast(toRgb(themeToken(theme, 'done')), THEME_BG[theme])
    expect(ratio, `${theme}: --done on the background is ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(3)
  })
})

/**
 * Done and the three verdicts are tokens, each theme's own (docs/frontend-design.md
 * §8.12). They are written as text — `text-done`, `text-good` — on the page, on
 * a card and on their own tint, so each has to clear AA in all three places in
 * every theme. A retuned theme that dims one fails here, not in a screenshot.
 */
describe('done and the verdicts as text', () => {
  const TOKENS = ['done', 'good', 'warn', 'bad']
  const TINTS = [0.05, 0.1, 0.15]

  it.each(THEMES.flatMap((theme) => TOKENS.map((token) => ({ theme, token }))))(
    '$theme: --$token reads on the page, a card and its own tint',
    ({ theme, token }) => {
      const fg = toRgb(themeToken(theme, token))
      for (const surface of ['background', 'card']) {
        const bg = toRgb(themeToken(theme, surface))
        const plain = contrast(fg, bg)
        expect(plain, `${theme}: --${token} on --${surface} is ${plain.toFixed(2)}:1`).toBeGreaterThanOrEqual(AA_NORMAL)
        for (const alpha of TINTS) {
          const tinted = contrast(fg, over(fg, alpha, bg))
          expect(tinted, `${theme}: --${token} on its /${alpha * 100} tint over --${surface} is ${tinted.toFixed(2)}:1`)
            .toBeGreaterThanOrEqual(AA_NORMAL)
        }
      }
    },
  )
})
