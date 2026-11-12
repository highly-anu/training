/**
 * The design rules, read from the sources (docs/frontend-design.md §1.8).
 *
 * Each rule in that table names the module that carries it and the check that
 * holds it; the checks that can be made by reading the code are here, the way
 * `DesignTokenTests` holds the phone's (ios/docs/design-system.md §1.8). A rule
 * lands with its conversions, so there is no baseline: a finding is a file
 * that wrote by hand what a shared module already provides. The message says
 * which module.
 *
 * Nothing here renders: it is invisible to tsc and eslint that a card settles
 * in 180 ms where every other card takes 250, and that is how ten durations
 * came to be typed in thirty-one files.
 */
import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join, relative, resolve } from 'node:path'

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '../src')

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return walk(path)
    return /\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : []
  })
}

const FILES = walk(SRC).map((path) => ({
  file: relative(SRC, path).replaceAll('\\', '/'),
  lines: readFileSync(path, 'utf8').split('\n'),
}))

interface Rule {
  /** What was written by hand. */
  pattern: RegExp
  /** Files that own the rule, or where the words mean something else. */
  allow: (file: string) => boolean
  /** Only these files, when the rule is about one folder. */
  only?: (file: string) => boolean
}

function findings({ pattern, allow, only }: Rule): string[] {
  return FILES
    .filter(({ file }) => !allow(file) && (only?.(file) ?? true))
    .flatMap(({ file, lines }) =>
      lines.flatMap((line, i) => (pattern.test(line) ? [`${file}:${i + 1}  ${line.trim()}`] : [])))
}

const is = (...files: string[]) => (file: string) => files.includes(file)
const under = (...dirs: string[]) => (file: string) => dirs.some((d) => file.startsWith(d))
const either = (...fns: ((file: string) => boolean)[]) => (file: string) => fns.some((fn) => fn(file))

/** Generated tables: `transition` is a modality id there. */
const GENERATED = under('lib/gen/')

describe('the sources the rules read', () => {
  it('finds the app', () => {
    // A moved folder or a broken walk would let every rule pass on nothing.
    expect(FILES.length).toBeGreaterThan(150)
    expect(FILES.some(({ file }) => file === 'lib/motion.ts')).toBe(true)
    expect(FILES.some(({ file }) => file === 'components/layout/Page.tsx')).toBe(true)
  })
})

describe('motion is written once (§11)', () => {
  it('no framer transition outside lib/motion.ts', () => {
    expect(findings({
      // `transition={{ … }}`, a `transition: { … }` inside animate/exit/variants,
      // and the keys only a transition has.
      pattern: /transition=\{\{|\btransition:\s*\{|\b(stiffness|damping|staggerChildren|delayChildren|bounce):\s/,
      allow: either(is('lib/motion.ts'), GENERATED),
    }), 'Take a preset from @/lib/motion (springStandard, crossfade, riseIn…); add one there if none fits.').toEqual([])
  })

  it('no duration or easing typed in an animation', () => {
    expect(findings({
      pattern: /\b(duration|ease):\s*['"\d[]/,
      allow: either(
        is('lib/motion.ts'),
        GENERATED,
        // A session's minutes, and a map camera told not to fly.
        is('lib/workoutMatcher.ts', 'components/workout/Swiss3DMap.tsx'),
      ),
    }), 'A duration or easing belongs to a preset in @/lib/motion.').toEqual([])
  })

  it('no duration, delay or easing class outside the tokens', () => {
    expect(findings({
      // `duration-200`, `delay-150`, `ease-in-out`. The tokens are written
      // `duration-(--motion-base)` and `ease-standard`, which do not match.
      pattern: /(?<![\w-])(duration|delay)-\d|(?<![\w-])ease-(in|out|in-out|linear)(?![\w-])/,
      allow: GENERATED,
    }), 'Use duration-(--motion-fast|base|slow) and ease-standard | ease-exit (styles/globals.css).').toEqual([])
  })

  it('a page takes its transition from <Page>', () => {
    expect(findings({
      pattern: /<motion\.div[^>]*\b(initial|exit)=|^\s*(initial|exit)=\{\{ opacity: 0, y: (16|-8)/,
      only: under('pages/'),
      allow: () => false,
    }), 'The root of a routed page is <Page> (components/layout/Page.tsx).').toEqual([])
  })
})
