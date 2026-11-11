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
      // Recharts takes its easing by name; chartMotion is where it is said.
      allow: either(GENERATED, is('lib/chartMotion.ts')),
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

describe('three states before content (§11)', () => {
  it('one spinner, and only beside the words of an action', () => {
    expect(findings({
      pattern: /animate-spin/,
      allow: is('components/ui/spinner.tsx'),
    }), 'A screen that is loading shows <LoadingState>; a running action <Spinner> or <Working> (ui/spinner).').toEqual([])
  })

  it('one skeleton', () => {
    expect(findings({
      pattern: /animate-pulse/,
      // The block in force on the Blocks timeline pulses; it is not a placeholder.
      allow: is('components/ui/skeleton.tsx', 'components/analytics/DevelopmentTab.tsx'),
    }), 'A placeholder is <Skeleton> (ui/skeleton), usually through <LoadingState>.').toEqual([])
  })

  it('no "Loading…" standing in for a screen', () => {
    expect(findings({
      pattern: /Loading[^'"`<{]*(…|\.\.\.)/,
      allow: is('components/shared/states/LoadingState.tsx'),
    }), 'Draw the shape of what is coming: <LoadingState shape=…>.').toEqual([])
  })

  it('the old loading looks stay gone', () => {
    expect(findings({
      pattern: /\b(LoadingCard|DumbbellLoader)\b/,
      allow: () => false,
    }), 'Use <LoadingState> (components/shared/states).').toEqual([])
  })

  it('an error is shown by FailedState or ErrorBanner, never as its bare message', () => {
    expect(findings({
      pattern: /\{\(?\(?\w*(error|Error)\b[^}]*\)\.message\}/,
      allow: under('components/shared/', 'components/devlab/', 'pages/DevLab'),
    }), 'Nothing loaded: <FailedState onRetry>. A reload failed with content on screen: <ErrorBanner onRetry>.').toEqual([])
  })

  it('a dashed box means absent or optional, and no new file draws one', () => {
    // Empty is <EmptyState>. The others are a rest day, an unfilled slot, a
    // drop target, an integration not configured — never a list with nothing in it.
    const DASHED = [
      'components/shared/EmptyState.tsx',
      'components/analytics/CoverageNotice.tsx',
      'components/bio/StravaConnect.tsx',
      'components/builder/GuidedScheduler.tsx',
      'components/builder/LanePicker.tsx',
      'components/dashboard/TodaySession.tsx',
      'components/devlab/heatmap/HeatmapPanel.tsx',
      'components/explore/LineageSection.tsx',
      'components/explore/philosophy/Glance.tsx',
      'components/explore/philosophy/PhaseWeek.tsx',
      'components/log/LinkingTab.tsx',
      'components/program/DayColumn.tsx',
      'components/program/PhaseChanges.tsx',
      'components/program/SessionCard.tsx',
      'components/session/SessionPanel.tsx',
      'components/session/WorkoutSummaryCard.tsx',
      'components/settings/ConnectionsSettings.tsx',
      'pages/Log.tsx',
      'pages/ProgramHistoryDetail.tsx',
    ]
    expect(findings({
      pattern: /border-dashed/,
      allow: is(...DASHED),
    }), 'An empty list or page is <EmptyState>, with the way forward.').toEqual([])
  })
})

describe('every action answers (§11.5–11.6)', () => {
  it('a pending button keeps its label', () => {
    expect(findings({
      pattern: /(isPending|[lL]oading|busy|[sS]aving|[sS]ubmitting|[gG]enerating|[sS]yncing)\s*\?\s*['"`][A-Z][^'"`]*(…|\.\.\.)['"`]/,
      allow: () => false,
    }), 'Use <Button loading={…}>: the spinner takes the icon, the label stays.').toEqual([])
  })

  it('the toast has one door', () => {
    expect(findings({
      pattern: /from 'sonner'/,
      allow: is('lib/toast.ts', 'components/shared/Toaster.tsx'),
    }), 'Use toast.undo / toast.failed from lib/toast — and only where the answer has left the screen.').toEqual([])
  })

  it('nothing asks through the browser', () => {
    expect(findings({
      pattern: /\b(window\.)?(confirm|alert|prompt)\((['"`]|$)/,
      allow: () => false,
    }), 'A removal offers toast.undo; what cannot be undone asks through <ConfirmDialog>.').toEqual([])
  })
})

describe('what changed, and where it came from (§11.9, §12.1, §13.1, §17)', () => {
  it('no component writes its own enter, exit or press', () => {
    expect(findings({
      pattern: /\b(initial|animate|exit|whileHover|whileTap)=\{\{/,
      // The ontology graph animates to computed positions: data, not a preset.
      allow: either(under('components/motion/', 'components/layout/', 'components/devlab/heatmap/'), is('lib/motion.ts')),
    }), 'Spread a preset from @/lib/motion (riseIn, collapseMotion, pressMotion…) or use components/motion.').toEqual([])
  })

  it('every chart draws through useChartEntry', () => {
    expect(findings({
      pattern: /\b(isAnimationActive|animationDuration|animationBegin|animationEasing)\b/,
      allow: is('lib/chartMotion.ts'),
    }), 'Spread useChartEntry() on the series: one timing, off under Reduce Motion.').toEqual([])
    const series = /<(Line|Bar|Area|Pie)\s(?!\{\.\.\.drawIn\})/
    expect(findings({ pattern: series, allow: () => false, only: (f) => f.endsWith('.tsx') }),
      'A Recharts series starts `<Line {...drawIn}` with `const drawIn = useChartEntry()`.').toEqual([])
  })

  it('a page header is <PageHeader>, its sections <SubTabs>', () => {
    expect(findings({
      pattern: /border-b px-6 py-4/,
      allow: is('components/layout/PageHeader.tsx'),
    }), 'Use <PageHeader icon title tabs actions>.').toEqual([])
    expect(findings({
      pattern: /role="tab(list)?"/,
      allow: is('components/layout/SubTabs.tsx'),
    }), 'Use <SubTabs>: arrow keys, the sliding pill and the 44 px touch target come with it.').toEqual([])
    expect(findings({
      pattern: /function TabSelector\b/,
      allow: () => false,
    }), 'Use <SubTabs>.').toEqual([])
  })

  it('the navigation drawer starts closed', () => {
    const store = FILES.find(({ file }) => file === 'store/uiStore.ts')!.lines.join('\n')
    expect(store).toMatch(/mobileNavOpen: false/)
    // Persisted, it would open over the page on the next visit.
    expect(store).toMatch(/partialize: \(s\) => \(\{ selectedWeekIndex: s\.selectedWeekIndex \}\)/)
  })
})
