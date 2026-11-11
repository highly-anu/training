# iOS Design System

The visual language, interaction patterns, and implementation decisions for the TrainingCompanion iPhone and Apple Watch apps. Derived from and consistent with `docs/frontend-design.md` (the web design system), translated into SwiftUI idioms. All screens — phone and watch — reference this document.

---

## Table of Contents

1. [The Design Language](#1-the-design-language) — six principles, and §1.8: every rule with what holds it
2. [Color Architecture](#2-color-architecture)
3. [Semantic Color Systems](#3-semantic-color-systems)
4. [Typography](#4-typography)
5. [Spacing & Layout](#5-spacing--layout)
6. [Component Patterns](#6-component-patterns)
7. [Motion & Animation](#7-motion--animation)
8. [Accessibility](#8-accessibility)
9. [Watch-Specific Rules](#9-watch-specific-rules)

**Components by job** (§6 is numbered in the order the patterns were written, not by theme):

| Job | Sections |
|---|---|
| Surfaces and controls | 6.3 states · 6.4 section header · 6.6 buttons · 6.15 card and status · 6.37 card and detail · 6.47 floating controls and the action bar |
| Navigation | 6.8 sub-tabs · 6.9 cross-tab routes · 6.13 tab structure · 6.48 sheets, pushes and zoom · 6.49 pager · 6.50 week strip |
| Actions | 6.43 session actions · 6.51 row actions · 6.24 filter menu · 6.38 constraint toggles · 6.52 tips |
| Sessions and the player | 6.1 session card · 6.2 modality badge · 6.5 load text · 6.14 exercise detail · 6.16 logging · 6.40 session icon · 6.44 player · 6.45 start and resume · 6.54 after the session |
| Today and Program | 6.53 Today · 6.17 regenerate offer · 6.18 methodology · 6.22 tracks and phases · 6.26 phase changes · 6.28 header card · 6.36 phase bar · 6.39 preview · 6.55 builder |
| Analytics | 6.11 period filter · 6.20 Blocks · 6.21 readiness · 6.25 score · 6.35 zone plan · 6.41 progress chart |
| Log and workouts | 6.10 route and charts · 6.12 activity icons · 6.19 Log · 6.23 workout row · 6.30 Workout complete |
| Standards | 6.31 ladder · 6.32 detail · 6.33 test badge · 6.34 suggestion |
| Motion and accessibility | 6.56 motion helpers and the completion moment · 6.57 accessibility helpers and the largest sizes |
| System surfaces | 6.27 home-screen widgets · 6.58 rendering modes and the Lock Screen · 6.44 the Live Activity · 6.29 sign-in |

---

## 1. The Design Language

The phone's language since the uplift of 1.35–1.41 (`docs/roadmap.md` item 18). Six
principles and the rule that keeps them (§1.7); §1.8 lists what they come down to, each
rule with the helper that carries it and what holds it. The web's principles
(`docs/frontend-design.md` §1) are the same ones in another idiom.

### 1.1 Content Is Solid, Chrome Floats

Every visual element conveys information or guides attention. There are two layers and
only two:

- **Content** — cards, rows, charts, sheets — is solid: one card (`.appCard()`, radius 16,
  `AppColor.surface`), no shadow, no blur, no gradient for depth.
- **Chrome** — the tab bar and its accessory, navigation bars, a screen's bottom action
  bar, the player's controls — is the system's Liquid Glass, with content scrolling
  beneath it (§6.47). Glass is never a card's background and never decoration.

The system's own chrome (`TabView`, `NavigationStack`, `List`, `Form`) is used as it comes.

### 1.2 Colour Has Three Jobs

- **Amber is "tap me"**: the tint (`AppColor.accent`) on every control, link and selection,
  and on load prescriptions. Nothing interactive or selected is blue.
- **Emerald is "done"** (`AppColor.complete`): saved, linked, on track — apart from the
  tint, so finished never reads as a button.
- **Hue is data**: a modality, a phase kind, a heart-rate zone, a chart series, each from
  its one owner (§3). Orange, yellow and red are states (`warning`, `caution`,
  `destructive`).

Both appearances are designed; the app follows the system unless Settings ▸ Appearance
says otherwise. A view writes no colour literal (§2).

### 1.3 Dense but Breathable

Training data is complex. Tight inside a component, generous between components, on one
scale (`AppMetrics`, §5): 4 pt inside a label, 8 between rows, 12 between cards, 16 at the
page's edge and inside a card, 24 between sections. Type is the system's text styles, so
it scales; the large numerals are `AppFont` (§4).

### 1.4 Progressive Disclosure

A summary state and a detail state, never everything at once: Today shows the day and
leads with the session to do next; a card opens its detail; an exercise shows its load and
opens its reference. How the detail arrives says what it is — a zoom from the card it
belongs to, a half-height sheet for a short choice, a push for a further step inside a
sheet, never a sheet on a sheet (§6.48).

**Numbers and symbols, not sentences** (2026-10-16). A screen says what a value is with
an SF Symbol and the number — `clock 21/18 min/wk`, `heart.fill 104/135`,
`checkmark.circle 1/1` — and a status with a coloured mark or badge, not a sentence. No
subtitle explains a section, no footnote names where a number came from unless it is the
exception (`iphone` "On device" when the server could not answer), and no row points to
another tab in words. The full sentence goes to VoiceOver (`appStat`, §6.57). Words stay
where a symbol cannot carry them: an empty state's one line, a coverage reason that tells
the athlete what to log, the server's recommendations.

### 1.5 Nothing Is Hidden

**Every action can be seen.** A gesture is a shortcut, never the only way. Each long
press, swipe and drag has a visible twin built into the component: the "…" on a session
card and a row (§6.43, §6.51), chevrons and a title on every pager (§6.49), the week strip
(§6.50), "+ Add session" on a rest day. A screen's main action is one tap away and where
the thumb is: its bottom action bar (§6.47), or on the card itself (Start workout, §6.53).

**Every screen answers before its content.** Loading, failed, empty — from one reading
(`AppLoadPhase`, §6.3). Loading is the content's own shape, redacted; a failure says so
and offers Try again; empty offers the way forward. Content on screen is never replaced by
a reload or its failure. A spinner is only for an action in flight.

### 1.6 Motion Answers, and Everyone Can Use It

**Motion** has three jobs: orientation (where did this come from), feedback (did that
register), continuity (what changed). Nothing moves that the athlete did not cause or that
did not just arrive. Springs are the standard, three presets in `AppAnimation` (§7.1); a
number rolls, a symbol follows its state, a chart draws once, and finishing a session is
the one moment that celebrates (§6.56). A touch answers what happened (`AppHaptics`, §7.4).

**Accessibility is part of each component, not a pass after it** (§8, §6.57): Reduce
Motion is decided once, inside the presets; every control is 44 pt; a value, its unit and
its caption read as one fact; every chart reads its numbers; colour is never the only
carrier of meaning; and every screen holds at the largest Dynamic Type size.

### 1.7 One Pattern, One Implementation

The rules above only hold if there is one place they are written down in code.
Two screens solving the same problem their own way is how a design language
dissolves — not through a bad decision, but through a reasonable one made
twice.

**When you need a component that another screen already has:**

1. **Look here first.** If §6 documents the pattern, use the component it
   names. Do not re-derive it from how a neighbouring screen looks.
2. **If two screens need it and no component exists, extract one** — then
   convert *both* call sites in the same change. A shared component with one
   user is a guess; with two it is a pattern. Leaving the original screen on
   its old implementation means the divergence survives, just with more code.
3. **Document it in §6** with its rules and, where the decision is not
   obvious, a *when not to use it*. A component without a boundary gets
   stretched to fit things it was never meant for.
4. **Put shared behaviour inside the component**, not in instructions at the
   call site. Haptics, spacing and animation belong to `AppSubTabPicker`
   precisely so no screen has to remember them. If a rule can only be followed
   by remembering it, it will eventually not be.

**When you find two screens already diverged**, treat it as a bug in the design
system rather than in either screen: the system failed to offer the pattern.
Fix it by extracting, converting both, and writing the section — in one change,
so the next person meets a rule rather than a precedent.

The counter-pressure is real: converting the second screen is always more work
than copying the first. Do it anyway, or be explicit in review about why not.

### 1.8 The Rules, and What Holds Each

Each rule lives in one file, and where a breach can be read from the source a test fails
on it: `DesignTokenTests` reads every Swift file of the app for the patterns below.

| Rule | Use | Owner | Held by |
|---|---|---|---|
| No colour literal in a view | `AppColor`, `ModalityStyle`, `PhaseStyle`, `HRZoneStyle` | `AppTheme.swift`, generated `ClientVocab.swift` | test: `Color(red:` |
| No fixed font size | a text style, or `AppFont` (`hero`, `metric`, `symbol`) | `AppTheme.swift` | test: `.system(size:` |
| Colour over a surface on one scale | `AppColor.Opacity` (§2.2) | `AppTheme.swift` | review |
| Spacing and radii on one scale; a card is 16 | `AppMetrics`, `.appCard()` / `AppCard` | `AppAnimationSettings.swift`, `AppCard.swift` | review |
| One section header | `SectionLabel` | `AppCard.swift` | review |
| One button family | `.appButton(.primary / .secondary / .destructive / .complete)` | `AppCard.swift` | test: `.buttonStyle(.bordered…)` |
| Glass only on what floats | `.appActionBar { }`, `AppFloatingControls { }` | `AppCard.swift` | test: `.buttonStyle(.glass` |
| Three states before content | `AppLoadPhase.resolve`, `AppLoadingState`, `AppEmptyState`, `AppFailedState`, `AppErrorBanner` | `Views/AppStates.swift` | `AppLoadPhaseTests` |
| Sheet heights by content | `.appSheet(.compact / .flexible)` | `AppNavigation.swift` | test: `.presentationDetents(` |
| No sheet on a sheet | `.appPush(item:)` inside the sheet's stack | `AppNavigation.swift` | review |
| A detail grows from its source | `.appZoom(from:in:)` | `AppNavigation.swift` | test: `.navigationTransition(` |
| One sub-tab selector | `AppSubTabScreen` / `AppSubTabPicker` (§6.8) | `AppSubTabs.swift` | review |
| Tabs change through the router | `AppRouter`'s methods (§6.9) | `AppRouter.swift` | review |
| Every gesture has a visible twin | `SessionActionsMenu`, a row's own "…", `AppPager`, the week strip | `Views/SessionActions.swift`, `AppPager.swift`, `Views/WeekStrip.swift` | review; `PagingTests` |
| No animation or curve of a view's own | `AppAnimation` presets | `AppAnimationSettings.swift` | test: bare `withAnimation {`, `.easeOut(duration:` and its kin |
| Small motions through one modifier each | `appNumeric`, `appSymbolBounce` / `Replace` / `Spin`, `AppScrollFade`, `appChartEntry` | `AppMotion.swift` | test: `.contentTransition(`, `.symbolEffect(`, `.scrollTransition(` |
| Reduce Motion asked by no view | built into the presets and modifiers | the two files above | by construction |
| Haptics through one API | `AppHaptics`, `AppRefresh.perform` | `AppAnimationSettings.swift` | review |
| 44 pt targets | `.appTapTarget()`, `.appTapSlop()` | `AppAccessibility.swift` | review |
| One fact, one element | `.appStat(_:)`, `.appTapRow(selected:)` | `AppAccessibility.swift` | review |
| Every chart reads its numbers | `.appChartSummary(_:_:)` + `ChartSummary` | `AppAccessibility.swift` | `AccessibilityAndRemoteTests` (the wording) |
| Colour never alone | words, a symbol, or `ColorTwin(symbol:)` | `AppAccessibility.swift` | review |
| Rows hold at the largest text size | `AppAdaptiveStack`, `AppAdaptiveGrid` | `AppAccessibility.swift` | a screenshot at that size |
| Prescriptions in one wording | `LoadFormat.describe` (§6.5) | `LoadFormat.swift` | `LoadFormatTests` |
| Custom symbols draw | `Image(symbol:)` (`ios/docs/custom-icons.md`) | `AppSymbol` | `SessionIconTests` |
| Widgets survive one tint | `.widgetAccentable()`, `widgetRenderingMode`, text styles (§6.58) | `TrainingWidgets/` | review |

A "review" row is checked by eye: a change to a screen ends in the simulator, in both
appearances, and — when a row or chart changed — at the largest Dynamic Type size
(`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`).

A new rule gets a row here, a helper in one file and, where the breach can be read from
the source, a line in `DesignTokenTests`.

---

## 2. Color Architecture

### 2.1 Colour Tokens

Every colour a view uses has a name in `AppColor` (`AppTheme.swift`) or comes from one
of the generated or semantic systems of §3. A view never writes a literal: `Color(red:`
belongs to `AppTheme.swift` and the generated `ClientVocab.swift` alone, and
`DesignTokenTests` fails the build's tests on any other. (Until 1.35 this section listed
ten named assets that did not exist, and the app shipped system blue: `AccentColor` was
empty in all four targets.)

| Token | Value | Use |
|---|---|---|
| `AppColor.accent` | the `AccentColor` asset: `#C97D15` dark, `#A8650F` light | The tint: every control, link, selection and load prescription. The brand amber reads 3.3:1 on white, so light mode takes the darker one (4.6:1). The asset is the same in the app, the widgets, the watch app and its widgets |
| `AppColor.surface` | `secondarySystemBackground` | A card on the page |
| `AppColor.surfaceGrouped` | `secondarySystemGroupedBackground` | A row or card inside a grouped list or form |
| `AppColor.surfaceRaised` | `tertiarySystemBackground` | A control or chip inside a card |
| `AppColor.separator` | `separator` | A hairline between or around surfaces |
| `AppColor.complete` | `#10B981` emerald, both themes | Done, saved, linked, on track — never the tint, so "done" reads apart from "tap me" |
| `AppColor.warning` | system orange | Needs attention, nothing failed: behind, partial, a compromise |
| `AppColor.caution` | system yellow | Weaker than a warning: a mild flag, a middling reading |
| `AppColor.destructive` | system red | A failure, or an action that removes something |
| `AppColor.info` | system blue | Neutral information that wants a colour of its own |

Text takes the system's hierarchy — `.primary`, `.secondary`, `.tertiary` (§4.2) — and
pages the system background; neither has a token.

**Blue is not a selection colour.** Anything interactive or selected is the tint. Blue
appears only as data: heart-rate zone 1, a chart series, a modality.

**Palettes** that are data, each in `AppColor`: `Effect` (training effect, mild to hard),
`blocks` (five hues cycled in block order, the web's `lib/developmentShaping.ts`),
`Sleep` (stages), `Schedule` (Profile ▸ Schedule's session lengths). Heart-rate zones
(`HRZoneStyle`), chart series and the modality and phase-kind colours (`ClientVocab`,
generated) keep their own owners (§3).

### 2.2 Opacity Scale

How strongly a colour is laid over a surface: `AppColor.Opacity`, one step per job, so two
cards tinted with different colours weigh the same.

| Token | Value | Use |
|---|---|---|
| `tint` | `0.08` | A card washed with its colour (a completed session) |
| `fill` | `0.12` | A badge or chip's fill |
| `fillStrong` | `0.2` | A selected chip, a bar's track |
| `border` | `0.35` | A coloured border |
| `ghost` | `0.5` | Disabled, not yet reached, behind the data |
| `muted` | `0.75` | De-emphasised but still read |

```swift
.background(AppColor.complete.opacity(AppColor.Opacity.fill))
```

---

## 3. Semantic Color Systems

These are exact values (not the tint, not named assets) because the specific colour IS the information: modality badges, session card stripes, chart series and phase indicators. Each has one owner — the generated `ClientVocab.swift` for modalities and phase kinds, `AppTheme.swift` for the rest — and a view reads it through `ModalityStyle`, `PhaseStyle`, `HRZoneStyle` or `AppColor`, never as a literal (§1.8).

### 3.1 Modality Colors

Exact values match the web `MODALITY_COLORS` table because both are generated from the modality files' `display` blocks (`tools/gen_client_vocab.py` → `ClientVocab.swift` in each target folder; frontend-design §8.9). All iOS screens that show modality identity use these — no approximations; the watch complication now does too (it drew the nearest system colours).

```swift
// ModalityStyle.swift reads the generated ClientVocab; no view holds a hex.
ModalityStyle.color(for: session.modality)   // Color
ModalityStyle.label(for: session.modality)   // "Max Strength"
ModalityStyle.icon(for: session.modality)    // SF Symbol name
```

The values are the modality files' `display` blocks
(`data/commons/modalities/*.yaml`); change one there and regenerate.

**Color grouping logic (matches web):**
- Warm (red → rose → orange): strength modalities
- Cool (sky → cyan): aerobic/interval
- Purple/violet: mixed modal
- Green spectrum (emerald → teal → lime): recovery, skill, rehab
- Pink: combat sport
- Amber/yellow: power, durability

**How to apply modality color:**

```swift
// Top bar stripe on session card (2pt height)
Rectangle()
    .fill(color)
    .frame(height: 2)

// Badge background
Text(style.label)
    .font(.caption2).fontWeight(.semibold)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(color.opacity(AppColor.Opacity.fill))
    .foregroundStyle(color)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(AppColor.Opacity.border), lineWidth: 1))

// Icon tint
Image(systemName: style.icon)
    .foregroundStyle(color)
```

### 3.2 Training Phase Colors

A phase has two parts. Its **name** is its methodology's own ("Foundations",
"Transmutation", "Specific"): `ProgramWeek.phaseLabel`, `PhilosophyPhase.name`.
Its **colour** comes from its **kind**, the shared vocabulary in
`data/commons/phase_kinds.yaml`. `PhaseStyle.color(for:)` is the one mapping, read
from the generated `ClientVocab.phases` — the same data as the web's `lib/phaseColors.ts`:

| Kind | Hex | | Kind | Hex |
|---|---|---|---|---|
| base | `#0ea5e9` | | specific | `#f97316` |
| build | `#f59e0b` | | maintenance | `#a1a1aa` |
| peak | `#ef4444` | | rehab | `#84cc16` |
| taper | `#22c55e` | | post_op | `#a855f7` |
| transition | `#8b5cf6` | | deload / recovery / active | `#94a3b8` |

Never label a phase by its kind when the week carries a name, and never write
a phase's description from its kind: the words belong to the methodology.
Program ▸ Current used to colour four kinds with system colours and everything
else grey.

**Intuitive mapping (same as web):** Blue = foundation, Amber = building heat, Red = peak intensity, Green = tapering, Gray = recovery/maintenance.

### 3.3 Completion State

One color owns "done" throughout the entire app: `#10b981` (emerald-500). Same as `CompleteGreen` asset.

```swift
// Completed session card overlay
.background(AppColor.complete.opacity(0.08))
.overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.complete.opacity(0.25)))

// Completion checkmark
Image(systemName: "checkmark.circle.fill")
    .foregroundStyle(AppColor.complete)
```

### 3.4 Slot-Type Icons

Used in exercise lists and session progress views. Always paired with a text label — never icon-only.

```swift
func slotTypeIcon(_ slotType: String) -> String {
    switch slotType {
    case "sets_reps":      return "dumbbell.fill"
    case "time_domain":    return "clock.fill"
    case "skill_practice": return "sparkles"
    case "emom":           return "timer"
    case "amrap":          return "arrow.clockwise"
    case "amrap_movement": return "repeat"
    case "for_time":       return "flag.checkered"
    case "distance":       return "map.fill"
    case "static_hold":    return "pause.circle.fill"
    default:               return "square.fill"
    }
}
```

### 3.5 Heart-Rate Zone Colors

`HRZoneStyle` (`HRZoneStyle.swift`): Z1 blue, Z2 green, Z3 yellow, Z4 orange,
Z5 red — easy to hard. Every zone drawn on the phone reads it: Analytics ▸
Program's intensity rows, a workout's zone distribution and HR timeline bands,
and Profile ▸ Athlete's zone bar (the five zones as one bar, each segment as
wide as its share of heart rate, its bpm range under it; each edge's stepper
carries the colour of the zone it ends; the bar is as tall as its label at the
athlete's text size, never a fixed height). The timeline used to draw slate/sky
bands from the web palette while the rest drew blue…red.

---

## 4. Typography

System font throughout. No web fonts. Dynamic Type supported on all text elements via `.font()` modifiers — never fixed point sizes for body text.

### 4.1 Scale

| Role | SwiftUI modifier | Weight | Notes |
|---|---|---|---|
| Page title | `.title2` | `.bold` | Tab root titles |
| Section label | `.caption` uppercase | `.semibold` | Group headers |
| Card title | `.subheadline` | `.semibold` | Session name, exercise name |
| Body | `.subheadline` | `.medium` | Primary readable text |
| Label | `.footnote` | `.medium` | Form labels, metadata |
| Caption | `.caption` | — | Timestamps, secondary info |
| Micro | `.caption2` | `.semibold` | Badges, pills |
| Mono (load specs) | `.caption.monospaced()` | — | "5×5 @ 85%" load strings |

**What a row is about is never a caption.** A row's subject — a lift, a modality, a
phase, a change line — is `.subheadline` (or the system's `.body` inside a `List`);
`.caption` is for what qualifies it. Nothing scales below `.caption2`, 11 pt at the
default size and Apple's minimum: no `minimumScaleFactor` that takes it lower (truncate
instead) and no `.system(size:)` for text or the glyphs beside it. `.tertiary` is for
chevrons and placeholders, never text someone has to read — on dark it is too faint
for 11–12 pt. Program ▸ Overview had all four until 2026-10-17 (§6.26).

**The sizes the text styles do not have are `AppFont`** (`AppTheme.swift`); a view never
writes `.system(size:` (`DesignTokenTests`; there were 23, some at 8–10 pt, until 1.35).

| Token | What | Use |
|---|---|---|
| `AppFont.hero(_:)` | rounded bold, monospaced digits, 72 pt by default | The one number a screen is about: the player's clock, a rest countdown |
| `AppFont.metric` | `.largeTitle` rounded bold, monospaced digits; scales | A card's lead number: readiness, a score |
| `AppFont.symbol(_:)` | 48 pt by default | A symbol standing alone as an illustration: an empty state, a result |
| `AppFont.micro` / `microStrong` | `.caption2` | The smallest text set: a chart's tick, a chip's label |
| `AppFont.mono` | `.caption2` monospaced | A log line, an identifier |

### 4.2 Color Hierarchy

Three levels of prominence via color, not weight alone:

```swift
Text("Back Squat")           // Primary: .primary
    .font(.subheadline).fontWeight(.semibold)

Text("5×5 @ 100 kg")        // Accent: AppColor.accent — load specs
    .font(.caption.monospaced())
    .foregroundStyle(AppColor.accent)

Text("Linear progression")   // Secondary: .secondary
    .font(.caption)
    .foregroundStyle(.secondary)
```

### 4.3 Truncation

Always use `.lineLimit(1)` or `.lineLimit(2)` on text that may overflow. Never let text break layout on narrow phone widths.

```swift
Text(session.archetypeName)
    .font(.subheadline).fontWeight(.semibold)
    .lineLimit(1)
    .truncationMode(.tail)
```

---

## 5. Spacing & Layout

All values in points (pt). 1pt = 1px at 1× scale.

### 5.1 Internal Component Padding

| Component | Padding |
|---|---|
| Standard card | `16pt` all sides |
| Compact card (session card) | `12pt` all sides |
| Exercise row | `12pt` vertical, `16pt` horizontal |
| Badge | `8pt` horizontal, `3pt` vertical |
| Button (primary) | `16pt` horizontal, `12pt` vertical |
| Sheet header | `16pt` all sides |
| Page content | `16pt` horizontal |

### 5.2 Gap / Spacing Scale

`AppMetrics` (`AppAnimationSettings.swift`); a view takes a step of the scale.

| Token | Value | Use |
|---|---|---|
| `gapTight` | `4pt` | An icon and its label, a title and its caption |
| `gapSmall` | `8pt` | Rows inside a card, chips in a row |
| `gapMedium` | `12pt` | Cards in a stack; a compact card's padding (`cardPaddingCompact`) |
| `gapLarge` | `16pt` | The page's margin; a card's padding (`cardPadding`) |
| `gapSection` | `24pt` | Between a screen's sections |

`minTapTarget` is 44 pt (§8).

### 5.3 Corner Radius

| Token | Value | Use |
|---|---|---|
| `radiusChip` | `6pt` | A chip, a badge, a bar |
| `radiusControl` | `10pt` | A field, a small button, a thumbnail, a selection tile |
| `radiusRow` | `12pt` | A row that stands alone, a card inside a card |
| `radiusCard` | `16pt` | A card (`.appCard()`), always continuous |
| `Capsule()` | — | Badges, modality pills, toggle-style buttons |

**Rule:** Nested elements use the same or smaller radius than their parent. **A card is
16.** Until 1.35 Analytics cards were 16, Today's and Program's hand-built ones 12 and 14
and Profile's 10; every card is now `.appCard()` or `AppCard` (§6.15).

---

## 6. Component Patterns

### 6.1 Session Card

The sample shows the anatomy; the cards that ship are Today's (`TodayView`) and the
calendar's rows, on `.appCard()`, with `SessionIcon` (§6.40) leading and the actions of
§6.43. `color` is `ModalityStyle.color(for:)`.

```swift
struct SessionCard: View {
    let session: WatchSession
    let style: ModalityStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Modality color bar — 2pt stripe, full width
            Rectangle()
                .fill(color)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 8) {
                // Header row: icon + name + duration pill
                HStack {
                    Image(systemName: style.icon)
                        .foregroundStyle(color)
                        .font(.subheadline)
                    Text(session.archetypeName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.estimatedMinutes) min")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(AppColor.surfaceRaised)
                        .clipShape(Capsule())
                }

                // Modality badge
                ModalityBadge(style: style)
            }
        }
        .appCard(compact: true)
    }
}
```

### 6.2 Modality Badge

A tinted capsule is `TintCapsule` (`AppCard.swift`): the colour's `fill` behind its own
text. The sample is what it draws.

```swift
struct ModalityBadge: View {
    let style: ModalityStyle

    var body: some View {
        Text(style.label)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(AppColor.Opacity.fill))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(AppColor.Opacity.border), lineWidth: 1))
    }
}
```

### 6.3 Loading, Empty and Failed States

Every screen answers three questions before its content: is it still loading, did the
load fail, or is there nothing. One reading, `AppLoadPhase.resolve(hasContent:isLoading:error:)`
(`Views/AppStates.swift`, `AppLoadPhaseTests`): content on screen wins and is never
replaced by a reload or its failure; then a load in flight; then the failure; only a load
that finished and found nothing is empty. Until 1.36 a failed program load read "No
Program" with a Generate button, ten screens drew their own empty state, and
`AppState.programError` was read by no view.

```swift
switch AppLoadPhase.resolve(hasContent: !appState.programHistory.isEmpty,
                            isLoading: appState.isLoadingHistory,
                            error: appState.historyError) {
case .content: list
case .loading: AppLoadingState(shape: .list, label: "Loading history")
case .failed(let message): AppFailedState(message: message) { await appState.loadProgramHistory() }
case .empty:
    AppEmptyState(icon: "clock.arrow.circlepath", title: "No history yet",
                  message: "Your programs are recorded from the moment you first open or save one.")
}
```

| View | When | Notes |
|---|---|---|
| `AppLoadingState` | first load, nothing to show yet | §7.3; `.cards` or `.list`; VoiceOver reads its `label` |
| `AppEmptyState` | the load finished and found nothing | a `ContentUnavailableView`; always the way forward when there is one — `prominent: true` (§6.6 `.primary`) only when it is the screen's one action (no program) |
| `AppFailedState` | the load failed and there is nothing to show | the server's or the system's message, "Try again" |
| `AppErrorBanner` | a reload failed while content is on screen | one warning-tinted row above the content, never in its place (Profile, Analytics ▸ Recovery) |

A new load in `AppState` publishes its failure (`historyError`, `workoutsError`,
`profileError`, `readinessError`, beside the older `programError`, `linkingError`,
`programAnalyticsError`, `developmentError`), ignores `URLError.cancelled`, and keeps what
it had. Analytics ▸ Load keeps its own answer: on a failed request it shows the phone's
figures and says so (`onDeviceMark`).

Inside a card, where the full view is too large, an empty chart is a `.title2` symbol
over one `.footnote` line — never a fixed point size. Spinners remain only for an action
in flight (a button, a sheet's save).

### 6.4 Section Header

Uppercase caption labels above groups of content — same pattern as the web's section
labels. One component, `SectionLabel` (`AppCard.swift`); `inset: false` when the parent
already pads. Today drew its own until 1.35.

```swift
SectionLabel("This week")
```

### 6.5 Load Prescription Text

Load specs are always monospace + amber. Makes them scannable at a glance.
The words come from one place: `LoadFormat.describe(_:)` (`LoadFormat.swift`)
turns an assignment into "3×5 @ 80 kg" / "45 min · Z2" / "AMRAP 12 min" for
the session sheet, the swap sheet and the exercise reference alike; never
re-derive the string at a call site.

```swift
Text(exercise.loadDescription)
    .font(.caption.monospaced())
    .foregroundStyle(AppColor.accent)
```

### 6.6 Buttons

One family, `.appButton(_:)` (`AppCard.swift`), so a button's weight says what it does on
every screen. A view never picks `.buttonStyle(.bordered…)` itself (`DesignTokenTests`;
93 did until 1.35, and Workout complete drew its own).

| Kind | Looks | Use |
|---|---|---|
| `.primary` | filled with the tint | The one action a screen or bar is for |
| `.secondary` | tinted, bordered | What stands beside it |
| `.destructive` | bordered, red | Removes something |
| `.complete` | filled emerald | Marks done: a session, a set, a confirmed link |

```swift
Button("Start workout") { … }.appButton(.primary)
```

A plain text button (a toolbar item, an inline link) takes the tint and no style.

Inside an action bar or `AppFloatingControls` (§6.47) the same four kinds draw in glass;
the call site does not change, and no view names a glass style itself (`DesignTokenTests`).

### 6.7 Deload Banner

```swift
HStack(spacing: 8) {
    Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(Color(TrainingPhase.deload.color))
    Text("Deload week — quality over load")
        .font(.footnote).fontWeight(.medium)
}
.padding(12)
.frame(maxWidth: .infinity, alignment: .leading)
.background(Color(TrainingPhase.deload.color).opacity(AppColor.Opacity.fill))
.clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusControl))
.overlay(RoundedRectangle(cornerRadius: AppMetrics.radiusControl)
    .stroke(Color(TrainingPhase.deload.color).opacity(AppColor.Opacity.border), lineWidth: 1))
```

### 6.8 Sub-Tab Selector

**When a screen divides into sections, there is exactly one way to do it.**

Analytics and Profile each grew their own: Analytics a native segmented
`Picker` with haptics and a swipeable paged `TabView`; Profile a hand-rolled
scrolling row of bordered, icon-bearing pills with neither. Same job, two
languages, and nothing stopping the next screen from inventing a third. Both
now use `AppSubTabs.swift`.

Conform the section enum to `AppSubTab` and wrap the sections in
`AppSubTabScreen`, which pins the selector under the navigation bar (a
`safeAreaInset` that follows a pull-to-refresh) and shows the selected section
beneath it:

```swift
private enum ProfileTab: Int, AppSubTab {
    case athlete, equipment, schedule, standards

    var label: String {
        switch self {
        case .athlete:    return "Athlete"
        case .equipment:  return "Equipment"
        case .standards:  return "Standards"
        case .schedule:   return "Schedule"
        }
    }
}

AppSubTabScreen(selection: $selectedTab) { tab in
    switch tab {
    case .athlete:    AthleteTab()
    case .equipment:  EquipmentTab()
    case .standards:  StandardsTab()
    case .schedule:   ScheduleTab()
    }
}
.navigationTitle("Profile")
.appTabStyle()
```

**Rules**

- **Use the native segmented control.** It inherits system styling, Dynamic
  Type and VoiceOver. A custom pill row has to reimplement all three, and the
  one we had reimplemented none of them.
- **Labels are words, not icons.** A segmented control divides the width
  evenly and truncates what does not fit; an icon adds nothing a word does not
  already say. Prefer one word per section.
- **Two to five sections.** One is not a choice. Beyond five the labels
  truncate on the narrowest iPhone — split the screen or push a level of
  navigation instead of shrinking the text.
- **Every tab's large title collapses on scroll**, as Today's does — the
  system behaviour (Health, Fitness, Music) — and the selector rides up under
  the inline title. Two things keep it working. The navigation bar must see
  the section's own scroll view, so the content is the selected section
  alone: until 2026-10-15 it was a paged `TabView`, which hid the scroll
  view and left four tabs' titles pinned while Today's collapsed. Sections
  are no longer swiped between; the selector is the way to move. And a
  section puts anything above its rows *inside* its list or scroll view (a
  header), never in a `VStack` above it — Log ▸ Activity's scope line is the
  list's section header. A section chosen in `onAppear` (a deep link) swaps
  the scroll view while the screen is still appearing and left the title
  blurred, so screens apply a requested section in `.task`, after the first
  frame.
- **The selector follows the title on a pull.** It is a `safeAreaInset`
  offset by the section's overscroll (`onScrollGeometryChange`), so a
  pull-to-refresh moves title and selector down together as Today's header
  moves, and on a scroll it stays pinned under the inline title. Three
  placements failed (2026-10-15): a `safeAreaBar` left List sections' titles
  blurred at rest; a plain inset stayed put while a pull slid the large title
  down *beneath* it; and the bar's `largeSubtitle` slot (shipped in 1.1.1)
  takes no touches when the section is a List or Form — every Log and
  Profile section — whatever the list style, wrapper or control. Check a
  placement with taps on a List section *and* a ScrollView section, and a
  gesture change with a real drag, not by reasoning. The `safeAreaBar` was
  tried again on the 26.2 SDK for 1.37 and still blurs the large title with
  nothing scrolled; the inset stays.
- **A section is rebuilt on every switch** (`.id(selection)`), so it starts at
  the top. Keeping visited sections alive and hidden was tried on 2026-10-15
  and dropped: the navigation bar's tracking of the visible one could not be
  verified. What the rebuild used to cost — every section's `.task`
  refetching — is gone: a section's load goes through
  `AppState.loadIfStale(key)`, which runs once per program revision and per
  full load (launch, pull-to-refresh, foreground refresh). A pull-to-refresh
  inside a section calls its loader directly.
- **Selection is always haptic** (`AppHaptics.selection()`), wired into
  `AppSubTabPicker` so no call site has to remember.
- **No `Divider()` under the selector.** The segmented control already reads
  as a discrete band; a rule beneath it doubles the boundary.
- Spacing is fixed in the component — `.padding(.horizontal)` and
  `.padding(.vertical, 8)`. Do not re-pad at the call site.

**When NOT to use it**

This pattern is for *screen-level* sub-navigation: dividing a whole tab into
sections. A segmented control that switches a **mode or filter inside content**
— Map/3D on a workout map, Browse/Generate in a sheet — is a different thing
and stays a plain `Picker`. The test: does it change what the screen *is*
about, or just how the thing in front of you is displayed? Only the former is
a sub-tab.

---

### 6.9 Cross-Tab Navigation

**A screen never reaches into another screen's state.** It asks the router.

Tab selection lives in `AppRouter` (`AppRouter.swift`), injected once by
`ContentView` and read by `MainTabView` as the `TabView` selection. It was
`@State` in `ContentView` before, which meant `ContentView` was the only thing
that could move the user — a card on the Dashboard had nowhere to send a tap.

```swift
@EnvironmentObject var router: AppRouter

Button {
    router.showAnalytics(.recovery)   // Dashboard readiness card → Analytics ▸ Recovery
} label: {
    readinessCard
}
.buttonStyle(.plain)
.accessibilityHint("Opens Analytics, Recovery")
```

**Rules**

- **Route through the methods**, not by assigning `router.tab` at a call site.
  The haptic and the order of the two writes (section first, then tab) belong
  to the router — the same reason haptics live inside `AppSubTabPicker`.
- **A requested sub-tab is a one-shot.** `showAnalytics(_:)` sets
  `analyticsSection`; Analytics applies it and calls `clearAnalyticsSection()`.
  Leaving it set would drag the user back to Recovery every time they returned
  to the tab, overriding the section they chose themselves.
- **Consume it in `onAppear` *and* `onChange`.** The router may name a section
  before the destination view exists (first visit — `onAppear` catches it) or
  while it is already on screen (`onChange`). One alone leaves a dead tap.
- **A card that navigates says so**: trailing `chevron.right`, `.caption`,
  `.tertiary` — the same affordance as §6.1's session card and the progression
  card. Wrap the card in a `Button` with `.buttonStyle(.plain)` (or a
  `NavigationLink` when it pushes within the tab) so the whole card is the
  target, and give it an `.accessibilityHint` naming the destination.

**When NOT to use it**

Pushing *within* a tab is still `NavigationLink` — the router is for crossing
between tabs. And a sub-tab is only worth naming in the router if some other
screen actually sends the user there; do not pre-declare routes nothing uses.

---

### 6.10 Workout Route & Charts

**The recorded shape of a workout: where it went, and what the sensors saw.**
`WorkoutTimeseriesSection.swift` — `WorkoutRouteSection` and
`WorkoutChartsSection`.

Two screens drew this independently and had already drifted: the workout detail
offered a Swiss 3D toggle and the session-log detail did not, and they disagreed
on how many GPS points make a pace chart (10 vs 1). Both now use these.

```swift
WorkoutRouteSection(points: detail.gpsTrack ?? [])
WorkoutChartsSection(workout: detail, hrConfig: appState.profile.hrConfig)
```

**Rules**

- **Absent data renders nothing** — not an empty frame. No track, no Route
  section; no series, no chart section. A reserved 160pt box with nothing in it
  reads as a loading failure.
- **The selected chart is derived, never assumed.** `WorkoutChartsSection` holds
  a `ChartKind?` and normalises it into whatever the data supports. The previous
  form — an `Int` defaulting to `0` (HR) — let a workout with elevation but no
  HR select a chart that did not exist, and that bug had already been copied
  into the second screen. Prefer making a bad state unrepresentable over fixing
  it in each copy.
- **One scrubber for all three** (since 1.39). Each chart takes `scrub:
  Binding<Double?>` — seconds from the start — and draws a rule there
  (`chartXSelection`); the section owns the value, so it stays put from HR to
  pace. The line above the chart reads the moment in every series
  (`WorkoutScrub.readout`: "12:30 · 142 bpm · 5:12 /km · 412 m"; a value only
  when one was recorded within a minute, so a pause reads as nothing), and says
  "Drag across the chart to read a moment" until the first touch. Pure, in
  `WorkoutScrubTests`. No chart could be read before.
- **Availability thresholds live in the component**: HR needs one sample,
  elevation one point with an altitude, pace ten points moving faster than
  0.3 m/s — enough to draw a line, not a dot.
- **Pass the re-fetched workout, not the list row.** List payloads omit
  `gpsTrack` and `heartRate.samples` deliberately (a long run carries 16k GPS
  points); the detail re-fetches with `APIClient.fetchWorkout(id:)`.
- The Swiss 3D toggle appears only inside the Swiss bounding box
  (`isInSwitzerland`), and the map mode is the component's own state.

**When NOT to use it**

This is for a stored workout's recorded timeseries. A live, in-progress session
is a different component with different needs — don't stretch this one to cover
it.

### 6.11 Period Filter

**One control for "over what period".** `AnalyticsPeriodPicker.swift`.

```swift
AnalyticsPeriodPicker(period: $period)
```

`period` is shared across the Analytics sub-tabs, but its only control used to
be inline in Overview — so the Workouts list was silently filtered by a choice
made on a different screen, while its own empty state advised "try a longer
period" and offered no way to do it.

**Rules**

- **Render it on every tab that filters by it.** Shared state with a control on
  one screen only is a filter the user cannot see or reach.
- **The haptic and the animation are inside the component** (`AppHaptics.selection()`,
  `AppAnimation.springSnappy`); call sites pass a binding and nothing else. So is
  the 44 pt target around each capsule and the selected trait VoiceOver reads.
- Give it its own line — do not fold it into a horizontal scroller of sort and
  filter pills, where it reads as one more chip rather than the scope of
  everything below.
- **A list with several filters takes them into one menu** (§6.24): Log ▸
  Workouts sets its period in the toolbar's filter menu, and its scope line
  ("4 workouts · Last 30 Days") keeps the period on screen.

**When NOT to use it**

It is not an `AppSubTabs` selector, and must not become one. By §6.8's own test
it changes *how the thing in front of you is displayed*, not what the screen is
about. It also does not belong above `AppSubTabPicker`: Recovery ignores period,
and a control that does nothing on the tab you are looking at is worse than one
you have to find.

---

### 6.12 Activity vs Modality Icons

**Two different questions, two different answers.** `ActivityIcon` in
`ModalityStyle.swift`.

- `ModalityStyle.icon(for:)` answers *what kind of training is this* — the
  planned modality. `aerobic_base` is a runner.
- `ActivityIcon.forActivityType(_:)` answers *what did the device record* —
  cycling is a bike, swimming is a swimmer.

Conflating them put a runner on every cycling row: a ride is filed under
`aerobic_base`, so a list keyed off modality showed a runner while the detail
page, keyed off activity type, showed a bike. Four screens had each written
their own copy of the activity mapping and only two of them knew that "bike"
means cycling.

```swift
// An imported workout: what was recorded, falling back to how it was filed.
Image(systemName: ActivityIcon.forWorkout(activityType: workout.activityType,
                                          modalityId: workout.inferredModalityId))
    .foregroundStyle(ModalityStyle.color(for: modality))
```

**Rules**

- **A recorded workout leads with its activity.** Use
  `ActivityIcon.forWorkout(activityType:modalityId:)`, which falls back to the
  modality only when the activity string names nothing specific ("Workout",
  `watch_16-Saturday-0`).
- **What SF Symbols lacks, the app draws.** There is no kettlebell glyph
  (checked against the iOS 26.3 runtime's 9,184 names), so
  `kettlebell.symbolset` is a custom SF Symbol written by
  `ios/tools/make_kettlebell_symbol.py`. How to make another in the same
  style — when, the drawing rules, the preview, the wiring — is
  `ios/docs/custom-icons.md`. A custom name must be drawn with
  `Image(symbol:)`, which sends `AppSymbol.custom` names to the asset
  catalog — `Image(systemName:)` draws nothing for them
  (`ActivityIconTests` loads each from the catalog).
- **Match whole words.** The watch records a session's archetype name as
  its activity type, so substring matching read "KB Movement Skill" as
  skiing and "Box Step-Ups" as boxing. Kettlebell sessions (`kb`,
  `kettlebell`) are `AppSymbol.kettlebell`. Names are shown
  through `ImportedWorkout.activityLabel`, which title-cases device
  identifiers and leaves a written name ("KB …", "(ME)") alone.
- **Colour still comes from the modality.** The icon says what you did; the
  colour says where it sits in the training palette. Keeping the colour on
  `ModalityStyle` is what lets a list stay readable when every row is a bike.
- **A planned session leads with its workout icon** — the third question,
  *what is in it* (§6.40): `SessionIcon.symbol(icon:modality:)`, which is the
  server's `icon` for its main exercise, else `ModalityStyle.icon(for:)`. A
  workout linked to a session takes that session's icon in Log ▸ Linking, so
  the pair reads as one.

**When NOT to use it**

Not for archetypes, philosophies or the builder's modality lists: those have a
modality and no session, so the modality icon is the correct and only answer.

---

### 6.13 Tab Structure

**Five tabs, and configuration is not one of them.**

| Tab | Root | Sections (`AppSubTabs`) |
|---|---|---|
| **Today** | `Views/Today/TodayView` | — (the day's sessions, what waits for an answer, three tiles — §6.53) |
| **Program** | `ProgramView` | Overview · Calendar · History |
| **Analytics** | `AnalyticsView` | Progress · Blocks · Load · Recovery |
| **Log** | `LogView` | Activity · Linking |
| **Profile** | `ProfileView` | Athlete (incl. injuries and HR zones) · Equipment · Schedule · Standards |

The section names and their order are the web's, item for item
(`docs/information-architecture.md` §2): a section is renamed or moved on
both clients in the same change. Program's Current became Calendar and
gained Overview (`ProgramOverviewTab`: methodology, phases, priority mix),
and Analytics' Overview became Load, on 2026-10-13. Every section is a
deep link — `program?section=`, `analytics?section=` (`overview` and
`development` are kept as aliases), `log?section=`, `profile?section=`.

`AppRouter.Tab` enumerates them; `MainTabView` in `ContentView.swift` reads the
selection from the router (§6.9). The bar is the system's (`Tab(_:systemImage:value:)`):
it shrinks on a scroll down (`tabBarMinimizeBehavior(.onScrollDown)`) and carries the
kept workout as its bottom accessory (§6.45). The first case is still named `.dashboard`
because the widgets deep-link to it; its label is "Today".

**Settings is pushed from Profile's toolbar gear** (`Views/SettingsView.swift`),
in this order: Connections (integration toggles), Devices & Sync (pairing, Sync
Now, last sync), Workout (the player's cues), Notifications (local session
reminders — `NotificationManager.swift`, rescheduled from the stored program on
every program change), Appearance, Account (sign out), and last one
**Diagnostics** row that pushes what the athlete never needs: when each sync
last ran, the API target (the switch in debug builds) and the debug log. Until
1.39 those three sat among the settings. Until
2026-10-01 these lived on a fifth "Sync" tab — a debug screen that held the
only sign-out, the integration switches and a hidden program mutation. A tab
is a place the athlete goes every day; a setting is something they change once.

**Rules**

- A new top-level destination needs a case in `AppRouter.Tab` and a `show…`
  method on the router; nothing else moves the user between tabs (§6.9).
- Sections within a tab use `AppSubTabs` (§6.8), two to five of them.
- Developer diagnostics (sync log, device status) live under Settings ▸ Devices
  & Sync, never on a tab.
- The web app's layout is the same journey with a sidebar
  (`docs/information-architecture.md`): Home / Program / Log / Analytics /
  Explore / Profile. The phone's Log tab (§6.19) is the same area as the
  web's: the record (recorded workouts, with the `.fit` importer), the
  decision queue (the suggestions inbox) and what was logged against planned
  sessions. Logging itself stays on the session (§6.16).

---

### 6.14 Exercise Detail Sheet

**The phone's exercise reference.** `Views/ExerciseDetailSheet.swift` — what a
movement is, how to do it, what it needs and what it leads to: category and
effort chips, movement patterns, the package's demo (`GET
/api/exercises/<id>/media`, a GIF rendered with `AsyncImage`; the source link
opens Safari), description, coaching focus, cues, common errors, and from the
catalog (`GET /api/exercises`, cached in `AppState.exerciseCatalog`) the
equipment, prerequisites and unlocks with ids resolved to names. When opened
from a prescription it shows that session's load (§6.5) and notes first.

```swift
// Inside a sheet that owns a NavigationStack: a push (§6.48).
.appPush(item: $exerciseSheet) { item in
    ExerciseDetailSheet(exerciseId: ex.id, name: ex.name, assignment: item.assignment, pushed: true)
}
```

`pushed: true` drops the sheet's own `NavigationStack` and Done button; without it the
screen is a sheet in its own right (from Analytics ▸ Progress). `SwapExerciseSheet` takes
the same flag.

**Who presents it**

- A planned session's exercise rows (`SessionDetailView`) — tap. The row
  carries a tertiary `info.circle` so the tap has an affordance, and the same
  row's context menu and trailing swipe offer **Swap** (`SwapExerciseSheet`,
  `POST /api/exercises/substitute`), which lists alternatives for the same
  slot with their load for the week; each alternative's `info.circle` opens
  this sheet too.
- Nothing else yet. Workout detail shows what was recorded, not a
  prescription; the builder's step 1 is about methodologies, not movements.

**Rules**

- Every field is optional and the sheet renders whatever the package ships;
  an exercise with no media still shows its catalog entry. Never block on the
  media request.
- The sheet is a reference, not an editor: no logging, no swapping from
  inside it. Swap lives on the row that owns the slot.
- It is the component the roadmap's "iOS Library tab" would promote; a
  Library tab is not worth adding until there is more than this to put in it.

### 6.15 Analytics Card, Status and the Program Section

**One card, one status vocabulary.** A card's status or source mark (a
verdict badge, "On device", a trend) goes in its `trailing:` slot, never in a
content row; nothing inside a card draws a box of its own (the coverage notice
lost its dashed border, Last Night its stage tiles, HRV and resting HR their
second title, 2026-10-17); every capsule is `TintCapsule`. `AppCard.swift` holds `AppCard` (`AppCard` until 1.35, when Today, Program and Profile took it too; `.appCard(compact:border:tint:)` is its surface alone, for a card with no header)
(uppercase caption header over content, secondary background, the app's card
radius, full width; an optional `trailing:` view beside the header for a
status badge, so a verdict never takes a row of its own). Every Analytics
section is a column of them, 16 pt apart — Progress too since 2026-10-16,
when its bordered score card, headers outside cards and cards inside cards
were replaced: Score, a card per methodology and per measure, Standards,
Exercises (rows divided, not nested cards), Recommendations, Suggested
adjustments; Overview and Recovery each carried a private copy until the Program
section became the third user. `AnalyticsStatus.swift` holds
`AnalyticsStatusStyle` — the engine's statuses folded onto green / yellow /
red / neutral and put into words, the same mapping as the web's
`components/analytics/status.ts` — `AnalyticsStatusBadge` (the capsule), and
the coverage reason copy. `AnalyticsProgressTab` reads its colours from it.

**Analytics ▸ Progress** (`Views/AnalyticsProgressTab.swift`) lays out the
server's `GET /api/analytics/program` document (`ProgramAnalyticsModels.swift`,
every section decoded on its own so a failed or future section cannot blank the
screen) and the progression review. Program and Progress were two sections
until 2026-10-23; the sections, titles and order are the web's
(`components/analytics/ProgressTab.tsx`):

- *Program*: the program header (§6.28) with plan fidelity as its footer —
  each field actual / ideal with a mark.
- *Score* (§6.25): the review's score, its band and the completion beside it.
- *Progress* — the one chart (§6.41): every exercise, each metric done
  against prescribed, and each methodology measure against its expectation.
- A section per methodology (`MethodologySectionView`,
  `Views/AnalyticsProgramSections.swift`): its name as a `SectionLabel`
  (§6.37), then one card of `MeasureRow`s, headline first — the name and the
  status badge on one line, where the measure stands in its own currency and
  its trend under it (side by side when they fit), the `CoverageNoticeView`
  when nothing measures it yet. Tapping a row draws it on the chart (the row
  tints, with an accent bar) and scrolls to it; the chevron pushes
  `MeasureDetailView` (§6.37): each exercise's status and stall, every movement
  and standard (each opens its sheet), the evidence and the About section. The
  rows were cards with a sparkline, and the detail had its own chart, until
  2026-10-23. Entries the program does not schedule fold behind one "N not in
  this program" row.
- *Scorecard*: the headline gate (`on_plan` / `off_plan` / `not_started`), a
  row per modality with completion against the plan to date and the weekly
  dose against the framework's range.
- *Intensity split*: a row per HR zone, Z1–Z5 each on its own (strength
  sessions are load, not heart rate, and are not a zone): the minutes the **completed** sessions planned in it (each
  slot's prescribed time in the zone its `intensity` names, from the server's
  `intensity.zones`) as an outline, the minutes their heart rate recorded
  filled over it, "recorded/planned min" beside it. A zone shows only when it
  has either. An older server sends no `zones`; the card then draws minutes per
  bucket per week. % of 1RM for max-effort frameworks.
- *Standards* (`ProgramStandardsCard`): the program's own — those it tests and
  those a lift it schedules estimates (the server's rule, `program_standards`);
  "More standards" went on 2026-10-23, and a button sends the athlete to
  Profile ▸ Standards for the rest. Per standard the modality's symbol and the
  name, the value as the server prints it, a chevron, the level badge and the
  gap on a second line, and the block's `Sparkline`. A row presents
  `StandardDetailSheet` in place (§6.32).
- *Workouts* (`SessionShapesCard`, a summary; "Session shapes" until
  2026-10-23): done of scheduled across every workout, how many ran past
  ±25 % of their estimate, and the first three. `SessionShapesDetailView`
  lists every workout with its duration against the archetype's estimate
  (amber past ±25 %), HR and the lead lift's est. 1RM.
- *Load* (TSB read in the phase's terms), then Recommendations and Suggested
  adjustments.
- *Movement* is parked: the server still builds it and `open=movement` still
  pushes `MovementDetailView`, but the section shows no card.

Rules: nothing is computed on the phone; the chart's two colours are the
web's; a status the engine adds later shows neutral, never a missing style.
The section reloads when the stored program's revision changes and on
pull-to-refresh (`fresh=1` forces the server to recompute).

---

### 6.16 Session Logging

**Log what you did on the session it belongs to.** `Views/ExerciseLogSheet.swift`,
reached from a session row's leading swipe ("Log") or its context menu. The
sheet dispatches on the slot type through `SessionLogging` (the phone's copy
of the web's `lib/outcomeFields.ts`): a sets × reps or hold slot gets one row
per set — reps or seconds, kg, RPE, done — prefilled from the prescription or
from what was logged before; every other slot gets its currency fields
(rounds, minutes, kilometres, reps). Two rules on the exercise, the web's
too: a kettlebell in a timed slot logs reps beside minutes (cadence), and an
isometric in a skill-practice slot logs the hold in seconds; both land on
the first set, where the rate and hold primitives read them. Saving goes through
`AppState.logExercise`, which writes `{exercises: {<id>: …}}` to
`PUT /health/sessions/<key>`; the server merges per exercise and keeps the
completion, notes and fatigue it already has, so logging before or after
"Mark Session Complete" is the same. The row then shows "Logged: 3 sets · 3×5
@ 80 kg" in green under the prescription.

`ExercisePerformanceLog` is the web's `ExercisePerformance`
(`sets[].setIndex/repsActual/weightKg/rpe/completed/durationSeconds`,
`rounds`, `durationSec`, `distanceKm`) — the keys `progression_tracker.py`
and the analytics primitives read. `GET /health/sessions/recent` carries
`exercises` so the phone reads back what any client logged. The watch keeps
its own set logger (digital crown) and writes the same shape, with each
set's `durationSeconds` from its start to the moment the logger opens.

Rules: never log into a different session than the one on screen; the sheet
is the one place sets are entered on the phone; a logged row never changes
the prescription.

---

### 6.17 Regenerate Offer

**A changed profile offers to rebuild the plan only when the change moves
something.** `Views/RegenerateOfferCard.swift` sits at the top of the Athlete
(which holds injuries), Equipment and Schedule tabs while
`AppState.showsRegenerateOffer` — a difference from `ProgramConstraintsDiff`
(the phone's copy of the web's `lib/programConstraintsDiff.ts`: level,
equipment without `open_space`, days per week, injuries against the program's
`constraints`), or the word that the last one changed nothing. The card waits
1.5 s after the last toggle ("Checking whether this changes your program…"),
then `AppState.checkConstraintChange` asks `POST /programs/constraint-change`,
which builds the rest of the program with the program's constraints and the
profile's and compares them:

- **Unaffected** — the program is what the new settings would build:
  `adoptProfileConstraints` records them on it (`PATCH /user/program/constraints`)
  and the card says "Your program doesn't change with these settings". No offer.
  Adding a kettlebell no session uses used to ask for a rebuild.
- **Affected** — "These settings change 18 sessions from week 1", the
  differences and **Preview changes** (Program ▸ Preview in regenerate mode,
  the days already behind the athlete as planned and the moved sessions marked,
  §6.39). Only the preview's **Apply from week N** saves
  (`applyRegeneratedTail`: the tail spliced onto the weeks and days already
  behind the athlete, through the revision-checked PUT); the card no longer
  applies on its own.
- **Refused** — "These settings can't build the rest of your program", the
  engine's reason and **See why** (the preview's "What would let it build").
- **Not comparable or the check failed** — the old "built for different
  settings" wording, and Preview changes generates the tail for the preview.

After Apply the difference is gone, and with it the reason the card was shown;
`AppState.profileOfferOutcome` (`.applied(weeks:)` / `.adopted`) keeps the
card on screen to say "Rebuilt N weeks with these settings" or "doesn't
change", until a new difference starts over.

Rules: the comparison is the server's, never a per-screen heuristic; the card
appears only where a constraint is edited; a blend regenerates as a blend
(`philosophy_ids` + weights); the card is a `VStack`, not a `Group` — a Group
hands `.task` to each child, and switching from "Checking…" to the card
restarted the check in a loop.

---

### 6.18 Methodology Sheet

**The program explains itself.** `Views/PhilosophyDetailSheet.swift` — a
methodology's summary, emphasis (modalities), core principles and how it
trains (intensity model, progression philosophy). Three presenters: the
builder's philosophy cards (step 1) and the book on the program header
card (§6.28) on Program ▸ Overview and Analytics ▸ Progress; a blend turns
the book into a menu with one entry per source
(`AppState.programMethodologies()`). It was private to
the builder until 2026-10-01, which left the plan the athlete was on with no
way to say what it was for — the web's equivalent is the Program overview's
link into Explore.

The sheet also lists the methodology's tracks, each with its phases and
their descriptions (§6.22).

Rules: the row reads the envelope's `sourceGoalIds`, never the builder's
selection; the sheet is the one methodology reference on the phone.

---

### 6.19 Log Tab

**The record and the decision queue, apart from the interpretation.**
`Views/LogView.swift`, the fourth tab (after Analytics since 2026-10-16), two sections:

- *Activity* (`LogActivityTab`): recorded activities (`WorkoutRow`, §6.23)
  and what was logged against planned sessions, in one list by date
  (`WorkoutListFilter.entries`). They were the Workouts and Sessions
  sections until 2026-10-20 (and Workouts was Analytics ▸ Workouts until
  2026-10-01). Show (All · Workouts · Sessions), period, sort and activity
  are the toolbar's filter menu (§6.24) beside the `.fit` importer; another
  sort than date leads with the workouts in that order, an activity keeps
  workouts only. A workout swipes to delete, carries the TRIMP badge and
  pushes `WorkoutDetailView`; a session row reads as `LogSessions.rows`
  builds it (below) and opens the session detail when it resolves.
- *Linking* (`LogLinkingTab`): one section per day, the workouts recorded
  that day beside the sessions planned for it — the current program's and
  every earlier program's, the header naming the program and marking an
  earlier one. A day holds its links (a check; swipe to unlink), same-day
  suggestions with Link and Not this, and the workouts and sessions still
  free. Linking across days is Link… on a workout, then Link here on any
  session — the phone's form of the web's drag. The days are built on the
  server (`GET /health/linking`, `src/linking.py`, the copy of the web's
  `lib/linking.ts`), since the phone has no matcher; every link sends the
  session's `sessionUid`, and one into an earlier program only links — its
  key would tick this program's session of that name. "Not this" is kept on
  the phone and sent with each request (`Linking`, `LinkingTests`). A link,
  an unlink or a "Not this" changes the list at once (`Linking.applying…`)
  and the server's reload, a couple of seconds, replaces it; the list is
  never disabled while it runs — doing so froze scrolling and every button
  until the reload landed, which read as a hung screen. Today
  still shows the server's own suggestions (`SuggestionRowView`).
- A session row of Activity: what was logged against a planned session —
  `LogSessions.rows` builds the rows from the server's session logs: the session's name when the key
  resolves in the current program, the date and source, and one line per
  exercise with content ("Back Squat — 3 sets · 3×5 @ 80 kg"). A row that
  resolves opens the session detail.

Analytics keeps Progress · Blocks · Load · Recovery: it
interprets, it no longer lists. `router.showLog(_:)` and
`trainingcompanion://log?section=…` name the sections (§6.9).

A log of an earlier program is named by the server (`planned_name`,
`planned_modality`, `planned_date`, `week_index`, `day_name` on
`GET /health/sessions/recent`, resolved through `planned_sessions`), so the
row reads "Heavy/Light/Medium · 25 Sep · earlier program · week 3 · Friday"
instead of "Session 3-Friday-0". The legacy key is program-relative and not
unique across versions — "3-Friday-0" exists in the current program too — so
a planned date before the current program's start overrides the key lookup:
the row keeps the earlier plan's name and does not open this program's
session of the same key (`LogSessionsTests`).

Rules: the record is listed once, here; Analytics never grows a list again;
a suggestion is decided here or on Today.

---

### 6.20 Blocks (Development Across Programs)

**Every block, not just this one.** `Views/AnalyticsDevelopmentTab.swift`,
the second Analytics section (Progress · Blocks · Load · Recovery). Progress is the current block measured against
what it is for; Blocks is how the athlete has developed across programs —
the question the history tables exist to answer. The server reads them as
one document (`GET /api/analytics/development`, `src/analytics/development.py`)
and the web's Analytics ▸ Development lays out the same one; nothing is
computed on the phone (`DevelopmentModels.swift` decodes it tolerantly,
section by section, like `ProgramAnalyticsModels`).

Four cards, each an `AppCard` (§6.15):

- *Blocks*: a strip across the top — each activation's share of the span in
  its colour — then a row per block: methodology names, span, weeks, sessions
  done of those the block reached (`checkmark.circle 3/10`; the percentage is
  VoiceOver's), "never reached" for the rest (`forward.end`), and a `current`
  `TintCapsule` on the active one. A row pushes `ProgramVersionDetailView`,
  the block week by week — the screen Program ▸ History opens (§6.37).
- *Lifts across blocks*: the series' name is the menu (`chevron.up.chevron.down`)
  of every lift and currency — rounds, minutes, km — with points in the window,
  each item with its block count; a name beside a menu showing the same name
  said it twice and wrapped (2026-10-18). The chart
  plots the heaviest completed set's est-1RM per session over real dates with
  the blocks as `RectangleMark` bands, deload points hollow, and a touch reads
  that session's set (`ChartPoint.detail`, "57.5 kg × 5"). Under it the trend
  as an arrow and %/session, and "By block", which pushes the per-block rows:
  first → last, best, sessions, Δ. Chips and the rows sat inline until
  2026-10-17.
- *TRIMP per week by block*: weekly TRIMP as bars coloured by block over the
  whole history (Load's card is the last 12 weeks), with a key naming each
  block; hidden when no workout carried load.
- *Standards over time*: per standard the name, the level badge and levels
  gained, a `Sparkline` of its results, the latest result and a chevron; a
  row presents the standard's sheet in place (§6.32), whose chart carries the
  blocks as bands. The current program's own first, the rest behind "More
  standards"; "Log a result" opens Profile ▸ Standards. Hidden when nothing is
  logged.

**Block colour is positional**: `DevelopmentAnalytics.palette` (indigo,
emerald, amber, pink, sky — the web's `BLOCK_PALETTE`) indexed by the
block's position in the timeline, so the strip, the bands, the bars and the
per-block rows agree. No history shows an empty state pointing at Program.

**The label is "Blocks", not "Development"**: five segments share the width
and the segmented control truncates "Development" to "Develop…" (§6.8). The
enum case is still `.development`; the deep link is
`trainingcompanion://analytics?section=blocks`; `router.showAnalytics(.development)`
from anywhere else (§6.9).

### 6.21 Readiness and Its Sources

**The card says the score; the screen says what it is made of.** Analytics ▸
Recovery's readiness card (an `AnalyticsDetailCard`, §6.37): the score in large
rounded type in its status colour, the status once as a `TintCapsule` beside
the header, the morning's readings as symbols and numbers
(`waveform.path.ecg 52 ms`, `heart.fill 48 bpm`, `moon.fill 7h 20m`), and the
server's flags as chips (`ReadinessFlagChips`: "RHR up 3d", "Recovery capped").
A coloured circle, the coloured score and a status word under it had said the
status three times.

`ReadinessDetailView` holds the rest: the score's **parts** against their
maxima as the server words them (`parts` on `GET /health/readiness`: resting
heart rate 35, HRV — or "Body Battery and recovery" when the watch stood in —
35, sleep, session fatigue and training load 10 each), "Capped by recovery time
left" when `cappedAt` says the watch's recovery hours lowered it, the watch's
Body Battery and recovery left, the readings, **Sources**, and About.

**Sources** is the one sentence that says where resting HR, HRV and sleep came
from — `ReadinessResult.sourceNote`, the phone's copy of the web's
`lib/readiness.readinessSourceNote`: components grouped by source, "Resting HR
from your Garmin watch's heart-rate low; HRV and sleep from Apple Health and
check-ins." Resting HR is scored from one series only
(`src/wellness.merge_for_scoring`), so the sentence is what explains a score
that moved because its source changed (`ReadinessSourceTests`). It sat under
the score on the card until 2026-10-17 — the one sentence §1.4 had tolerated
there. Today's card shows the score and the readings and nothing else.

Settings ▸ Devices shows the paired Connect IQ watch's last wellness reading
under the device rows (`WellnessReading.summary()`, the web Devices card's
line): the heart-rate low, the 7-day resting HR, Body Battery and recovery
time — never the watch profile's `resting_hr`, which is the zone setting.

---

### 6.22 Track Phase List and Start Phase Picker

**A methodology's phases read the same wherever they appear.**
`Views/TrackPhaseList.swift` draws one track: a proportional strip coloured by
kind (§3.2), then one row per phase with its own name, its length (marked
"repeatable" for a block meant to cycle) and its focus line. Three presenters:
the builder's track picker (step 2) and review (step 4), the Program settings
sheet under its Track picker, and the methodology sheet (§6.18), which passes
`showsDescriptions: true` to add each phase's description.

`StartPhasePicker` (in `Views/ProgramBuilder/BuilderConstraintsStep.swift`) picks where a program
starts from the chosen track's own phases; `nil` is the first phase. The
builder (step 3) and the settings sheet use it, and both disable it while an
event date is set, because the server then counts the phases back from the
event.

Rules: the phases come from `PhilosophyCard.tracks`, never from a hard-coded
list — the builder offered base/build/peak/taper for every methodology, and
sent them under a key the server never read. A request names the track
(`track_id`) and start phase (`start_phase`) by id; a tail regenerate takes
both from the week it starts at (`ProgramConstraintsDiff.merged`). A
methodology with one track shows it without a choice; a track with one phase
shows no start picker.

**Several tracks (a composition).** Picking two to four methodologies in step 1
makes a blend of tracks (`BuilderLane`, `ProgramComposition.swift`). Step 2 is
`LaneSections`: per track a `TrackChoiceRow` list (the same row the one-track
picker uses), a weight slider and "Add another <methodology> track"; step 3 a
`StartPhasePicker` per track; step 4 lists the tracks. The request sends
`lanes`. A composed program shows `CompositionTracks` — each track's share,
days, kept days, its own phase strip and what it gave up — on Program ▸
Overview and in the preview, the same view in both; session rows carry a
`TrackBadge`. A regenerate (settings sheet, from this week) sends every track
from its own phase that week, never the lead track's alone.


---

### 6.23 Workout Row and Linked Workouts

**A recorded workout looks the same wherever it is listed.**
`Views/WorkoutRow.swift` is one recorded workout: the activity icon (§6.12),
what the device recorded, date, time and duration, distance and average HR,
the source chip, the linked-session chip and the TRIMP badge. Log ▸ Activity
lists them; the session detail's *Recorded Workout* section shows the one
linked to that session (with `showsSession: false`, since the row already
sits on its session, and `showsChevron: false` inside a `NavigationLink`)
and pushes `WorkoutDetailView`.

A session card on Today shows a `link` glyph beside the completion check
when a workout is linked. Both read `AppState.linkedWorkout(forSessionKey:)`,
the reverse of `matchedSessionKey(for:)`: confirmed matches first, then a
session log's `matched_workout_id`. A match the server dates outside the
active program (`inCurrentProgram: false` on the snapshot) never links —
"4-Monday-0" names a session of every program the athlete has had
(`LinkedWorkoutTests`).

---

### 6.24 Filter Menu

**Several filters on one list are one toolbar button, not rows of pills.**
`Views/WorkoutFilterMenu.swift`. Log ▸ Workouts (now Activity) used to stack three bands
under the title — the section picker, the period pills and a scroller of
sort and activity chips — so the list started a third of the way down the
screen. The system's own apps (Mail, Files, Photos) put filtering behind
one `line.3.horizontal.decrease.circle` button.

- **One value.** `WorkoutListFilter` (show, period, sort, activity) is held by the
  screen and passed as a binding to the menu and the list, so they cannot
  disagree. `isDefault` and `apply(to:)` live on it (`WorkoutListFilterTests`).
- **Submenus that name their value.** Each dimension is a `Picker` with
  `.pickerStyle(.menu)` inside the `Menu`, so the menu reads "Sort By — Date"
  without opening it. Reset appears only when something differs.
- **The glyph fills while a filter is on**, the convention for "this list is
  narrowed".
- **Never invisible.** A scope line heads the list — the count and period
  always, and a removable chip for each narrowing — so a filter set in the
  menu is visible and one tap clears it (§6.11).
- The section picker (§6.8) stays the only band under the title. Analytics
  keeps `AnalyticsPeriodPicker`: there the period is the only filter.

### 6.25 Score Explanation

**A score says what it is made of and which band it is in.**
The Score card on Analytics ▸ Progress (`Views/AnalyticsProgressTab.swift`) opens
`ScoreDetailView` (§6.37), with the band from
`ProgressionScore` (`ProgressionScore.swift`). Today's Progress card no longer
shows the score (2026-10-16): it shows the methodology's headline measure, worded
by the server (`headlineSummary`), and Adherence beside it carries completion. Analytics ▸ Progress read 70 "On Track" in week 1 for an athlete who
had done every session: compliance × 0.4 plus a neutral 50 × 0.6 for a measure
with no data, a number nobody could reconstruct. Since 2026-10-16 the score is
the measures' trends alone; before any has one there is no score, and the card
says why under "Not enough data yet".

- **The words are the server's** (`score_breakdown`, `score_status`,
  `scope_label`, `pending_measures`, `purpose` from `src/analytics/review.py`),
  so the web says the same; the phone only lays them out. Older servers send
  none of them and the card falls back to the thresholds alone.
- **The card counts; the detail explains.** The card is the score, its band,
  the completion and `score_status.counts` — "⏸ 3 stalled · 🐢 3 behind", each
  status's symbol (`AnalyticsStatusStyle.symbol`) and number, worst first,
  wrapping in a `LegendFlow`. `ScoreDetailView` has the server's sentence
  (which names two measures per status, then "and N more"), each measure with
  its symbol and points and the sum beneath, those still collecting data,
  how many of each method's measures can be read ("Measurable" — the
  methodology card's "📏 2/2" until 2026-10-18), the bands with the current
  one ticked, and `purpose` as its About. "How is this scored?" folded most
  of that inside the card until 2026-10-18; an older server's card shows the
  sentence instead of the counts.
- **What the percentage covers is said to VoiceOver** ("2 of 2 sessions so
  far · week 1", the server's `scope_label`) — it used to say "Weekly", which
  it never was, and then sat beside the percentage in words, the same fact
  twice (2026-10-17).
- **Nothing waiting is said.** A measure with no data is listed under Waiting
  for data with what starts it; an empty review says "Nothing to change — keep
  going" instead of ending in blank space.


### 6.26 Phase Changes

**Overview summarises the phases; each phase is its own screen.** Program ▸ Overview
reads the server's `phase_summary` (`PhaseSummaryModels.swift`, from
`src/phase_summary.py`), the same document the web lays out; the phone counts nothing.

- **The Phases card** (`ProgramOverviewTab`, an `AppCard`, §6.15) is one row per
  phase, divided: the kind's dot, the methodology's name for it, "Now" (`TintCapsule`)
  on the current one, and "Wk 5–20 · <focus>" under it. A row with a summary has a
  chevron and pushes `PhaseDetailView`; without one (an older server) it is a plain row.
- **`PhaseDetailView`** is an inset-grouped `List`: the weeks and the focus line, the
  methodology's description as the section's footer, then *Each week* (a row per
  modality with its symbol, a dot per session and "2×/wk", and the week's minutes),
  *What changes* (the server's lines), *Sessions* (new in the modality's colour, gone
  struck through) and *Lifts* (every loaded lift, first → last weight).
- **Compare phases** closes the card when there is more than one phase and pushes
  `PhaseMatrixView`: every session — or, with its segmented control, every exercise —
  against every phase as times per week, grouped by modality, scrolling sideways when a
  track has more phases than the screen is wide.
- **Summaries match segments by order**, and only when the counts agree, so a mismatch
  shows nothing rather than another phase's changes.
- `program?section=overview&phase=<n>|compare` opens a phase (from 0) or Compare from
  the launch environment, so the pushed screens can be screenshotted (`AppRouter.openProgramPhase`).

Until 2026-10-17 a phase row expanded in place into four caption-sized blocks and the
matrix sat on Overview itself: a four-phase track was a page of them, and the screen had
no summary state (§1.4).

---

### 6.27 Home-Screen Widgets

**One full-width row each** (`systemMedium`, `TrainingWidgets/HomeWidgets.swift`):

- **Week Overview** — the program week, Monday to Sunday, one column a day:
  each session a modality-coloured disc (a tick once done, its minutes under
  it, red minutes once its day has passed undone), "rest" on an empty day,
  today outlined in orange; the header says the week, the phase and done of
  all. Taps open Program ▸ Calendar.
- **Training Status** — Today · Readiness · Adherence · Progress, the web's
  Today cards as four cells, each a link to its own screen (Today, Analytics
  ▸ Recovery, ▸ Program, ▸ Progress). A coloured rule tops each cell: the
  session's modality, the readiness status, the scorecard's verdict, the
  headline's status.

Rules: the phone writes both snapshots (`AppState.writeHomeWidgets` →
`WidgetWeekData`, `WidgetStatusData` in the App Group) whenever the program,
a completion, readiness or `/analytics/program` changes, and reloads only
these two kinds; the widgets compute nothing. A `Link` tints and centres its
label, so a status cell sets its own foreground and alignment. To look at a
widget, render its view with `ImageRenderer` in a throwaway test — nothing
can add one to the simulator's home screen.


### 6.28 Program Header Card

**The program says what it is the same way wherever it is named.**
`Views/ProgramHeaderCard.swift` — an `AppCard` headed "Program": the
methodology (a blend joined with "+") and the book (§6.18), the current
phase as a pill in its kind's colour with `calendar` week/total and a
deload mark, one symbol row per fact (`ProgramHeader.Tag`: track, how it
progresses, intensity model, framework), and a footer the screen supplies.
`ProgramHeaderStat` is a footer cell: symbol, value, unit under it, an
optional mark.

- *Program ▸ Overview* (first card): the track when the methodology has more
  than one, and nothing else as a tag — how it trains is the book's (§6.18),
  and the framework is Analytics' to name. The footer: the weeks as one bar
  (`PhaseProgressBar`, §6.36, without labels) with the first and last day under
  its ends, days a week and session minutes (`ProgramHeaderStat`), the event,
  then the priority mix as one bar split by modality with a wrapping legend
  (`PriorityMixBar`, the shares from `ProgramPriorities`). No verdict, and no
  fact twice: the number of weeks is the pill's "1/12". Until 2026-10-17 it also
  listed progression, intensity model and framework, a weeks cell, and the
  priority mix as a card of its own — "linear progression" four times over for
  Starting Strength.
- *Analytics ▸ Progress* (first card): every tag — how it progresses,
  intensity model, framework (the name from the analytics document's frame,
  since the phone has no framework catalog) — and plan fidelity as its footer,
  each field actual / ideal with a check or a warning mark.

Rules: the card owns the book's sheet; a screen passes facts, never draws
its own copy. It replaced Overview's "About this methodology" row
(`MethodologyRow`) and Analytics' private frame card on 2026-10-16.


### 6.29 Sign-in, Sign-up and Account

**One signed-out screen signs in and signs up.** `Views/Auth/AuthView.swift`:
*Continue with Apple* creates the account when there is none, so the screen
never asks which the athlete wants. The button is white in dark mode, black in
light, a capsule at full width. Under it a footnote link reveals the password
form (email, password, *Sign in* as `.borderedProminent`, `.controlSize(.large)`)
for accounts made on the web.

- A failure is one line in red with a warning mark, worded by
  `SignInError.message(for:)`; a cancelled Apple sheet says nothing.
- The Apple button carries `.id(colorScheme)`: the system button keeps the style
  it was made with and would stay black on black after a scheme change.

**Settings ▸ Account** (`AccountSection`): the email — "Hidden email (Apple)"
for a relay address — with how the account signs in, *Sign Out*, and
*Delete Account…*, a sheet confirmed by typing DELETE.


### 6.30 Workout Complete

**A new workout gets a moment, not just a row.**
`Views/WorkoutCompleteSheet.swift`, presented by `ContentView` the first time
the phone sees a stored workout — from the watch, Garmin, Strava or Apple
Health — that ended in the last 36 hours. `WorkoutCompletion` (pure,
`WorkoutCompletionTests`) picks it: the most recently finished workout not
yet shown that recorded something. Several arriving in one sync show only the
newest; closing the sheet marks every listed workout seen
(`AppState.finishCompletedWorkout`, the ids in `UserDefaults`), so the rest
wait in Log ▸ Linking rather than popping up one after another. A `.fit`
import is its own confirmation and is marked seen when it lands.

Top to bottom:

- *Hero*: the activity icon (§6.12) in its modality's colour on a 15 % disc
  with a 35 % ring, the completion check (§3.3) on its edge — it bounces
  once when a link is confirmed — "WORKOUT COMPLETE" in green, what the
  device recorded, date · time · source, and one line of credit.
- *Route*: the track on a flat map, only when it is one — two real fixes
  (not 0,0) spread over more than 50 m (`WorkoutRoute.hasRoute`, which the
  workout detail's Route section asks too). A gym session's handful of
  points in one spot draws no map.
- *Numbers*: up to six tiles, in this order: time, distance, average HR, load
  (TRIMP, coloured by `TrimpStyle`), elevation gain, calories, peak HR. Four
  sit two by two. The load and everything under *Effort* (training effect,
  the zone split as one `HRZoneStyle` bar, recovery hours) are the server's
  `analysis` from `GET /health/workouts/<id>`; without it the card is absent.
- *The planned session* (`WorkoutCompletion.Match`), as an `AppCard`
  with a status capsule:
  - **Linked** (green): the server, the watch or another client already
    linked it; the session row carries the check. A match the server dates
    to an earlier block shows no session of this program (§6.23).
  - **Suggested** (orange): the server's weak match, with *Not this* on the
    row and **Confirm & complete** (green) as the sheet's primary action;
    the day's other open sessions are offered under it.
  - **Unlinked**: no suggestion, but sessions planned that day have no
    recording yet — each with *Link*. A session already logged done is
    still open: the watch logs the session it ran and its recording comes
    in through Garmin Connect afterwards, as Log ▸ Linking reads it.
  - **Extra**: every session that day already has a recording, or none
    was planned.
  Linking goes through `AppState.matchAndComplete`, the same path as Today's
  Accept.
- *Week N*: a dot per planned session of the workout's week, in its
  modality's colour, filled and ticked once done or linked, with done/all.

**The line of credit** (`WorkoutCompletion.cheer`) is chosen by situation —
the week finished, a long day (90 min+), on plan, planned but not yet linked,
extra work — and within it by a stable hash of the workout's id, so one
workout always reads the same and a run of them does not repeat. It is the
one sentence on the screen; everything else is a symbol and a number (§1.4).

**Any session, any package.** Nothing on the sheet names a philosophy,
framework or archetype. It reads the recorded workout (activity, times,
distance, heart rate and the server's `analysis`) and, for the planned
session, only what every package's program carries: the session's
`modality`, its archetype's `name` and `duration_estimate_minutes`, and its
key. It shows no prescription, so a package does not have to describe its
loads in any particular way for the sheet to work. A new package that
schedules the existing modalities needs nothing here. A new **modality** is
the one thing that needs work on the phone: `ModalityStyle` (colour, label,
icon) is a fixed table of the twelve in `data/commons/modalities/`, and an
unknown id is drawn grey with a generic figure until it is added there (and to
the web's `MODALITY_COLORS` and `data/commons/modality_families.json`, which
the matcher scores with).

Rules: the sheet decides nothing on its own — closing it leaves an unlinked
workout unlinked, to be decided in Log ▸ Linking. *Details* (toolbar)
pushes `WorkoutDetailView`. `trainingcompanion://workout-complete[?id=…]`
opens it for a given workout, or the newest, seen or not, for the simulator;
`?demo=1` lines up the newest eight, one after another as each is closed.
A sheet SwiftUI could not present (another was open) is taken back after
1.5 s without being marked seen; the first load on an install or on this
build only records what is listed. A suggestion for another program's
session is not confirmed here (its key would tick this program's session of
that name); it falls through to the day's open sessions.

### 6.31 Standard Ladder

**One ladder for every standard, on every screen.** `Views/StandardLadder.swift`
(the web's `components/standards/StandardLadder.tsx`) draws four rungs, entry →
elite, filled up to the level the **server** reached (`levelIndex`, 0 = below
entry) in the colour of the modality the standard measures (`domain` →
`ModalityStyle`), with each rung's word and threshold under it — the threshold
as the server prints it (`standardsText`: "4:30", "1.5×BW"). `StandardLevelBadge`
names the level ("Advanced", "Below entry") in a capsule of the same colour.

- Used by Profile ▸ Standards (rows and the *Log a result* sheet), the
  standard's own sheet (§6.32), a target-level measure's detail screen
  (§6.37) and Blocks (the badge; a gain is said as "+1 level", never in a
  status green).
- Where: Profile ▸ Standards is *This program* (the server's `programStandards`)
  · *Your results* · the other standards behind *Show all*; Progress shows the
  program's own and says how far each moved this block with a `Sparkline`
  (56 × 16, the modality's colour, no axis) from the block's start, and opens
  the standard's sheet in place; Blocks draws each as a compact
  `StandardHistoryChart`, the current program's first, and opens its sheet
  through `AppRouter.openStandard`.
- A level has no colour of its own: position and word carry it, so it cannot
  be mistaken for a status. The traffic light (§6.15) is only for a declared
  target (met · partly · below).
- Nothing on the phone computes a level or formats a value: `level_of` and
  `format_value` live in `src/analytics/benchmarks_data.py`. Profile used to
  colour levels purple/blue/green with its own thresholds and had no "below
  entry".
- Results are logged by text (`AppState.logResult`): the field takes what the
  athlete would write ("4:58") and the server parses it; a value it cannot
  read comes back in its words under the field.

The level words and thresholds under the rungs are `.caption2`, truncating —
they were a fixed 9 pt in `.tertiary`, under Apple's 11 pt minimum (§4.1).

### 6.32 Standard Detail

**One standard, every result.** `Views/StandardDetailSheet.swift` (the web's
`StandardDetailSheet.tsx`) is presented from a Profile ▸ Standards row, from Athlete's
*Bodyweight history* (`StandardSubject.bodyweight`), and by the deep link
`profile?section=standards&standard=<id>` (`AppRouter.openStandard`):

- the current result with its level badge, best and the gap to the next level, the
  `StandardLadder` (§6.31), the test protocol;
- *History*: `StandardHistoryChart` — the results as one line in the modality's
  colour, each level a dashed `RuleMark` labelled with its word and the server's
  threshold text (no value axis: nothing on the phone formats a value), the
  program blocks as alternating bands, a month tick (a week tick under two
  months), and drag-to-read (`chartXSelection`);
- *Log a result* → `StandardResultSheet`: the value as typed ("4:58"; for a ×BW
  standard *Load lifted* kg × reps or *Ratio ×BW*), the day (`DatePicker`, no
  future days), a note. Editing sends only what changed.
- the results, newest first: value, level, day, source ("Typed in", "Garmin"…),
  block and note; tap or swipe to edit, swipe to delete behind a confirmation
  that says the rest of the history stays.

### 6.33 Test Badge and Standard Target

**A test says what it measures.** `Views/StandardTestViews.swift`: `TestBadge` (a
capsule, `trophy.fill`, "Test") marks a session that tests the phase's standards
(`ProgramSession.testInfo`, read from the round-tripped `test` key) on Today's
session card, Program's rows and the session header. `StandardTargetRow` names one
standard with the athlete's best, its level badge and "90 reps for intermediate"
under it — the server's words — and opens its sheet (§6.32) through the router.

- Session detail: under the header, "A test, in place of …" and a
  `StandardTargetRow` per standard; each scored exercise (`standardId`) names its
  standard beside the prescription.
- Today: the session card shows the badge and "N standards" instead of the
  exercise count.
- The catalog and results load when a session with scored slots opens, since
  only Profile loaded them before.

### 6.34 Standard Suggestion

**A result a session suggests is saved by the athlete, never by the app.**
`Views/StandardSuggestionRow.swift`: `StandardSuggestionRow` shows one suggestion —
standard name, the value as the server prints it, `StandardLevelBadge` (§6.31), then
"New best", "Was 7:45", "First result" or, for a re-logged value, "Corrects 7:32",
and where it came from (session, day) — with three answers: **Save result**
(`.borderedProminent`), **Correct** (an inline field, saved with the typed value),
**Not a test** (`.bordered`). `AppHaptics.success` / `.error`; the server's words on
a failure. The first line is the short name ("1-Mile Run"), the value and the badge;
everything else — standing, what was logged ("fastest 1 mile of 5.2 km"), where it came
from — is the second, so nothing truncates the name. `SessionSuggestion` is the same row, compact and without the name, for
one standard of one session (`StandardSuggestion.isFromTest(sessionKey:)` compares
the day, since the web logs under "3-Monday" and the phone under "3-Monday-0").

- Profile ▸ Standards: *To confirm*, above *This program*, when any are waiting.
- Today: "N results to confirm", the first three, then "All N in Profile".
- Session detail: under each test standard's `StandardTargetRow` (§6.33) — not in
  the exercise row, whose tap and swipe actions would take the buttons' touches.
- `ExerciseLogSheet` (§6.16): a for-time slot's **Time** field takes m:ss
  (`SessionLogging.parseClock`), starts empty (the cap is only its placeholder —
  prefilled, a test nobody changed would have saved its cap as the result) and keeps
  Save off while it does not read; a test slot asks first for its standard's
  number. The web's `components/standards/SuggestionRow.tsx` is the same row.

### 6.35 Zone Plan Comparison

**Planned zone minutes are an outline, recorded ones fill over it.**
`Views/ZonePlanComparison.swift`: `ZonePlanComparison(rows:)` draws one row per zone —
label, a track with the planned minutes as a stroked outline and the recorded minutes as
a fill in `HRZoneStyle.color` (§8), both against the largest value — and "22/8 min"
(recorded/planned) at the trailing edge; a Recorded/Planned key under the rows. Zones
with neither side are left out (`ZonePlanComparison.rows(planned:recorded:)` from the
server's five-zone arrays). Analytics ▸ Progress's intensity card draws it over the block
(`intensity.zones`).

`PlannedZonesView(analysis:)` is one workout against its session's programming
(`analysis.planned`, `src/analytics/hr_plan.py`) under "Planned for Fran": the zone
minutes that **count** — only where an exercise prescribes zones — against the planned
minutes of the same exercises; a caption saying how they were counted (the watch's
exercise times, not timed, no heart rate, or why nothing counts); then one row per
exercise: name, its prescription ("Zone 2", "max effort") and "12 of 15 min" when the
watch timed it, "not timed", or "not counted" in secondary text. On the workout
screen's "Against the plan" section and in the Workout complete sheet's effort card
(§6.30); nothing when the workout is linked to no session. `ZonePlan` holds the words,
the phone's copy of the web's `lib/zonePlan.ts` (`ZonePlanTests`, `zonePlan.test.ts`).


### 6.36 Phase Progress Bar

**Where the athlete is in the program, as one bar.** `Views/PhaseProgressBar.swift`:
a segment per phase as wide as its weeks, in its kind's colour (§3.2) — past phases
dimmed, the current one filled to this week with a marker, later ones faint — on a
`systemFill` track. Program ▸ Calendar shows it with each phase's name under its
segment; Program ▸ Overview's header (§6.28) without (`showsLabels: false`), since the
pill names the current phase and the Phases card lists them all. One accessibility
label for the whole bar: "Week 3 of 12, Base".

Rules: segments come from `PhaseSegment.segments(of:)`, never a list of kinds; a label
too long for its segment truncates at `.caption2` — it used to scale to 60 %, about
6.6 pt (§4.1). Calendar drew it privately until Overview became the second user.


### 6.37 Card and Detail

**A card is the summary; the detail is a level down.** Apple's iOS guidelines
have no "back of the card": the flip-to-the-back info button is gone, and
detail is reached the way Lists and tables describe it — "a disclosure
indicator reveals the next level in a hierarchy". Charting data says the same
for charts ("keep a chart simple, letting people choose when they want
additional details"; a small chart previews "a larger version… in a different
view" with the same style), and Apple Health is the model: a summary card, then
a screen with the full chart, the numbers and, at the end, *About*.

- **`AnalyticsDetailCard`** (`AppCard.swift`) is an `AppCard` that is
  one `NavigationLink`: the whole card is the target, `chevron.right` follows
  the header's badge, `accessibilityHint` names the destination. Its content
  is the summary state only — the current value in its own currency, a status,
  a trend, a `Sparkline`, at most one line of words (a coverage reason) — and
  holds nothing interactive, since the card itself is the button.
- **A row that opens something** inside a card (an exercise, a standard) is
  its own `NavigationLink` or button with a trailing chevron, not the card.
  A row has one push target, the whole row. `MeasureRow` (Analytics ▸
  Progress) pushes `MeasureDetailView`; a measure the chart can draw leads
  with a chart button (`chart.line.uptrend.xyaxis.circle`, filled and amber
  while it is the chart's series) that draws it there. Until 1.38 the row
  drew and a small chevron pushed.
- **The detail screen** is an inset-grouped `List` with an inline title (the
  card's name): the standing first, then the chart (200 pt, with a menu
  picker when it has several series — a display mode, §6.8), then every row
  the card left out, then **About**.
- **`AboutSection(about:)`** (`Views/DetailParts.swift`) ends the screen:
  *About* (what the number measures, the package's note) and *What to log*
  (each capture requirement and where it is logged). The words are the
  server's — `src/analytics/vocabulary.about`, carried as `about` on each
  progress entry — so the cards keep to numbers and symbols (§1.4) and the
  explanation is written once, for both clients. An info button
  (`info.circle`) only where there is nothing to navigate to: Apple's info
  button "reveals more information about a row's content" and does not
  navigate.
- **`Sparkline`** (`Views/DetailParts.swift`) is the one small line: the
  standards' block line and the Exercises card's chart were two.
- **No fold, no picker on a card.** Extra information is never an inline
  "How is this…?" fold or a segmented picker inside the card: the card holds
  one reading and the detail holds the rest, alternatives included (Mix's
  activities, Weekly's TRIMP). Every card with more to say than its summary
  is an `AnalyticsDetailCard`; one whose rows open their own screens
  (Standards, Exercises, Blocks, Check-ins) keeps them, and Totals is all
  there is to say.
- **A group's name is a `SectionLabel`, not a card**
  (`Views/AnalyticsProgramSections.swift`): the methodology above its measure
  cards ("STARTING STRENGTH", "· 70%" in a blend), styled as an inset list's
  section header and aligned with the cards' text. A card that only named
  what followed said nothing of its own.
- **A label inside a row is `.labelStyle(.inline)`** (`InlineLabelStyle`,
  `AppCard.swift`): symbol and words 4 pt apart. A `List` gives every
  `Label` an icon column — the symbol in a fixed-width slot, the words far
  from it ("◎     120kg") — which `.titleAndIcon` does not undo. A label that
  *is* the row (a "How to do it" button) keeps the column; one that is part
  of the row's content — a target, a trend, a reading, a badge — does not.
  `TintCapsule`, `MeasureTrendLabel` and `CoverageNoticeView` carry it
  themselves.
- A detail a deep link can open, for screenshots and other screens:
  `analytics?section=progress&measure=<entry id>` and `&exercise=<id>` (selected on the
  Progress chart, §6.41), `analytics?open=score|scorecard|intensity|movement|workouts|shapes|readiness|sleep|hrv|resting-hr|checkins|pmc|load-focus|mix|weekly|block-load`
  (`AppRouter.openAnalyticsDetail`; each section pushes its own).

Users: Analytics ▸ Progress's Score (`ScoreDetailView`, §6.25), its measure
rows (`MeasureDetailView`), "N not in this program" under them
(`MeasuresElsewhereView`), its
Standards rows (the standard's sheet, §6.32); Analytics ▸ Recovery's readiness (`ReadinessDetailView`, §6.21),
sleep (`SleepDetailView` — Sleep Debt, Last Night and Sleep Stages were three
cards), HRV and resting heart rate (`RecoveryTrendDetailView`, one view for
both, like `RecoveryTrendChartView`) and "All check-ins" (`CheckInHistoryView`;
the card keeps the last seven `CheckInRow`s); Analytics ▸ Load's Performance
Management (`PMCDetailView`: today's CTL, ATL and TSB — whole numbers, one
decimal under ten — over a compact `PMCChart` on the card, the full chart with
a drag-to-read rule on the screen), Load Focus (`LoadFocusDetailView`: each
band's zones and minutes), Mix (`MixDetailView`: by modality and by activity)
and Weekly (`WeeklyDetailView`: sessions and TRIMP a week, each week's two
numbers) — `Views/LoadCardDetails.swift`; Analytics ▸ Blocks' block rows
(`ProgramVersionDetailView`), "By block" (`SeriesBlocksView`), TRIMP by block
(`BlockLoadDetailView`: each block's weeks, average a week, peak and total —
the server's `load.byBlock`) and standards (the sheet); Analytics ▸ Progress's
Scorecard (`ScorecardDetailView`: weeks, tiers, each modality's minutes),
Intensity split (`IntensityDetailView`: zones, weeks, each framework's split,
share of 1RM) — `Views/ProgramCardDetails.swift` — Movement and Workouts
(`MovementDetailView`, `SessionShapesDetailView`); and Program ▸ Overview's
phases (§6.26, before this section was written). Program's Load card is a
summary of the PMC that Load's own card opens.

Where two cards were the same data two ways they became one card: Load's
**Mix** (the modality ring on the card; activity hours on its detail) and
**Weekly** (sessions a week on the card; TRIMP a week on its detail, with
"On device" under that chart only, whose request is its own). Each had a
segmented picker inside the card from 2026-10-17 to 2026-10-18.

Terms that are not a measure — TRIMP, CTL, ATL, TSB, readiness, HRV, resting
HR, sleep debt, completion and minutes a week, the intensity split and the
heart-rate zones, load focus, the mix, sessions a week, load by block — take
their About from `vocabulary.TERMS`, served by the
static `GET /api/analytics/vocabulary` and cached in
`AppState.analyticsTerms` (`AboutText(terms:from:)`).

---

### 6.38 Constraint Toggles

**What a program is built for is toggled one way.** `EquipmentToggleSection`
and `InjuryToggleSection` (`Views/ConstraintToggles.swift`) are the `Form`
sections of equipment (`EquipmentItem.all`) and injury flags
(`appState.injuryFlagDefs`) bound to a `[String]`. Users: the builder's
constraints step, the Program settings sheet and the preview's Adjust — the
first two had each written the same two loops.

When not to use it: Profile ▸ Equipment is the profile's own screen, a grid of
tiles grouped by kind; it edits what the athlete owns, not what one program is
built for.

---

### 6.39 Program Preview

**A generated program is a draft until it is started.**
`Views/ProgramPreviewView.swift` (the web's `/program/preview`) shows a draft
and saves nothing until **Start this program** / **Apply from week N**, each
behind a confirmation that names what happens to the program it replaces (kept
in Program ▸ History with its logs). It is pushed from the builder's last step
(**Preview Program**, which generates with `persist: false` — the builder used
to persist and throw the answer away, so a refusal silently kept the old
program) and from the Program settings sheet's full regenerate, and presented
as a sheet by the regenerate offer (§6.17) in regenerate mode.

- **Plan · Held back** (`AppSubTabPicker`, §6.8). Plan lists each week's
  sessions; a row says "N held back" (`circle.slash`, symbol and words, §1.6),
  "In place of …" or "Scaled: written for …", and in regenerate mode
  "Changes" on the sessions the change moves, its row tinted. A session opens
  `PreviewSessionSheet`: each exercise with its load (`LoadFormat`), why an
  empty slot is empty in plain words (`HeldBack.blockerText` from the
  server's `blocked_by`: "Strict Press needs barbell, rack"), and **Swap**
  (`SwapExerciseSheet` with its `draft` source — the draft's methodologies and
  constraints, the pick edits the draft only).
- **Held back** is `POST /programs/impact`: the empty slots counted, the
  schedule findings, "What would restore it" (**Add barbell · restores 33**,
  **Preview without …**, **Preview at …** — each previews again) and every
  change filed under its cause; knock-on changes are one line.
- **A refused draft** shows the validator's reason and "What would let it
  build" with the one action that alone unblocks it; Start stays disabled.
- **Adjust** (toolbar) edits level, equipment and injuries (§6.38) and
  previews again; swaps on the draft are dropped with it, and it says so.
- **Words** live in `ProgramPreviewModels.swift` (`HeldBack`, the decoders,
  `ProgramEdits` — the index-addressed edits the active program uses too),
  pinned by `ProgramPreviewTests`.
- Debug builds open it on launch: `SIMCTL_CHILD_TC_PREVIEW=<philosophy id>`
  (a draft from the profile; `TC_PREVIEW_WEEKS`, `TC_PREVIEW_TAB=heldback`)
  with `ROUTE='trainingcompanion://program'`.

### 6.40 Session Icon

**A session leads with what is in it; its colour says what kind it is.** The
server gives every planned session an `icon` for its main exercise
(`src/session_icon.py`, from `data/commons/workout_icons.json`), derived on
every read and never stored. Today there is one: `kettlebell`, for a session
whose main exercise is a kettlebell exercise — every Wildman day, a kettlebell
day in any other package. A session without one keeps its modality icon.

```swift
Image(symbol: SessionIcon.symbol(icon: session.icon, modality: session.modality))
    .foregroundStyle(ModalityStyle.color(for: session.modality))
```

- **Same icon everywhere.** The phone, the widgets (`WidgetSession.icon`), the
  Apple Watch (`WatchSession.icon`, `SessionListView`), the Garmin
  (`Icons.forSession`, its `cat_kettlebell` bitmap) and the web
  (`WorkoutIcon`) draw the same glyph for the same session, so a recorded
  workout is easy to put beside the session it was.
- **The modality stays on the card** — the capsule on Today, the caption on the
  session header — but not as the header's icon.
- **Always through `Image(symbol:)`**: the icon is a custom symbol in each
  target's catalog (`ios/tools/make_kettlebell_symbol.py` writes all four).
  An id this build has no glyph for falls back to the modality icon, never to
  nothing (`SessionIconTests`).
- **Where:** Today's card (before the name), Program ▸ Calendar and the day
  sheet, the session header, the preview, the session pickers (import,
  workout detail, Workout complete), Log ▸ Linking. The inline watch
  complication keeps the modality's system symbol.

### 6.41 Progress Chart

**Every time series of the program is one chart.** Analytics ▸ Progress
draws what the athlete did against what the program asked on one card
(`Views/ProgressChartView.swift`), the web's `ProgressChart`:

- A menu names the series (Exercises — "Back Squat · 10 logged" — then the
  methodology measures the server names in `exerciseSeries.measures`), a row of
  capsules its metric (top set, reps, sets, total reps, volume, est. 1RM, RPE,
  time, hold, rounds, distance — only those the exercise has a value for), and
  `info.circle` opens the exercise's reference (`ExerciseDetailSheet`, §6.14).
- The last done value large, "Last done <day>" under it, "logged/scheduled"
  beside it.
- Swift Charts on a date axis: done as a green line with points (hollow on a
  deload, the deload day shaded), prescribed (an exercise) or expected (a
  measure) as an indigo dashed line, today as a dotted rule. Straight segments
  — sessions are discrete, and a curve invented values between them. The
  legend names the dashed line only when there is one (a lift the method
  works up on the day prescribes no kg). The y-axis starts from the lightest
  value, not 0.
- A panel under the chart reads one session: the day, the workout, the
  prescription in the server's words and what was done set by set ("100×5,
  100×5, 100×4 · RPE 8"). Before the first touch it is the last session done
  (else the first planned), so the readout is there to be found and the card
  keeps its height; touching the chart moves it to the nearest session. A tip
  in line above it says so once (§6.52).

The series are the server's (`exerciseSeries` on `/analytics/program`,
`src/analytics/exercise_series.py`); `ProgressChartModel`
(`ExerciseSeriesModels.swift`) only selects and lines them up, as
`lib/progressChart.ts` does on the web (`ProgressChartModelTests`). It
replaced, on 2026-10-23, the measure cards' sparklines, `MeasureDetailView`'s
chart, and the Exercises section with its `ExerciseHistoryView` screen
(`/progression/exercises`, which stays for installed builds).

### 6.42 (unused)

No pattern took this number; it is kept so the later ones do not move.

### 6.43 Session Actions

`Views/SessionActions.swift`: what a program day or one of its sessions can do, one set of
items (`SessionActionSet`) with three ways in, on Today's session card and Program ▸
Calendar's day row:

- **`SessionActionsMenu`** — the visible "…" at the card's or row's trailing edge. It draws
  nothing on a day with nothing to offer (a past rest day).
- **`SessionAddButton`** — a rest day's quiet "+ Add session", today or later only.
- **`.sessionActions(weekIndex:dayName:sessionIndex:)`** — the same menu on a long press,
  the shortcut (§6.51).

Per session it offers **Move to Another Day** (`MoveWorkoutSheet`), **Replace**
(`ReplaceWorkoutSheet`) and, for a session the athlete added that is not done, **Remove
Added Session** (destructive); a calendar row with several sessions groups them in sections
by name. Today or a later day also offers **Add Session**. `SessionDetailView` carries none
of these — it keeps the exercise swap (one slot). Until 1.38 the long press was the only
way in and no screen showed an Add button; a tip (§6.52) now points at the "…" once.

**Adding** is `ReplaceWorkoutSheet` with `mode: .add`. Its tabs, as when replacing, are
**Browse** (every archetype, picked by hand) and **Search** (first when adding): a Kind picker
(Mobility, Movement / Skill, Aerobic Base, Durability, Rehab) under the day's name, its footer
"An extra: it counts once you do it, and you can remove it.", then one centered, prominent
**Search** button — the server finds a fitting session from the library, never invents one.
A found or picked session is pushed in full before anything is saved (`SessionPreviewView`):
its kind, name, minutes, exercise count and source ("via Kelly Starrett / Built to Move"),
every exercise with its prescription (`LoadFormat.describe`) and load note, then **Add
Session** / **Replace Workout** and, for a searched one, **Search Again** (another of the
kind; its refusal shows on this screen). "Add Session" saves (`AppState.addSession`), and the
Apple Watch is resynced once the save lands (`.programSaved` → `WatchSessionManager.syncProgram`). An added session
shows a dashed "Added" capsule on Today's card and "Added" in the calendar row. Week dots leave
an undone one out (`WorkoutCompletion.weekDots`). A refusal shows the server's sentence
(`APIError.serverErrorDetail`).

### 6.44 Workout Player

`Views/WorkoutPlayerView.swift` (model `WorkoutPlayer.swift`): one session, full screen
(`.fullScreenCover`, the app's only one), run step by step on the Apple Watch's engine
(§9.8) and drawn from the screens the server writes for both watches (`WatchSpecText`), so
every number and word is the watches'. It is for an athlete who records with a band and
reads the steps on the phone: no heart rate is shown or kept.

- **Before the start:** the session laid out (each step with its prescription and last
  time), **Start** in the modality colour. The first Start asks for notifications once.
- **Header:** close (✕, "Leave the workout?" — Finish and save / Leave, resume later / Discard workout), the
  session's name over the elapsed time, the step list (≡); a segmented bar of the steps,
  the current one in the modality colour, done ones dimmed; "Step n of N".
- **Step page:** the title in `.title` bold, field A (label `.caption` semibold secondary
  uppercase over a 96 pt rounded bold monospaced value), field B on one row beside its
  label (`.title` rounded), the template's gauge (set dots, an interval's bar over the whole step with Work /
  Rest under it, a timed step's or AMRAP cap's bar), the two lines (`.title3`, then
  `.title3` secondary), **Notes** as a disclosure (load note, coach cue, focus).
- **Controls:** one 64 pt capsule in the modality colour saying what the spec's LAP does
  (Complete set n, Start/End hold, + Round, Switch side, Next, Finish), **Skip** under it
  in plain secondary. A completed set opens the **set logger** sheet (reps, kg, RPE
  steppers, prefilled from the prescription and last time; Save logs it).
- **Rest:** a 260 pt ring in the modality colour counting down, "Up next" with the step
  and its set, then **+30 s** (secondary capsule) and **Skip rest** (prominent). A rest
  that ends on heart rate shows "until HR < n" with its cap: the phone has no reading.
- **Lead-in:** "Work in" over the count (160 pt rounded bold, the modality colour) on a
  dimmed page, with a tone and a tap each and the go's own tone; spoken with Voice on.
- **The end:** `WorkoutPlayerCompleteView` — a check, "Workout complete", the summary
  (time, sets, volume, steps done), each step's log, a test's **Results**, the reps a
  timed step asks for, notes; **Save workout** (or **Save results** / **Not a test**) and
  **Discard workout**. A failed save says so in red under the buttons and keeps the
  workout. Save is one `PUT /health/sessions/by-uid/<uid>`, then Today refreshes.
- **While away:** the screen stays awake while the player is open; leaving the app
  schedules a notification per forecast moment and starts the **Live Activity**
  (`TrainingWidgets/WorkoutLiveActivity.swift`): on the Lock Screen the session and phase in
  the modality colour, the step in `.headline`, what follows, and the countdown in 34 pt
  rounded monospaced with "Step n of N"; in the Dynamic Island the phase symbol and the
  countdown (compact), the step and next (expanded). The countdown is
  `Text(timerInterval:)`; a step that waits for the athlete shows n/N instead. On the
  Lock Screen and in the expanded island it has the player's own two secondary buttons:
  **Pause** / **Resume** on a step the clock runs (`canPause`) and **Skip** on any —
  `Button(intent:)` with `WorkoutPauseResumeIntent` / `WorkoutSkipIntent`
  (`WorkoutActivityIntents.swift`, compiled into the app and the widget extension). The
  intent runs in the app and calls `WorkoutRemote`: the open player's engine, else the
  kept workout's, caught up to now first; then the state is saved, the cues are scheduled
  again and the activity redrawn (`paused` shows "Paused" and a still clock).
- **Kept:** the engine's state is saved on every move (`ActiveWorkoutStore`); a relaunch
  shows it above the tab bar (§6.45), and Start on the same session carries on.
- **Controls:** `AppFloatingControls` (§6.47) — the one primary button in the step's
  colour, Pause / Skip / ±0.1 km beside each other beneath it, all glass over the step.

### 6.45 Start Workout and Resume

The player is reached from `SessionDetailView`, so every place that opens a session
(Today, Program ▸ Calendar, Log) can start one: **Start workout** (play.fill, prominent,
the modality colour) stands above **Mark Session Complete** in the action bar (§6.47) while
the session is not done. The player grows out of the button (§6.48). It is disabled only when the session's day cannot be placed in the
program. Cards and the long-press menu (§6.43) do not offer it.

A kept workout — one the athlete left with Resume later, or that an earlier launch left
behind — is the **tab bar's bottom accessory** (`tabViewBottomAccessory`,
`KeptWorkoutAccessory` in `ContentView.swift`), so the way back is on every tab: play.circle.fill
(checkmark.circle.fill when it ended unsaved), the session's name over "Resume · Step 4 of 9"
("Review · Finished · save it"), and a ⋯ menu with **Discard workout**. A tap opens the
player, which grows out of the accessory. With the bar minimised it is one line. It goes
once the workout is saved or discarded, or after a day. `KeptWorkout.shared` publishes the
record; `ActiveWorkoutStore` writes it on every save and clear, so no screen reads the file.
Until 1.37 this was a card at the top of Today, which only Today showed.

Settings ▸ **Workout** holds the player's cues on this phone: Count in before work, Count
in after Start, Voice (`WatchCueSettings`; the Apple Watch keeps its own).

### 6.46 (unused)

### 6.47 Floating Controls and the Action Bar

**Glass is for what floats over content; cards stay solid.** Two places qualify, both in
`AppCard.swift`:

- **`.appActionBar { … }`** — a screen's bottom bar: its main action and at most one beside
  it, large, in glass, with the content scrolling and fading out beneath (`safeAreaBar`).
  No background of its own. Session detail (Start workout · Mark Session Complete), the
  session preview (confirm · Search Again), the program preview (Start this program) and
  Workout complete (Confirm & complete / Done) use it; a screen has one.
- **`AppFloatingControls { … }`** — the same grouping without the bar, for controls laid
  over a screen: the workout player's (§6.44).

```swift
.appActionBar {
    Button { start() } label: { Label("Start workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
        .appButton(.primary)
        .tint(ModalityStyle.color(for: session.modality))
}
```

**Rules**

- Buttons inside are ordinary `.appButton(_:)` (§6.6); the container makes them glass
  (`\.appButtonsFloat`) and blends neighbours (`GlassEffectContainer`). Never
  `.buttonStyle(.glass…)` at a call site.
- A message in the bar (an error line) is plain text above the buttons. A setting in the
  bar — the preview's "Also add … to my profile" toggle — sits on a glass surface of its own.
- Content cards, rows and sheets are never glass.

### 6.48 Sheets, Pushes and Zoom

**How a screen arrives says what it is** (`AppNavigation.swift`).

| Arrives as | When | How |
|---|---|---|
| Full-height sheet | A flow or a screen in its own right: the builder, a preview, a session, a workout, Preview ▸ Adjust (a form taller than half a screen) | `.sheet` alone |
| `.appSheet(.compact)` | A short choice with nothing to type: Move, the player's Finish | half height, grabber |
| `.appSheet(.flexible)` | Reference, a short list or a small form: the set logger, a standard's result, the check-in, a day's sessions, a philosophy, an exercise from the chart | half height, pulls up, grabber |
| Push (`.appPush(item:)`) | A further step **inside** a sheet that owns a `NavigationStack`: an exercise's reference, a swap | Back button; never a sheet on a sheet |
| Zoom (`.appZoom(from:in:)`) | A detail that belongs to the row or card that opened it | grows from its source |

Zoom sources today: Today's session card → the session; an Analytics card → its detail
(`AnalyticsDetailCard`, built in); a workout row → the workout (`appZoomScope` on Log,
`appZoomSource` on the row); Start workout → the player; the kept-workout accessory → the
player. Under Reduce Motion `appZoom` does nothing and the system's own transition runs.

**Rules**

- Cancel leads, the confirming action trails, in every sheet's toolbar.
- A view writes no `.presentationDetents` or `.navigationTransition` itself
  (`DesignTokenTests`).
- A screen that can be both pushed and presented takes `pushed:` and owns its
  `NavigationStack` only when presented (§6.14).

### 6.49 Pager

**Anything paged sideways has a visible control.** `AppPager.swift`:

- **`AppPager(pages:selection:) { page in … }`** — one page at a time, full width, a
  paging scroll view (`scrollTargetBehavior(.paging)` + `scrollPosition`). `selection` is
  the page on show; setting it from outside scrolls there.
- **`AppPagerHeader(pages:selection:unit:onTitle:) { title }`** — a chevron either side of
  a title naming the page; the chevrons dim at the ends, and the title is a button when
  `onTitle` is given (back to today, back to the current week). `unit` words the
  chevrons for VoiceOver ("Previous day").
- **`Paging`** — which pages there are and where a step lands, pure (`PagingTests`):
  `dayRange` (the program's span around today, clamped to eight weeks either way, today
  always a page; a week either way without a program), `week(around:)` (Monday to Sunday
  as day offsets), `step`.
- **`fitsPage: true`** makes the pager as tall as the page on show rather than the
  tallest page, for pages of very different heights: Today's rest day beside a day of
  three sessions left a gap over whatever followed.

Today's days and Program ▸ Calendar's weeks use it. Both were hand-rolled `DragGesture`s
with no control until 1.38: nothing said another day was there.

### 6.50 Week Strip

`Views/WeekStrip.swift`, under Today's pager header: Monday to Sunday of the week on show,
one mark a day under its letter — done (an emerald checkmark), planned (a dot in the
session's modality colour), rest (a dash) — today's letter amber, the selected day on a
filled ground. A tap selects the day, so the
strip is the day pager's second control. Days outside the pager's range are dimmed and do
nothing. A day is done once every session on it is.

### 6.51 Row Actions

**A gesture is a shortcut, never the only way.** Every action a swipe or long press holds
has a visible twin, built into the row's own component:

| Where | Visible | Shortcut kept |
|---|---|---|
| Session card, Calendar day row | "…" (`SessionActionsMenu`), "+ Add session" on a rest day (§6.43) | long press |
| Session detail's exercise row | leading log circle (logs, or opens the logger); the row opens the exercise; trailing "…" (Log, Swap, About) | swipes |
| Log ▸ Linking | "…" on a linked pair, a suggestion and a loose workout (Unlink, Open Workout); **Link…** a button on a declined workout too | swipe to unlink, long press |
| Standard detail's result | "…" (Edit, Delete) | swipe |
| Set logger's set | `minus.circle` | swipe |
| Profile ▸ Injuries' custom flag | remove button | swipe |
| Profile ▸ Schedule's session chip | a menu of Rest · Short · Long · Mobility, the current one ticked | — |

**Rules**

- The "…" is `ellipsis` in a 44 pt target at the trailing edge, secondary colour, labelled
  "<name> actions" for VoiceOver ("Session actions" on a card); its items are the gesture's, in the same order.
- One destructive item on a row is a plain button with the destructive role; a list of
  them does not get an `EditButton` — these lists live in sheets and sub-tabs whose
  toolbars are taken, and a per-row control needs no mode.
- A value with a fixed set of choices is a menu with the current one ticked, never
  tap-to-cycle (the schedule chips cycled until 1.38: Short to Rest was three taps).
- No footer explains a gesture with symbols; if a control needs explaining, make it
  visible.

### 6.52 Tips

TipKit, **two tips, each shown once** (`MaxDisplayCount(1)`), and gone for good as soon as
the athlete does the thing:

- `SessionActionsTip` — on today's first session card, pointing at its "…".
- `ChartScrubTip` — in line (`TipView`) between the Progress chart and its readout; a
  popover covered the card it was explaining.

A tip teaches a control that is already visible; it never stands in for one. A third tip
needs one of these to go. `Tips.configure()` runs at launch; debug builds take
`SIMCTL_CHILD_TC_TIPS=show|hide` so a screenshot has every tip or none.

### 6.53 Today

**The day's session first, then what waits for an answer, then three numbers.**
`Views/Today/` — `TodayView` (the screen), `TodaySessionCard`, `TodayInbox`,
`TodaySummary`. One 1,040-line file until 1.39.

1. **Where the athlete is**: the program's name over "Week 3 · Build". The date is the
   pager's title (§6.49), not a second heading.
2. **The day** — pager header, week strip (§6.50), then the day's sessions.
   `TodaySessionCard`: the modality capsule, the session's icon and name, minutes and
   exercise count, its "…" (§6.43). **The session to do next carries Start workout**, in
   its modality colour, which opens the player (§6.44) straight from the tab; the card
   itself still opens the detail. A done session shows its emerald mark and no button;
   a later day's session none either.
3. **The inbox** (`TodayInbox`): workouts that look like planned sessions and results to
   confirm, three of each at most, each row the shared component (§6.34, the match
   suggestion row); the rest are in Log ▸ Linking and Profile ▸ Standards.
4. **Three tiles** (`TodaySummary`, `TodayTile`): Readiness, Adherence, Progress — one
   number or mark each in its status colour (`AppFont.metricCompact`), a line under it,
   and a tap into the Analytics section that explains it. A tile with nothing to say
   shows a dash, never a zero. They were three full cards, and the session shared the
   screen with three dashboards.

**Rules**

- Today holds no detail an Analytics section already has; a tile links there.
- Start is on the card only when the session can be started today; nothing on Today
  starts a past or future day's session.

### 6.54 Session Detail: After the Session

`SessionDetailView` is the header, then the exercises. What is answered once the work
is done — "done as written?" for a contract session (or its lifts), the notes, the
fatigue — is one **After the session** disclosure under the exercises: closed while the
session is untouched, open by itself once something is logged, a workout is linked or
the session is done. Its label's second line says what is inside ("Done as written,
notes, fatigue"). Until 1.39 Progress and Session Notes were two sections that appeared
from nowhere on completion, and a note could not be written beforehand.

### 6.55 Program Builder

`Views/ProgramBuilder/` — `BuilderState` (the draft and what is valid),
`ProgramBuilderFlow` (the shell), one file a step (`BuilderMethodologyStep`,
`BuilderScheduleStep`, `BuilderConstraintsStep`, `BuilderReviewStep`);
`Views/ProgramSettingsSheet.swift` is the settings sheet that shared its file.

- **Step indicator** (`BuilderStepIndicator`), the navigation bar's title: "Step 2 of
  4 · Schedule" over four capsules, amber up to the current one. Read as one element
  by VoiceOver.
- **The way forward is the action bar** (§6.47): "Next", and on the last step "Preview
  program" — disabled while the step is not valid (`BuilderState.entryReady` on the
  last: the method's required movements ticked). It was a text button in the toolbar,
  and the last step had a second button in its list.
- **A methodology card says what it asks**: its icon, name, the comparable facts
  `/philosophies/glance` serves ("12 wk · 3 days/wk · 30 min", `PhilosophyGlance.facts`,
  the ideal of each) and two lines of its summary; selected is the accent border, tint
  and a filled check, never colour alone. The (i) opens the methodology sheet (§6.18).
- Debug builds open the builder on launch with
  `SIMCTL_CHILD_TC_BUILDER=<step>[:<philosophy id>]`.

**Selection cards** everywhere (the builder's methodologies, Profile ▸ Equipment's
profiles) are `.appCard(compact:border:tint:)` with a check mark when chosen.
Replace and Add session (`ReplaceWorkoutSheet`) search with the system's `.searchable`
and switch Browse / Search with `AppSubTabPicker`; its own search field is gone.

### 6.56 Motion Helpers and the Completion Moment

`AppMotion.swift` (§7.5). Where each goes:

- **Numbers that change while on screen** take `appNumeric(value:)`: Today's three tiles,
  Recovery's readiness score, Load's totals, done of scheduled, the player's clocks and
  counts, Workout complete's sets. A number that only ever arrives with its screen needs
  nothing.
- **A symbol that follows a state** is one `Image` with a computed name and
  `appSymbolReplace(value:)` — never two images in an `if`: the exercise row's log circle,
  mark complete, a linked pair, the week strip's day mark (`WeekStrip.Status` is the
  value), the player's pause / play. `appSymbolBounce` is for what was earned (Workout
  complete's check and records).
- **Card stacks** — Today's dashboard and the four Analytics sections — wrap their cards
  in `AppScrollFade { … }` inside the stack, so a card added later gets it. Lists of rows
  do not.
- **Every `Chart`** ends with `.appChartEntry()`. It masks, so it never changes the
  chart's layout, and the mask is gone once the reveal is over.

**The completion moment.** A session is finished behind a cover — the detail sheet, the
player — so its card would change unseen. `AppState.justCompleted` holds the key
(`markSessionComplete`, `finishWorkout`; cleared by undo), and Today draws that session
as not yet done (`isShownComplete`) until Today is uncovered: then, after 450 ms, the
card's stripe turns from its modality colour to emerald, the check scales in, Start
workout leaves and the week strip's dot becomes its check, in one `springStandard`. The
success haptic stays with the tap that finished it. Under Reduce Motion the same change
crossfades.

### 6.57 Accessibility Helpers and the Largest Sizes

`AppAccessibility.swift`. A view writes none of this by hand:

| Need | Helper |
|---|---|
| A control drawn under 44 pt | `.appTapTarget()` — the frame takes the tap |
| A text button in running content | `.appTapSlop()` — the tap area grows, nothing moves |
| A value, its unit and its caption that are one fact | `.appStat("6.9 hours, down 25 percent")` — one element, in words (`SpokenUnit.text` spells "h", "km", "bpm") |
| A row that acts on a tap gesture | `.appTapRow(selected:)` — one element, a button, selected when it is |
| A chart | `.appChartSummary(label, summary)` — what it draws as the label, its numbers as the value, built by `ChartSummary` (`range`: low to high and the latest; `series`: first to last; `shares`: each part's percent) |
| A status told by colour alone | `ColorTwin(symbol:)` beside it — drawn only under Differentiate Without Colour |
| A row of tiles | `AppAdaptiveStack` — a row at the standard sizes, a leading column at the accessibility sizes; `AppAdaptiveGrid(columns:)` drops to one or two columns |

**Every chart has a summary**; a chart without one reads as nothing or as each mark in
turn. A status that already has words or its own symbol (the status badges, the week
strip's check, dot and dash) needs no twin.

**At the accessibility sizes** (`dynamicTypeSize.isAccessibilitySize`) the text takes the
width. The rules the pass at the largest size settled:

- A row that cannot fit is an `AppAdaptiveStack`; its leading item takes
  `.frame(maxWidth: .infinity, alignment: .leading)` instead of a `Spacer`, which would
  give the column a height.
- A capsule's or chip's label is one line (`.lineLimit(1)`, with `.fixedSize()` or
  `.minimumScaleFactor(0.7)`); a row of chips scrolls sideways (the period picker).
- An icon column is `.frame(minWidth:)`, never a fixed width: a scaled symbol in a fixed
  frame draws over its text.
- A title beside paging chevrons says less — Today's date is "Wed, Nov 11" — instead
  of wrapping inside a word.
- A card's trailing action moves up beside its status (Today's session card: the "…"),
  so the name has the card's width.

Standard sizes are unchanged by all of it; check both when a row changes.

### 6.58 Widgets: Rendering Modes and the Lock Screen

- **Tinted and clear.** In `accented` and `vibrant` rendering the system draws a widget
  in one tint, so a hue carries nothing. What the widget is about — today's session's
  stripe and icon, the week's done marks, a ring — is `.widgetAccentable()`; done is a
  checkmark, never emerald alone; a mark that is white on a hue in full colour reads
  `widgetRenderingMode` and becomes one filled symbol outside it (the week widget's done
  session, `HomeWidgets.swift`), and a missed session says so in its shape ("✕"). Fonts
  are text styles, as in the app.
- **Lock Screen** (`TrainingWidgets/AccessoryWidgets.swift`). *Today* also comes as
  `accessoryRectangular` (the session, its minutes, "Done") and `accessoryInline` (one
  line above the clock: "Clean and Press · 23 min", "Rest day", "Today done"). *Week
  Count* is new: `accessoryCircular` (a capacity gauge, done of the week's sessions),
  rectangular and inline ("Week 3 · 2 of 3 done"). `AccessoryText` is the one wording;
  both read `WidgetDataStore`, as the home-screen widgets do, and say "Open Training
  Companion" when the stored week is over.

---

## 7. Motion & Animation

### 7.1 Rules

- **Springs are the standard**, three of them, in `AppAnimation`
  (`AppAnimationSettings.swift`). A view never writes `withAnimation {` or a curve of its
  own (`DesignTokenTests`). Until 1.35 this section banned springs while the code was six
  of them.
- **Reduce Motion is decided in one place**: with it on, every spring preset is
  `crossfade`, so no caller asks.
- Nothing moves that the athlete did not cause or that did not just arrive.

| Preset | What | Use |
|---|---|---|
| `springStandard` | response 0.45, damping 0.82 | State changing in place: a card expanding, a selection moving |
| `springSnappy` | response 0.35, damping 0.86 | A small, quick answer to a tap: a toggle, a chip, a tab |
| `layoutChange` | response 0.5, damping 0.88 | Content arriving, leaving or moving in a list |
| `crossfade` | ease in-out, 0.2 s | Loaded content fading in; every spring under Reduce Motion |
| `tick` | linear, 1 s | A clock's hand between two seconds (the player's countdown ring) |
| `chartEntry` | response 0.7, no bounce | A chart drawing itself the first time it appears (§7.5) |

### 7.2 Standard Transitions

```swift
// State change (completion, toggle)
withAnimation(AppAnimation.springSnappy) { isComplete = true }

// A row arriving or leaving
.animation(AppAnimation.layoutChange, value: rows)

// Tab switch, sheet, push: the system's — do not override
```

### 7.3 Loading States

A screen waiting for its content shows that content's shape, redacted
(`redacted(reason: .placeholder)`), never a spinner: `AppLoadingState` (§6.3) draws three
cards or seven rows with a slow pulse (`AppAnimation.shimmer`, the one curve that is not a
spring; still under Reduce Motion). It shows only while there is nothing on screen — a
pull to refresh keeps the content and the system's own indicator.

### 7.4 Haptics

`AppHaptics` is the one API; a touch answers what happened, never decorates.

| Call | When |
|---|---|
| `selection()` | A picker, a sub-tab, a chip changing |
| `light()` | A gesture taking hold: pull-to-refresh triggering, a page turning |
| `medium()` / `rigid()` | A committed action: a set logged, a step advanced |
| `success()` | Work finished: a session saved, a refresh done, a link confirmed |
| `warning()` / `error()` | A refusal, a failed save |

Pull-to-refresh goes through `AppRefresh.perform` (light on trigger, 600 ms minimum,
success at the end).

### 7.5 Small Motions

One modifier each, in `AppMotion.swift`, timed by an `AppAnimation` preset and still under
Reduce Motion. A view never writes `.contentTransition(`, `.symbolEffect(` or
`.scrollTransition(` of its own (`DesignTokenTests`). Where each is used: §6.56.

| Modifier | What | Under Reduce Motion |
|---|---|---|
| `appNumeric(value:countsDown:)` | A number rolls to its new value (`springSnappy`); without `value`, the roll alone, for a clock its owner already animates | Fades |
| `appSymbolBounce(value:)` | A symbol bounces once: something was earned | Nothing |
| `appSymbolReplace(value:)` | One image whose symbol follows a state: pause / play, linked or not, a day's mark | Fades |
| `appSymbolSpin(isActive:)` | A symbol turns while work runs | Still |
| `AppScrollFade { … }` / `appScrollFade()` | A card eases in and out at the scroll's edge (opacity to 0.65, scale to 0.97), settled once a third of it shows | Nothing |
| `appChartEntry()` | A chart is drawn from its leading edge, once | Drawn at once |

---

## 8. Accessibility

- **Dynamic Type:** All `.font()` modifiers use semantic styles (`.subheadline`, `.caption`, etc.) — never `.system(size: 14)` for body text. The system scales these automatically.
- **VoiceOver labels:** Every `Image(systemName:)` that conveys meaning must have `.accessibilityLabel()`. Icon-only buttons must have `.accessibilityLabel()`.
- **Color + icon:** Modality colors are always accompanied by the modality label text or icon. Never color-only meaning.
- **Minimum tap targets:** 44×44pt minimum for all interactive elements: `.appTapTarget()` on a small control, `.appTapSlop()` on a text button in running content (§6.57).
- **The helpers are in `AppAccessibility.swift`** (§6.57): one fact read as one element, a chart's numbers as its value, a symbol beside a colour-only status, rows that stack at the accessibility sizes.
- **Reduce Motion:** asked by no view — the `AppAnimation` presets and the `AppMotion` modifiers answer it (§7.1, §7.5); a zoom falls back to the system's transition.
- **Differentiate Without Colour:** a status that has neither words nor a symbol of its own takes a `ColorTwin` (§6.57).
- **Largest Dynamic Type size:** every tab is laid out at it; a row or chart that changes is checked there as well as at the standard size (§6.57).
- **Charts:** every chart has an `appChartSummary` — what it draws as the label, its numbers as the value.
- **Focus management:** When a sheet is dismissed, VoiceOver focus should return to the triggering element. Use `.accessibilityFocused()` if needed.

---

## 9. Watch-Specific Rules

The watch app shares the same design language but with tighter constraints.

### 9.1 Typography on Watch

Watch uses the same semantic scale but effectively one size smaller:

| Role | Watch modifier |
|---|---|
| Exercise name | `.headline` |
| Load description | `.footnote.monospaced()` |
| Timer countdown | `.system(size: 36, weight: .bold, design: .rounded)` |
| Badge/pill | `.caption2` |

### 9.2 Layout on Watch

- No horizontal scroll. Everything fits in the 44mm/45mm/49mm width.
- Three-tab `TabView(.page)` for the active workout (exercise / progress / metrics).
- `.fullScreenCover` for rest timer — non-dismissable by back gesture.
- One primary action per screen. No more than two buttons visible at once.

### 9.3 Color on Watch

Same modality colors, but use them more sparingly — the watch face is small. The 2pt color stripe on cards translates to a 3pt stripe (slightly more prominent). HR zone colors are the primary semantic layer during active workout.

### 9.4 Results on Watch

A test step says what it is for under its prescription: "Best 7:32 · 7:00 for
advanced" (`WatchExercise.standard`, the server's words) in `.caption2`, yellow —
the one test accent on the watch, never a level colour. At the end of a test
session `SessionCompleteView` lists each standard with what the watch captured
(tap one to enter it with the crown: `ResultEntryView`), then **Save Results** /
**Not a test** in place of *Save Workout* — still two buttons, as §9.2 asks. The
answer travels in the summary (`standardResults`); the phone's §6.34 row is where an
unanswered one is decided.

### 9.5 Motion on Watch

No custom animations. Use system defaults only. Haptics replace visual feedback for confirmations — do not add both haptic and animation for the same event.

### 9.6 The step page (one page for every step)

A step is drawn as the Garmin draws it, from its package's screen spec
(`WatchSpecText`, docs/watch.md): the title line (`.headline`, two lines at most — the
name and the title parts the spec names: side, load, wave %, zone, pack), two fields side
by side (a `.caption2` secondary label over a 30 pt rounded semibold monospaced value,
the second right-aligned; one field when the spec has one), a `Divider` for the rule, and
two lines (`.footnote`, then `.caption2` secondary). A test's line is the §9.4 yellow.
Under it, `StepControlsView`: **Start** until a clocked step runs, then one prominent
button in the modality colour that says what the spec's LAP will do (Complete Set n,
Start/End Hold, + Round / + Lap, Last Round / Last Lap, Switch Side, Next, Finish), and a
plain **Skip** beside it — still two buttons (§9.2). `DataPageView` and `StepControlsView`
(`Views/StepPageView.swift`) replaced the eight views the watch chose by slot type; a new
template is drawn there, never in a view of its own.

While a lead-in counts (`WorkoutSessionState.leadInLeft`: Countdown Start after Start, or
a rest's last three seconds), the vocabulary's word ("Work in 3", "2", "1") stands over
the buttons in `.title3` rounded semibold in the modality colour, and Start is hidden
until the clock runs.

### 9.7 Settings and the lead-in

The watch's Settings (`WatchSettingsView`, `WatchCuePlayer.swift`) is the last menu row
of the Today list before Sync: **Lead-in**, **Countdown Start** and **Voice** as system
toggles, a footer saying what each does, and **Try it**, which plays the count. The values
live on the watch (`@AppStorage`, `WatchCueSettings`), as the Garmin's live on the Garmin.
A count is `.click`, the go `.start` (both sound unless the watch is silenced); with Voice
on, `AVSpeechSynthesizer` also says the word, ducking other audio. The rule is
`WatchCues.leadIn`, the Garmin's `Cues.leadIn`: change it in `watch_vocabulary.json`.

### 9.8 One engine, two apps

`WorkoutSessionState` (with `+Page` and `+Clock`) runs every step on the watch and in the
phone's player (§6.44): both apps compile it, the watch through its membership
exceptions. It never touches a device — haptics, tones and words go through
`WorkoutCueOutput` (`WatchCueOutput` here, `PhoneCueOutput` on the phone) — and its clock
is `tick()` once a second plus `catchUp(to:)`, which runs missed seconds silently. A
change to how a step behaves is made there, once, with a case in `WorkoutEngineTests`;
`WorkoutManager` keeps only what is the watch's own (HealthKit, the route, the metronome).
