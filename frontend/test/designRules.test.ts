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

/** Dev Lab is a workbench for one developer; the shared components reach it, the page rules do not. */
const DEV_LAB = either(under('components/devlab/'), is('pages/DevLab.tsx'))

/**
 * Opening tags, whole — a tag's attributes run over many lines, which the
 * line rules cannot see. `{…}` is followed three levels deep, as far as a
 * handler written in place goes.
 */
const TAG = /<([A-Za-z][\w.]*)\b((?:[^<>{}]|\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}|=>)*?)\/?>/g

function tagFindings(
  breach: (tag: string, attrs: string) => boolean,
  allow: (file: string) => boolean = () => false,
): string[] {
  return FILES
    .filter(({ file }) => file.endsWith('.tsx') && !allow(file))
    .flatMap(({ file, lines }) => {
      const source = lines.join('\n')
      return [...source.matchAll(TAG)]
        .filter((m) => breach(m[1], m[2]))
        .map((m) => `${file}:${source.slice(0, m.index).split('\n').length}  <${m[1]}>`)
    })
}

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

describe('nothing behind hover (§11.10)', () => {
  const PLAIN = new Set(['div', 'span', 'li', 'tr', 'td', 'p', 'section', 'article', 'Card'])

  it('what can be clicked is a button or a link', () => {
    // `onClick={(e) => e.stopPropagation()}` is a wall, not an action.
    const wall = /onClick=\{\(?\w+\)?\s*=>\s*\w+\.stopPropagation\(\)\}/
    expect(tagFindings(
      (tag, attrs) => PLAIN.has(tag) && /\bonClick=/.test(attrs) && !wall.test(attrs),
      DEV_LAB,
    ), 'Make it a <button> (or a link). A card with controls inside takes one stretched button under its content — WeekOverview\'s SessionCard, WorkoutRow.').toEqual([])
    expect(tagFindings((tag, attrs) => PLAIN.has(tag) && /role="button"/.test(attrs), DEV_LAB),
      'A <button> is focusable, answers Space and Enter, and is announced; a div with a role is none of those by itself.').toEqual([])
  })

  it('no control waits for a hover', () => {
    expect(findings({
      pattern: /(opacity-0|invisible)\b.*\bgroup-hover(\/\w+)?:|\bgroup-hover(\/\w+)?:(opacity-100|visible)\b/,
      allow: DEV_LAB,
    }), 'Show it. Only a pointer\'s shortcut for something the row\'s menu also does may wait: class `reveal` inside a `reveal-host` (globals.css), which shows on focus and on touch.').toEqual([])
  })

  it('a button explains itself through <Tip>, never `title`', () => {
    expect(tagFindings((tag, attrs) => (tag === 'button' || tag === 'Button') && /\btitle=/.test(attrs), DEV_LAB),
      'Wrap it in <Tip label="…">: a `title` waits a second, never shows on touch or focus, and cannot show a shortcut.').toEqual([])
  })

  it('focus, press and the touch target are written once', () => {
    const css = readFileSync(resolve(SRC, 'styles/globals.css'), 'utf8')
    expect(css).toMatch(/:focus-visible\s*\{\s*outline: 2px solid var\(--ring\)/)
    expect(css).toMatch(/@media \(pointer: coarse\)/)
    expect(css).toMatch(/\.reveal-host:focus-within/)
    // An outline taken away with nothing in its place.
    expect(findings({
      pattern: /^(?!.*(focus-visible:|focus:(?!outline-none)|data-\[)).*\boutline-none\b/,
      allow: either(under('components/ui/'), DEV_LAB),
    }), 'Leave the global focus ring, or replace it on the same element with a focus-visible: style.').toEqual([])
  })

  it('a drag has a keyboard and a menu', () => {
    const week = FILES.find(({ file }) => file === 'components/dashboard/WeekOverview.tsx')!.lines.join('\n')
    expect(week).toMatch(/KeyboardSensor/)
    expect(week).toMatch(/announcements:/)
    expect(week).toMatch(/<DropdownMenuLabel>Move to<\/DropdownMenuLabel>/)
  })

  it('one tooltip provider, one list of shortcuts', () => {
    expect(findings({
      pattern: /<TooltipProvider\b/,
      allow: is('components/shared/Tip.tsx', 'components/ui/tooltip.tsx'),
    }), 'App.tsx has <TipProvider>; use <Tip>, which finds it.').toEqual([])
    expect(findings({
      pattern: /addEventListener\('keydown'/,
      allow: either(is('components/layout/Shortcuts.tsx', 'components/log/LinkingTab.tsx'), DEV_LAB),
    }), 'A shortcut goes in lib/shortcuts.ts, so "?" lists it; Escape belongs to the dialog or sheet.').toEqual([])
  })
})

describe('hue is data, emerald is done (§8.12, §12.11)', () => {
  const COLOUR_MODULES = (file: string) => /^lib\/\w*[Cc]olors\.ts$/.test(file)
  const TESTS = (file: string) => /\.test\.tsx?$/.test(file) || file.startsWith('mocks/')

  it('done and the verdicts are tokens, never a raw green', () => {
    expect(findings({
      pattern: /\b(emerald|green)-\d/,
      allow: either(is('lib/dataColors.ts', 'lib/movementColors.ts'), GENERATED, DEV_LAB, TESTS),
    }), 'Finished is `text-done` / `bg-done/10` (lib/completionColors.ts); going well is `text-good` (lib/statusColors.ts). A green that is data — a scale step, a category — gets a name in lib/dataColors.ts.').toEqual([])
  })

  it('a component writes no hex', () => {
    expect(findings({
      pattern: /['"`(]#[0-9a-fA-F]{3,8}\b/,
      allow: either(COLOUR_MODULES, is('lib/hrZones.ts', 'lib/themes.ts', 'lib/developmentShaping.ts'), GENERATED, DEV_LAB, TESTS),
    }), 'A theme colour is a token (`var(--border)`); a data colour has a name in its module (lib/dataColors.ts for a series or scale).').toEqual([])
  })

  it('every chart sits in a ChartFrame', () => {
    expect(findings({
      pattern: /\bResponsiveContainer\b/,
      allow: is('components/shared/ChartFrame.tsx'),
    }), '<ChartFrame label="…" summary={say.series(…)}> gives the chart its name and its numbers in words (lib/chartSummary.ts).').toEqual([])
    const frames = tagFindings((tag, attrs) => tag === 'ChartFrame' && !/\blabel=/.test(attrs), TESTS)
    expect(frames, 'A ChartFrame says what it draws.').toEqual([])
  })

  it('the page can be skipped to and has one h1', () => {
    const layout = FILES.find(({ file }) => file === 'components/layout/RootLayout.tsx')!.lines.join('\n')
    expect(layout).toMatch(/href="#main"/)
    expect(layout).toMatch(/id="main"/)
    expect(findings({
      pattern: /<h1\b/,
      // Three pages outside the sidebar's sections write their own header, one h1 each.
      allow: either(is('components/layout/PageHeader.tsx', 'pages/ProgramHistoryDetail.tsx', 'pages/WorkoutDetail.tsx', 'pages/LoginPage.tsx'), DEV_LAB, TESTS),
    }), 'The page\'s name is PageHeader\'s `title`, its only h1; a section is an h2.').toEqual([])
  })
})
