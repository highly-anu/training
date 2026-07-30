# Frontend Fix Plan

Work list derived from auditing `frontend/` against `docs/frontend-design.md` on **2026-07-30**.

Scope: **web frontend only.** iOS and watchOS have their own gaps (`ios/docs/design-system.md` §2 specifies a named-color-asset system that was never built; `ios/README.md` describes an app three feature-generations out of date) — not covered here.

Every item below is a place where **the design doc is right and the code has drifted**. Divergences where the *code* made the better call were resolved by rewriting the doc instead, and are not work items — see §17.9 (Dashboard header) and §17.8 (two-tier and control-strip header variants) in the design doc.

Nothing here is speculative polish. Each item is either a measured standards failure, a broken invariant, or a duplication that will cause the next inconsistency.

---

## Status summary

Implemented 2026-07-30: FIX-1, FIX-2, FIX-3, FIX-4, FIX-7, FIX-8. Verified with `tsc --noEmit` (clean) and `npm run build` (clean). `npm run lint` reports 69 problems — byte-identical to the pre-work baseline, so zero regressions.

| ID | Item | Severity | Status |
|---|---|---|---|
| FIX-1 | Light-mode semantic text fails WCAG AA | **High** | ✅ **Done** — all systems paired, 2 modules extracted, regression guard in CI |
| FIX-2 | No reduced-motion support | **High** | ✅ **Done** |
| FIX-3 | GPS map pinned to dark basemap | Medium | ✅ **Done** |
| FIX-4 | HR zone colors triplicated | Medium | ✅ **Done** |
| FIX-5 | Hand-rolled empty states bypass `EmptyState` | Medium | ⬜ Open — per-site judgment, do incrementally |
| FIX-6 | Chart chrome partially hardcoded | Low | ⬜ Open — cleanup |
| FIX-7 | Pages missing the standard page transition | Low | ✅ **Done** |
| FIX-8 | Icon-only buttons have no accessible name | Medium | ✅ **Done** |
| FIX-9 | Theme web fonts load unconditionally | Low | ✅ **Closed** — decided to leave; rationale below |

**What's left:** FIX-5 and FIX-6, both opportunistic cleanup. The contrast guard is in place, so FIX-1 cannot silently regress.

**Not covered:** `pages/WorkoutImport.tsx` and `components/bio/BulkImportReview.tsx` were skipped throughout — they hold uncommitted bulk-import work in progress, and editing them would interleave with those changes. They contain the only remaining unpaired semantic text in the app (9 occurrences). Worth a pass once that feature lands.

---

## FIX-1 — Light-mode semantic text fails WCAG AA

**Severity: High. Status: ✅ done.**

Final state: **165 paired `text-{c}-700` / `dark:text-{c}-300`** class pairs across the app, perfectly balanced, with two new shared modules. The only unpaired semantic text left is in the two skipped WIP files.

### What the "64 usages" actually turned out to be

The original count came from grepping `text-emerald-500|text-emerald-400`, which conflated several unrelated systems. Classifying them properly found:

| Bucket | Disposition |
|---|---|
| True completion states (~20) | → `lib/completionColors.ts` |
| Score-widget status triplet | → `lib/statusColors.ts` (was duplicated ×3) |
| Chart marks, legend swatches, `bg-` fills | left alone — the colour is the data |
| Category / effort / fatigue text (§8.4–8.6) | re-paired in place |

Fixing only the emerald cases left style maps visibly half-converted — paired emerald sitting beside unpaired amber and red in the same object. So the pairing was extended to every semantic text colour (red, orange, amber, yellow, lime, green, teal, cyan, sky, blue, indigo, violet, purple, pink, rose, slate, zinc), which is what §8.8's corrected rule always implied.

### Second duplication found

`STATUS_STYLES` — the green/amber/red `ring`/`score`/`badge` triplet — was duplicated **verbatim** in `ReadinessWidget`, `DevelopmentWidget` and `ProgressionReviewCard`, differing only in `label`. Extracted to `lib/statusColors.ts`; `label` deliberately stayed local, since the same green reads "Ready" / "On Track" / "Ahead" depending on the question.

### A caution for anyone repeating this

The bulk sweep was regex-driven and produced three malformed classes that a build will *not* catch, because Tailwind emits no error for a nonsense variant chain:

- `\b` matched inside `dark:hover:`, yielding `dark:hover:text-x-700 dark:hover:text-x-300` on one element
- non-adjacent pairs (`text-x-600 … border-x/20 dark:text-x-400`) left a stray `dark:` class that `tailwind-merge` would resolve to the *wrong* shade
- an opacity-suffixed hover lost its `hover:` on the dark side

All three were caught by tallying class shapes (`text-X-700` count must equal `dark:text-X-300` count) rather than by tsc, build, or lint. **Do that tally after any bulk class edit** — none of the normal gates see these.

### The problem

`:root` holds the light palette (design doc §3.1), so a bare `text-{color}-400` class is what **light mode** renders. Both semantic color maps use `text-{c}-400 dark:text-{c}-300` — the `dark:` half brightens an already-passing dark mode, while light mode is left on the lighter shade, over a `/15` tint of the same hue on white.

Measured contrast against the tint each is actually painted on (AA floor for this text size is 4.5:1):

| Class | On | Ratio | |
|---|---|---|---|
| `text-red-400` (#f87171) | `bg-red-500/15` over white ≈ #fce3e3 | **2.27:1** | ✗ |
| `text-amber-500` (#f59e0b) | `bg-amber-500/10` over white ≈ #fef5e7 | **2.00:1** | ✗ |
| `text-emerald-500` (#10b981) | `bg-emerald-500/10` over white ≈ #e7f8f2 | **2.33:1** | ✗ |
| `text-red-500` (#ef4444) | `bg-red-500/10` over white ≈ #fdecec | **3.29:1** | ✗ |
| `text-emerald-700` (#047857) | `bg-emerald-500/10` over white ≈ #e7f8f2 | **5.05:1** | ✓ |

These badges render at `text-[10px]`–`text-xs`, which is where contrast matters most.

Not cosmetic: modality and phase are how a user tells a strength day from a conditioning day at a glance. In light mode that distinction is currently near-invisible to anyone with reduced contrast sensitivity, and marginal for everyone else.

### The fix

Target pairing everywhere: **`text-{color}-700 dark:text-{color}-300`**. No shade lighter than `-600` clears the floor; `-700` clears it with margin.

Three sites, all complete:

1. ✅ **`src/lib/phaseColors.ts`** — 11 entries.
2. ✅ **`src/lib/modalityColors.ts`** — 12 entries.
3. ✅ **Completion states** — extracted to `lib/completionColors.ts`, plus `lib/statusColors.ts` for the status triplet.

For (3), **extract to `src/lib/completionColors.ts`** while fixing rather than patching in place. One color owning one meaning across the whole app is the case a shared module exists for, and 64 hand-maintained copies is how the next drift starts. Mirror the shape of the existing maps:

```typescript
export const COMPLETION = {
  border: 'border-emerald-500/30',
  bg:     'bg-emerald-500/10',
  text:   'text-emerald-700 dark:text-emerald-300',
  hover:  'hover:bg-emerald-500/20',
} as const
```

### Also check

- **Military and Zen backgrounds are not white.** Military is dark (olive-tinted) and behaves like dark mode; Zen is a warm off-white and behaves like light. Verify the `-700` shade on Zen's `oklch(0.97 0.012 90)` background, not just on pure white.
- **`hex` values must not change.** They are mirrored into two Swift files (design doc §8.9). This fix touches Tailwind *class* strings only. Changing a hex is a three-file, three-platform change and is out of scope here.

### Verification

Sample one badge per system per theme against a contrast checker. Then consider the guard below — this class of bug is invisible in review and will recur.

### Follow-on: contrast regression guard — ✅ done

`test/semanticContrast.test.ts` + `test/contrastUtils.ts`. Runs via `npm test` and in CI on every frontend PR (added to `.github/workflows/frontend-build.yml`, which previously ran only the build).

Required adding a test runner — the frontend had none. Chose **vitest**: Vite-native, one dev dependency, and it picks up TS and the `@` alias without extra config.

**It found 14 entries the manual sweep missed**, all near-misses in the 4.25–4.49 range, so all invisible to review. That corrected the rule recorded in the design doc: `-700` is *not* universally sufficient. The bright hues (orange, amber, yellow, lime, green, emerald, teal, cyan, pink, rose) need `-800` on a `/15` tint. Two non-obvious causes:

- **Tint strength matters.** `emerald-700` passes on completion's `/10` tint (5.05:1) but fails on modality's `/15` (4.31:1). Same hue, different system, different required shade.
- **Zen is the binding constraint**, not light. Its warm off-white background composites every tint darker, so several entries pass in Light and fail only in Zen.

**Both failure modes are verified to actually fail**, which matters more than the passing run — a guard that cannot fail is decoration:

| Injected regression | Caught as |
|---|---|
| `text-red-700` → `text-red-400` (the original bug) | `modality/max_strength in "light": 2.33:1` |
| dropped the `dark:` half | `phase/base in "dark": 2.84:1` + `no dark:text-* shade` |

**Design choice worth keeping:** the palette is read from `node_modules/tailwindcss/theme.css` and the backgrounds from `src/styles/globals.css`, not hardcoded. A hex table would drift silently the moment Tailwind or a theme changed. Two self-check assertions ensure the parsers matched something, so a regex that matches nothing fails loudly rather than passing everything.

---

## FIX-2 — No reduced-motion support

**Severity: High. Status: ✅ done.** Highest value-per-line item in this plan.

**Implemented:** `MotionConfig reducedMotion="user"` wraps the tree in `src/App.tsx`; `DumbbellLoader` gates its `pathOffset` loop on `useReducedMotion()` and falls back to the static glyph at `opacity 0.6` (raised from 0.2 so the fallback doesn't read as broken), plus a `role="status"` on its container. Recharts entry animations are the one remaining item — see the table below.

### The problem

Zero results across `frontend/src` for `useReducedMotion`, `prefers-reduced-motion`, `motion-reduce:`, and `MotionConfig`. Every animation in design doc §9 plays at full amplitude for users who have asked their OS to stop them: page transitions translate 16px, cards scale on hover, panels slide 420px, wizard steps slide 60px, lists stagger.

`prefers-reduced-motion` exists largely for vestibular disorders, where this triggers real symptoms. Design doc §1.6 names accessibility a foundation.

### The fix

One provider at the app root (`src/App.tsx`) covers most of it:

```tsx
import { MotionConfig } from 'framer-motion'

<MotionConfig reducedMotion="user">
  {/* existing tree */}
</MotionConfig>
```

`reducedMotion="user"` disables transform and layout animations (`x`, `y`, `scale`, `rotate`, `height`) while letting `opacity` and `backgroundColor` through — the right split for this system. Page transitions become clean cross-fades, set-completion keeps its color-flash confirmation, expand/collapse snaps. Orientation and feedback survive; only movement stops.

### Not covered by the provider

| Surface | Handling |
|---|---|
| `animate-pulse` skeletons | Leave — low-amplitude opacity only |
| `animate-spin` spinners | Leave — conveys liveness, no translation |
| `DumbbellLoader` | Gate on `useReducedMotion()`; fall back to the dim static glyph it already draws as its base layer |
| Recharts entry animations | `isAnimationActive={false}` when reduced (`animationDuration`/`animationBegin` are set explicitly in `ModalityDonut` and others) |

`DumbbellLoader` is the one that matters — a continuously looping animation is the exact case the preference targets, and it already renders a correct static base, so the fallback is nearly free.

### Verification

macOS: System Settings → Accessibility → Display → Reduce motion. Walk Dashboard → day panel → session detail → builder wizard. Nothing should translate; everything should still be legible and complete.

---

## FIX-3 — GPS map pinned to dark basemap in all themes

**Severity: Medium. Status: ✅ done.** Best effort-to-visibility ratio here.

**Implemented** in `src/components/workout/GPSMap.tsx` exactly as specified below, including the `key={tileUrl}` on `<TileLayer>` to force a clean tile swap. Z1 slate against the light basemap was checked and reads acceptably.

### The problem

`src/components/workout/GPSMap.tsx:90`:

```tsx
<TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" />
```

Hardcoded to CartoDB's **dark** basemap regardless of theme. In Light and Zen this drops a dark slab into a pale page — roughly 360px tall, the most conspicuous theme break in the app. Zen is hit worst: its whole premise is a warm, soft surface.

### The fix

CartoDB serves `light_all` at an identical URL shape. Select from the active theme:

```tsx
import { useTheme } from 'next-themes'

const { resolvedTheme } = useTheme()
const isDark = resolvedTheme === 'dark' || resolvedTheme === 'military'
const tileUrl = `https://{s}.basemaps.cartocdn.com/${isDark ? 'dark_all' : 'light_all'}/{z}/{x}/{y}{r}.png`
```

Military is dark-background, so it groups with dark; Zen groups with light. Consider lifting that mapping into a small `useIsDarkTheme()` hook — anything else theme-branching on lightness will want it.

### Watch for

- Leaflet may need a re-render to swap tiles cleanly; key the `<TileLayer>` on `tileUrl` if they don't.
- Route polylines are colored by HR zone (§8.7). Z1 slate `#94a3b8` is the weakest against a light basemap — check it before calling this done.
- Keep the container's `isolate`. Leaflet sets high z-indexes on its panes; without a stacking context the map paints over sheets and dialogs.

---

## FIX-4 — HR zone colors triplicated

**Severity: Medium. Status: ✅ done.** No visible defect today; it was a correctness trap.

**Implemented:** `ZONES` (colour + label + description + band fill) now lives in `src/lib/hrZones.ts`, with `ZONE_COLORS` and `ZONE_BG` derived from it. All three consumers import it; `HRZoneChart`'s local `ZONE_META` is now an alias.

### The problem

The five-color zone ramp is copy-pasted verbatim in three files:

- `src/components/workout/HRTimeline.tsx:29`
- `src/components/bio/HRZoneChart.tsx:18`
- `src/components/workout/GPSMap.tsx:9`

All three currently agree. Every other semantic color system in the app lives in `lib/` for exactly this reason, and the zone *boundaries* already live in `lib/hrZones.ts` — so the colors are separated from the thresholds they color.

### The fix

Move the ramp into `src/lib/hrZones.ts`, beside `DEFAULT_ZONE_BOUNDARIES`, and import in all three consumers:

```typescript
export const ZONE_COLORS = [
  '#94a3b8', // Z1 — slate  · Recovery   (<60% max HR)
  '#38bdf8', // Z2 — sky    · Aerobic    (60–70%)
  '#fbbf24', // Z3 — amber  · Tempo      (70–80%)
  '#f97316', // Z4 — orange · Threshold  (80–90%)
  '#ef4444', // Z5 — red    · Max        (90%+)
] as const
```

`HRZoneChart` also carries per-zone `label` and `description` ("Z1", "Recovery"). Fold those in as a single `ZONES` array of objects so labels stop being re-derived per consumer.

`HRTimeline` additionally holds `ZONE_BG` (`rgba(148,163,184,0.06)` and siblings) for its background bands — derived from the same ramp, so move it alongside.

### Do not

Fold zone colors into `MODALITY_COLORS`. They encode a different axis — measured intensity vs. training category — and their near-collisions (Z2 sky-400 vs `aerobic_base` sky-500) are intentional. Design doc §8.7 covers why.

---

## FIX-5 — Hand-rolled empty states bypass the shared component

**Severity: Medium.** Real UX cost, not just duplication.

### The problem

`src/components/shared/EmptyState.tsx` is imported by **6** files. There are **25** hand-rolled `border-dashed` empty states. The pattern was adopted; the component was not.

The cost is not visual — most copies look approximately right. It is that `EmptyState` takes an `action` CTA, and the hand-rolled copies consistently omit it. A meaningful share of the app's zero-data views are dead ends offering no path forward, directly against design doc §1.4 and §11.2 ("always provide an action CTA that resolves the empty state").

### The fix

Audit the 25 sites:

```bash
grep -rn "border-dashed" frontend/src --include="*.tsx"
```

Sort into three buckets:

1. **Zero-data views** → convert to `<EmptyState>`, and supply the `action` that was dropped. This is the bucket that matters.
2. **Slot-sized empty cells** (an unscheduled day in the week grid) → leave. Too small for title/description/CTA; a bare dashed cell is correct, and the design doc now records this as the sanctioned exception.
3. **Decorative dashed borders** (drop zones, placeholder outlines) → leave, unrelated.

If a site needs something `EmptyState` cannot express, extend the component. Do not fork it inline.

**Incremental is fine.** No need for one big sweep — convert as files are touched, prioritizing views a new user hits first (no program, no workouts, no bio data), since those are exactly where a missing CTA does the most damage.

---

## FIX-6 — Chart chrome partially hardcoded

**Severity: Low.** Cleanup, best done opportunistically.

### The problem

Roughly 30 hardcoded hex values against ~32 `var(--color-*)` references across chart files. The right split is:

- **Semantic marks** (bars, lines, cells that *mean* something) → hardcoded hex from a §8 system. Correct as-is — amber must stay amber in Zen.
- **Chart chrome** (axes, ticks, grid, cursor, tooltip surface, reference lines) → `var(--color-*)` tokens.

Some chrome is still hardcoded and will read wrong in Military and Zen.

### The fix

Sweep chart files for hardcoded chrome and convert:

| Chrome | Token |
|---|---|
| axis tick fill | `var(--color-muted-foreground)` |
| axis / grid lines | `var(--color-border)` |
| tooltip background | `var(--color-card)` |
| tooltip border | `var(--color-border)` |
| cursor fill | `var(--color-muted-foreground)` @ `fillOpacity: 0.08` |
| neutral reference lines | `var(--color-border)` |

Leave every mark color alone.

### Related

`src/pages/WorkoutAnalytics.tsx` defines chart series colors inline rather than importing a §8 system. The values it picks are correct today, so this is genuinely low priority — but new series added there should read from `MODALITY_COLORS` or `ZONE_COLORS`, not fresh literals.

### Verification

Open each chart in all four themes. Military (olive, dot-grid body) and Zen (warm off-white, gradient washes) are where hardcoded chrome shows.

---

## FIX-7 — Pages missing the standard page transition

**Severity: Low. Status: ✅ done.**

**Implemented:** `DevLab.tsx` root is now the standard `motion.div` wrapper with `key="devlab"`. Login was assessed and is **intentionally exempt** — it renders pre-auth, outside `RootLayout` and outside the router's `AnimatePresence`, so it has no sibling to transition against.

`DevLab.tsx` and `LoginPage.tsx` have no Framer Motion usage; all 12 other pages carry the standard enter/exit from design doc §9.1. Route changes into and out of Dev Lab cut hard while every neighbor fades.

**Dev Lab:** wrap the page root in the standard page wrapper.

```tsx
<motion.div
  key="devlab"
  initial={{ opacity: 0, y: 16 }}
  animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
  exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
  className="flex h-full flex-col overflow-hidden"
>
```

The `key` must be unique — `AnimatePresence` cannot sequence pages without it.

**Login:** likely fine to leave. It renders pre-auth, outside the app shell and outside the router's `AnimatePresence`, so it has no sibling to transition against. Confirm, then either wrap it or record it as intentionally exempt.

Do this after FIX-2 so the new transition inherits reduced-motion handling.

---

## FIX-8 — Icon-only buttons have no accessible name

**Severity: Medium. Status: ✅ done.**

**Implemented:** all 7 `size="icon"` buttons now carry an action-describing `aria-label` — sidebar toggle, previous/next week, clear search, play/pause week animation (label follows state), reset week range. Sheet and dialog closes were checked: Radix's `SheetClose`/`DialogClose` already supply an accessible name, so none was added.

### The problem

10 `aria-label` attributes across 154 components. Design doc §17.7 specifies icon-only ghost buttons as the standard page-level action:

```tsx
<Button variant="ghost" size="icon" className="size-8">
  <SomeIcon className="size-4" />
</Button>
```

A Lucide icon renders as an `<svg>` with no text content, so each of these is an unnamed control to a screen reader — announced as "button" with nothing else. Radix supplies roles, keyboard handling, and focus, which made this feel solved; naming is the part Radix cannot infer.

### The fix

```bash
grep -rn 'size="icon"' frontend/src --include="*.tsx"
```

Add `aria-label` to each, describing the **action**, not the icon — `aria-label="Refresh program"`, never `aria-label="RefreshCw"`.

Priority order:
1. Page header actions (§17.7) — the top-level controls on every page
2. Sheet/dialog close buttons — check whether Radix's `SheetClose` already supplies a name before adding one
3. Card-level icon actions (replace, move, delete on session cards)

Also worth a pass: the 3 existing `sr-only` uses suggest the pattern is known but was applied unevenly. Either convention is fine; `aria-label` is less markup for a bare icon button.

### Verification

VoiceOver (⌘F5), tab through a page header. Every stop should announce a meaningful name.

---

## FIX-9 — Theme web fonts load unconditionally

**Severity: Low. Status: ✅ closed — decided to leave as-is (option 1).**

`index.html:9-11` loads IBM Plex Mono (Military) and Lora (Zen) from Google Fonts on every page load, via two `preconnect`s and one render-blocking stylesheet `<link>`. Only two of four themes use them, and the default theme is dark — so most users pay for two fonts they never render.

It is already correctly built: `display=swap` is set, weights are scoped, `preconnect` is present. The only issue is that it is unconditional.

**Options, in order of preference:**

1. **Leave it.** One stylesheet with `swap` and `preconnect` is a small cost, and deferring risks a visible font swap when a Military/Zen user loads. Defensible — record the decision and close the item.
2. **Inject on demand.** Append the `<link>` when the theme becomes `military` or `zen`, from the same place `next-themes` is configured. Costs a one-time swap on first switch into those themes.
3. **Self-host** `woff2` subsets. Removes the third-party dependency and the two `preconnect`s; adds build weight.

No action required — this is recorded so the decision is deliberate rather than accidental.

---

## Explicitly not doing

Items considered and rejected, so they are not re-litigated:

| Item | Why not |
|---|---|
| Changing modality/phase **hex** values | Mirrored by hand into two Swift files (design doc §8.9). A three-platform change with no defect motivating it. FIX-1 touches class strings only. |
| Making Dashboard drop its tab header | The old §17.9 rule said to. The code is better — see the rewritten §17.9. Doc was changed instead. |
| Converting Explore's `flex-wrap` header to one row | It carries two tab tiers and handles it correctly. Documented as a sanctioned variant in §17.8. |
| Splitting `ExerciseCatalog` / `ProgramView` two-row headers | The identity row obeys §17.2; the strip below is content-scoped chrome. Documented as the control-strip variant. |
| Unifying zone colors with modality colors | Different semantic axes. Near-collisions are intentional (§8.7). |
| Container queries, `layoutId` shared elements, virtualization, `color-mix()` | Real opportunities, but enhancements — not gaps against the current spec. Track separately from this plan. |
