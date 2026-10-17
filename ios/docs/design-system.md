# iOS Design System

The visual language, interaction patterns, and implementation decisions for the TrainingCompanion iPhone and Apple Watch apps. Derived from and consistent with `docs/frontend-design.md` (the web design system), translated into SwiftUI idioms. All screens — phone and watch — reference this document.

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Color Architecture](#2-color-architecture)
3. [Semantic Color Systems](#3-semantic-color-systems)
4. [Typography](#4-typography)
5. [Spacing & Layout](#5-spacing--layout)
6. [Component Patterns](#6-component-patterns)
7. [Motion & Animation](#7-motion--animation)
8. [Accessibility](#8-accessibility)
9. [Watch-Specific Rules](#9-watch-specific-rules)

---

## 1. Design Philosophy

Six principles, inherited from the web app. The iOS translation follows each.

### 1.1 Substance Over Decoration

Every visual element earns its place by conveying information or guiding attention. No gradients for depth, no blurs for atmosphere, no shadows as decoration.

**iOS:** Don't add `.shadow()`, `.blur()`, or layered backgrounds unless they carry meaning. SwiftUI's default `List` and `NavigationStack` chrome is acceptable — fight the urge to over-style it.

### 1.2 Dark-First, Theme-Capable

The app defaults to dark mode. Light mode is supported via the system setting — do not override it unless explicitly required. All colors are defined as named Color assets with automatic dark/light variants. No hardcoded hex values in views.

```swift
// Correct
Color("Background")
Color("CardSurface")
Color("PrimaryText")

// Wrong
Color(hex: "#141620")
Color(.systemBackground)   // only for native-feeling chrome, not custom surfaces
```

### 1.3 Dense but Breathable

Training data is complex. The interface must show it compactly without feeling cramped. Rule: tight internal padding within components, generous spacing between components.

- Session card internal padding: 12pt
- Gap between session cards: 8pt
- Gap between sections on a page: 24pt

### 1.4 Progressive Disclosure

Show only what the user needs at each level. The Today tab shows session cards. Tapping opens SessionDetail. Each exercise shows its load description; coaching cue is collapsed until tapped.

Never show all information at once. Always have a summary state and a detail state.

**Numbers and symbols, not sentences** (2026-10-16). A screen says what a value
is with an SF Symbol and the number — `clock 21/18 min/wk`, `heart.fill 104/135`,
`checkmark.circle 1/1` — and a status with a coloured mark or badge, not a
sentence. No subtitle explains a section ("The blocks this program runs, in
order"), no footnote names where a number came from unless it is the
exception (`iphone` "On device" when the server could not answer), and no
row points to another tab in words. The full sentence goes in the
`accessibilityLabel`. Words stay where a symbol cannot carry them: an
empty state's one line, a coverage reason that tells the athlete what to log,
the server's recommendations.

### 1.5 Motion with Purpose

Animation serves three functions: orientation (where am I?), feedback (did that register?), continuity (what appeared?). No decorative motion.

```swift
// Correct duration range: 0.15–0.25s
withAnimation(.easeOut(duration: 0.2)) { ... }

// Wrong: bouncy springs, long durations, sparkle effects
withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) { ... }
```

### 1.6 Accessibility as Foundation

Dynamic Type supported on all text. VoiceOver labels on every icon-only button. Color is never the sole conveyor of meaning — always paired with an icon or text label.

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

---

## 2. Color Architecture

### 2.1 Named Color Assets

Define these in `TrainingCompanion/Assets.xcassets` as named colors with dark and light variants. Every view uses names, never literals.

| Asset Name | Dark | Light | Usage |
|---|---|---|---|
| `Background` | `#141620` (dark navy) | `#ffffff` | Page backgrounds |
| `CardSurface` | `#1e2030` (lighter navy) | `#ffffff` | Card/panel fills |
| `CardBorder` | `#ffffff1a` (white 10%) | `#e8e8ec` | Card borders |
| `PrimaryText` | `#fafafa` | `#141620` | Main readable text |
| `SecondaryText` | `#8a8fa8` | `#6b7280` | Captions, metadata |
| `Accent` | `#c97d15` | `#c97d15` | Amber primary — identical in both themes |
| `AccentText` | `#c97d15` | `#c97d15` | Load prescriptions, active states |
| `Muted` | `#272a3a` | `#f4f4f6` | Input fills, tab bar fills, skeleton backgrounds |
| `DestructiveRed` | `#ef4444` | `#ef4444` | Errors, destructive actions |
| `CompleteGreen` | `#10b981` | `#10b981` | Completion states (emerald — never changes) |

**Rule:** `Accent` (amber) is the only color that is the same in dark and light mode. This is intentional — brand consistency over theme adaptation.

### 2.2 Opacity Convention

The web uses opacity suffixes (`/10`, `/15`, `/30`) to encode visual hierarchy. In SwiftUI use `.opacity()` or `Color("X").opacity(N)` equivalently:

| Opacity | Use |
|---|---|
| `0.08` | Extremely subtle tint (completion card background) |
| `0.12` | Light semantic background (badge fill) |
| `0.25` | Semantic border (completion border, dashed outline) |
| `0.45` | Interactive border on hover/press state |
| `0.50` | Disabled icons, ghost elements |
| `0.70` | Overlay backdrops behind sheets |

---

## 3. Semantic Color Systems

These use literal `Color(hex:)` values (not named assets) because the specific color IS the information. Used for modality badges, session card top bars, chart series, and phase indicators.

### 3.1 Modality Colors

Exact values match the web `MODALITY_COLORS` table. All iOS screens that show modality identity use these — no approximations.

```swift
// ios/TrainingCompanion/ModalityStyle.swift
struct ModalityStyle {
    let hex: String
    let color: Color
    let label: String
    let icon: String   // SF Symbol name

    static let all: [String: ModalityStyle] = [
        "max_strength":             .init(hex: "#ef4444", label: "Max Strength",     icon: "figure.strengthtraining.traditional"),
        "relative_strength":        .init(hex: "#f43f5e", label: "Relative Strength",icon: "figure.strengthtraining.traditional"),
        "strength_endurance":       .init(hex: "#f97316", label: "Str Endurance",    icon: "dumbbell"),
        "power":                    .init(hex: "#eab308", label: "Power",             icon: "bolt.fill"),
        "aerobic_base":             .init(hex: "#0ea5e9", label: "Aerobic Base",      icon: "figure.run"),
        "anaerobic_intervals":      .init(hex: "#06b6d4", label: "Intervals",         icon: "heart.circle"),
        "mixed_modal_conditioning": .init(hex: "#8b5cf6", label: "Mixed Modal",       icon: "bolt.heart"),
        "mobility":                 .init(hex: "#10b981", label: "Mobility",          icon: "figure.cooldown"),
        "movement_skill":           .init(hex: "#14b8a6", label: "Movement Skill",    icon: "figure.flexibility"),
        "durability":               .init(hex: "#f59e0b", label: "Durability",        icon: "backpack"),
        "combat_sport":             .init(hex: "#ec4899", label: "Combat Sport",      icon: "figure.boxing"),
        "rehab":                    .init(hex: "#84cc16", label: "Rehab",             icon: "cross.case"),
        "kettlebell":               .init(hex: "#6366f1", label: "Kettlebell",        icon: "dumbbell.fill"),
    ]

    static func style(for modalityId: String) -> ModalityStyle {
        all[modalityId] ?? .init(hex: "#8a8fa8", label: modalityId, icon: "square.fill")
    }
}
```

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
    .fill(Color(hex: style.hex))
    .frame(height: 2)

// Badge background
Text(style.label)
    .font(.caption2).fontWeight(.semibold)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(Color(hex: style.hex).opacity(0.15))
    .foregroundStyle(Color(hex: style.hex))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(Color(hex: style.hex).opacity(0.35), lineWidth: 1))

// Icon tint
Image(systemName: style.icon)
    .foregroundStyle(Color(hex: style.hex))
```

### 3.2 Training Phase Colors

A phase has two parts. Its **name** is its methodology's own ("Foundations",
"Transmutation", "Specific"): `ProgramWeek.phaseLabel`, `PhilosophyPhase.name`.
Its **colour** comes from its **kind**, the shared vocabulary in
`data/commons/phase_kinds.yaml`. `PhaseStyle.color(for:)` is the one mapping,
with the same hex values as the web's `lib/phaseColors.ts`:

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
.background(Color("CompleteGreen").opacity(0.08))
.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("CompleteGreen").opacity(0.25)))

// Completion checkmark
Image(systemName: "checkmark.circle.fill")
    .foregroundStyle(Color("CompleteGreen"))
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
carries the colour of the zone it ends). The timeline used to draw slate/sky
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

### 4.2 Color Hierarchy

Three levels of prominence via color, not weight alone:

```swift
Text("Back Squat")           // Primary: Color("PrimaryText")
    .font(.subheadline).fontWeight(.semibold)

Text("5×5 @ 100 kg")        // Accent: Color("AccentText") — load specs
    .font(.caption.monospaced())
    .foregroundStyle(Color("AccentText"))

Text("Linear progression")   // Secondary: Color("SecondaryText")
    .font(.caption)
    .foregroundStyle(Color("SecondaryText"))
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

| Value | Use |
|---|---|
| `4pt` | Between badge and label, icon and text |
| `8pt` | Between exercise rows, between session cards |
| `12pt` | Between related form elements |
| `16pt` | Between sections within a card |
| `24pt` | Between major sections on a page |

### 5.3 Corner Radius

| Radius | Use |
|---|---|
| `6pt` | Small chips, filter pills |
| `10pt` | Buttons, input fields |
| `12pt` | Session cards, exercise rows |
| `16pt` | Sheet header elements, large cards |
| `999pt` (`.clipShape(Capsule())`) | Badges, modality pills, toggle-style buttons |

**Rule:** Nested elements use the same or smaller radius than their parent.

---

## 6. Component Patterns

### 6.1 Session Card

```swift
struct SessionCard: View {
    let session: WatchSession
    let style: ModalityStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Modality color bar — 2pt stripe, full width
            Rectangle()
                .fill(Color(hex: style.hex))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 8) {
                // Header row: icon + name + duration pill
                HStack {
                    Image(systemName: style.icon)
                        .foregroundStyle(Color(hex: style.hex))
                        .font(.subheadline)
                    Text(session.archetypeName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color("PrimaryText"))
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.estimatedMinutes) min")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color("Muted"))
                        .clipShape(Capsule())
                }

                // Modality badge
                ModalityBadge(style: style)
            }
            .padding(12)
        }
        .background(Color("CardSurface"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color("CardBorder"), lineWidth: 1))
    }
}
```

### 6.2 Modality Badge

```swift
struct ModalityBadge: View {
    let style: ModalityStyle

    var body: some View {
        Text(style.label)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(hex: style.hex).opacity(0.15))
            .foregroundStyle(Color(hex: style.hex))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: style.hex).opacity(0.35), lineWidth: 1))
    }
}
```

### 6.3 Empty State

Used when there's no program, no exercises match a filter, etc. Always provides a clear path forward.

**Use the system's `ContentUnavailableView`** — its title, symbol, description and
actions scale with Dynamic Type and read correctly to VoiceOver. This section used to
prescribe a hand-built `VStack` with `.font(.system(size: 48))`, against §8; Analytics ▸
Program, Progress and Blocks each carried a copy until 2026-10-17.

```swift
ContentUnavailableView {
    Label("No active program", systemImage: "chart.bar.doc.horizontal")
} description: {
    Text("Generate a program to measure it here.")
} actions: {
    Button("Go to Program") { router.showProgram(.calendar) }
        .buttonStyle(.bordered)
}
```

Inside a card, where the full view is too large, an empty chart is a `.title2` symbol
over one `.footnote` line — never a fixed point size.

### 6.4 Section Header

Uppercase caption labels above groups of content — same pattern as the web's section labels.

```swift
Text("THIS WEEK")
    .font(.caption).fontWeight(.semibold)
    .tracking(0.8)
    .foregroundStyle(Color("SecondaryText"))
    .padding(.horizontal, 16)
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
    .foregroundStyle(Color("AccentText"))
```

### 6.6 Primary Button

```swift
Button("Generate Program") { ... }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(Color("Accent"))
    .foregroundStyle(.white)
    .font(.subheadline).fontWeight(.semibold)
    .clipShape(RoundedRectangle(cornerRadius: 10))
```

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
.background(Color(TrainingPhase.deload.color).opacity(0.12))
.clipShape(RoundedRectangle(cornerRadius: 10))
.overlay(RoundedRectangle(cornerRadius: 10)
    .stroke(Color(TrainingPhase.deload.color).opacity(0.25), lineWidth: 1))
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
  header), never in a `VStack` above it — Log ▸ Workouts' scope line is the
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
  gesture change with a real drag, not by reasoning.
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
- **A planned session uses `ModalityStyle.icon(for:)`** — there is no recorded
  activity yet, and the modality is the whole truth about it.

**When NOT to use it**

Not for programme sessions, archetypes or anything in the Program tab: those
have a modality and no activity, so the modality icon is the correct and only
answer.

---

### 6.13 Tab Structure

**Five tabs, and configuration is not one of them.**

| Tab | Root | Sections (`AppSubTabs`) |
|---|---|---|
| **Today** | `TodayView` | — (cards: sessions, readiness, suggestions, development, progression) |
| **Program** | `ProgramView` | Overview · Calendar · History |
| **Analytics** | `AnalyticsView` | Program · Progress · Blocks · Load · Recovery |
| **Log** | `LogView` | Workouts · Suggestions · Sessions |
| **Profile** | `ProfileView` | Athlete (incl. injuries and HR zones) · Equipment · Schedule · Standards |

The section names and their order are the web's, item for item
(`docs/information-architecture.md` §2): a section is renamed or moved on
both clients in the same change. Program's Current became Calendar and
gained Overview (`ProgramOverviewTab`: methodology, phases, priority mix),
and Analytics' Overview became Load, on 2026-10-13. Every section is a
deep link — `program?section=`, `analytics?section=` (`overview` and
`development` are kept as aliases), `log?section=`, `profile?section=`.

`AppRouter.Tab` enumerates them; `MainTabView` in `ContentView.swift` reads the
selection from the router (§6.9). The first case is still named `.dashboard`
because the widgets deep-link to it; its label is "Today".

**Settings is pushed from Profile's toolbar gear** (`Views/SettingsView.swift`):
Connections (integration toggles), Devices & Sync (pairing, Sync Now, last
sync, sync details, debug log), Notifications (local session reminders —
`NotificationManager.swift`, rescheduled from the stored program on every
program change), Appearance, Account (sign out). Until
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
.sheet(item: $exerciseSheet) { item in
    ExerciseDetailSheet(exerciseId: ex.id, name: ex.name, assignment: item.assignment)
        .environmentObject(appState)
}
```

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

---

## 7. Motion & Animation

### 7.1 Rules

- Duration: 0.15–0.25s. Never longer unless the element itself moves across the screen.
- Easing: `.easeOut` for most transitions (things settle quickly). `.easeInOut` for push/pop navigation.
- Exit animations faster than entry: entry 0.20s, exit 0.15s.
- No bouncy springs for data-driven UI. Springs only for direct manipulation (drag-to-dismiss, pull-to-refresh).

### 7.2 Standard Transitions

```swift
// Sheet present/dismiss
.transition(.move(edge: .bottom).combined(with: .opacity))

// List row appear (staggered)
.transition(.opacity.animation(.easeOut(duration: 0.2).delay(Double(index) * 0.04)))

// State change (completion, toggle)
withAnimation(.easeOut(duration: 0.2)) { isComplete = true }

// Tab switch: use default SwiftUI TabView animation — do not override it
```

### 7.3 Loading States

Use redacted shimmer (`redacted(reason: .placeholder)`) for skeleton loading. Never show spinners for content that loads in <1s.

```swift
if isLoading {
    SessionCardSkeleton()
        .redacted(reason: .placeholder)
        .shimmering()    // requires Shimmer package or manual implementation
} else {
    SessionCard(session: session)
}
```

---

## 8. Accessibility

- **Dynamic Type:** All `.font()` modifiers use semantic styles (`.subheadline`, `.caption`, etc.) — never `.system(size: 14)` for body text. The system scales these automatically.
- **VoiceOver labels:** Every `Image(systemName:)` that conveys meaning must have `.accessibilityLabel()`. Icon-only buttons must have `.accessibilityLabel()`.
- **Color + icon:** Modality colors are always accompanied by the modality label text or icon. Never color-only meaning.
- **Minimum tap targets:** 44×44pt minimum for all interactive elements. Use `.frame(minWidth: 44, minHeight: 44)` on small controls.
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

---

## Color Utility

Add this extension to both targets:

```swift
// ios/TrainingCompanion/Extensions/Color+Hex.swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

---

### 6.15 Analytics Card, Status and the Program Section

**One card, one status vocabulary.** A card's status or source mark (a
verdict badge, "On device", a trend) goes in its `trailing:` slot, never in a
content row; nothing inside a card draws a box of its own (the coverage notice
lost its dashed border, Last Night its stage tiles, HRV and resting HR their
second title, 2026-10-17); every capsule is `TintCapsule`. `AppCard.swift` holds `AnalyticsCard`
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
the coverage reason copy. `ProgressionView` reads its colours from it.

**Analytics ▸ Program** (`Views/AnalyticsProgramTab.swift`) lays out the
server's `GET /api/analytics/program` document — how closely the plan is
being followed (`ProgramAnalyticsModels.swift`, every section decoded on its
own so a failed or future section cannot blank the screen):

The sections, titles and order are the web's (`components/analytics/ProgramTab.tsx`);
the phone lacked Standards and Session shapes, half of Movement and the
intensity footer until 2026-10-16.

- *Program*: the program header (§6.28) with plan fidelity as its footer —
  each field actual / ideal with a mark.
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
- *Movement*: sets and minutes done against planned by pattern (planned the
  grey track, done over it), balance ratios, unilateral share, assumed minutes.
- *Session shapes* (`SessionShapesCard`): done of scheduled, duration against
  the archetype's estimate (amber past ±25 %), HR, the lead lift's est. 1RM.
- *Load* (TSB read in the phase's terms).

**Analytics ▸ Progress** (`Views/ProgressionView.swift`) reads the same
document for what it measures progress by, after the review's score (§6.25)
and measures — the web's Progress tab:

- A section per methodology (`MethodologySectionView`, `Views/AnalyticsProgramSections.swift`): measurable of applicable, then a `ProgressEntryCard` per metric that applies — a
  summary that opens `MeasureDetailView` (§6.37): the status badge, where the
  measure stands in its own currency (the lead lift's latest value and its
  name; movements practised of the program's and `lock.open` the ones opened;
  standards met of those with a target), the trend, the headline pill, a
  `Sparkline`, and the `CoverageNoticeView` when nothing measures it yet.
  The detail has the exercise picker (a menu), the actual-against-expected
  chart (actual green, expected indigo dashed, deload points hollow), the
  stall line, every movement and standard (each opens its sheet), every line
  of evidence and the About section. Entries the program does not schedule
  fold behind one "N not in this program" row.
- *Standards* (`ProgramStandardsCard`): the program's own (`primary`), the
  rest behind "More standards"; per standard the modality's symbol and the
  name, the value as the server prints it, a chevron, the level badge and the
  gap on a second line, and the block's `Sparkline`. A row presents
  `StandardDetailSheet` in place (§6.32), which draws the ladder; rows drew
  one each, and jumped to Profile, until 2026-10-17.
- *Exercises* (`ExerciseProgressSection`, from `GET /progression/exercises`):
  a segmented filter on three counts — with data, so far, in the program (the first that shows something until the athlete picks), and a row
  per exercise — latest value, this week's prescription as the target, a
  sparkline, HR from a linked workout, the finding's change line. "No trend
  yet" when logged but unmeasured, "Not tracked" when nothing is logged. A
  row pushes `ExerciseHistoryView`: the standing, every logged session as a
  chart (the target as a dashed rule) and as rows, "How to do it"
  (`ExerciseDetailSheet`, §6.14) and the finding's words as About.

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

**A changed profile offers to rebuild the plan from this week, never
silently.** `Views/RegenerateOfferCard.swift` sits at the top of the Athlete
(which holds injuries), Equipment and Schedule tabs whenever `AppState.constraintDifferences`
is non-empty — `ProgramConstraintsDiff` (the phone's copy of the web's
`lib/programConstraintsDiff.ts`) compares the profile's level, equipment, days
per week and injuries with the `constraints` the active program was built for,
which the envelope carries since saves round-trip it. The card names each
difference ("Equipment: 5 items → 1 added, 1 removed"), and one tap runs
`AppState.regenerateFromCurrentWeek`: a non-persisting generate for the
remaining weeks with the merged constraints (continuing the phase and
week-in-phase), spliced onto the weeks and days already behind the athlete
(`Regeneration.splice`, which never replaces a day before today) and saved through the revision-checked PUT, so the
old plan stays in Program ▸ History. The Program settings sheet offers the same
action above its destructive full regenerate.

Rules: the comparison is the shared one, never a per-screen heuristic; the
card appears only where a constraint is edited; a blend regenerates as a
blend (`philosophy_ids` + weights), not as its first source.

---

### 6.18 Methodology Sheet

**The program explains itself.** `Views/PhilosophyDetailSheet.swift` — a
methodology's summary, emphasis (modalities), core principles and how it
trains (intensity model, progression philosophy). Three presenters: the
builder's philosophy cards (step 1) and the book on the program header
card (§6.28) on Program ▸ Overview and Analytics ▸ Program; a blend turns
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
`Views/LogView.swift`, the third tab, three sections:

- *Workouts* (`LogWorkoutsTab`, the list that was Analytics ▸ Workouts until
  2026-10-01): recorded activities (`WorkoutRow`, §6.23) with
  swipe-to-delete and the TRIMP badge; the period, sort and activity filter
  are the toolbar's filter menu (§6.24) beside the `.fit` importer; a row
  pushes `WorkoutDetailView`.
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
- *Sessions* (`LogSessionsTab`): what was logged against planned sessions
  across the program, newest completion first — `LogSessions.rows` builds
  the rows from the server's session logs: the session's name when the key
  resolves in the current program, the date and source, and one line per
  exercise with content ("Back Squat — 3 sets · 3×5 @ 80 kg"). A row that
  resolves opens the session detail.

Analytics keeps Program · Progress · Blocks · Load · Recovery: it
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
the fourth Analytics section. Program is the current block measured against
what it is for; Blocks is how the athlete has developed across programs —
the question the history tables exist to answer. The server reads them as
one document (`GET /api/analytics/development`, `src/analytics/development.py`)
and the web's Analytics ▸ Development lays out the same one; nothing is
computed on the phone (`DevelopmentModels.swift` decodes it tolerantly,
section by section, like `ProgramAnalyticsModels`).

Four cards, each an `AnalyticsCard` (§6.15):

- *Blocks*: a strip across the top — each activation's share of the span in
  its colour — then a row per block: methodology names, span, weeks, sessions
  done of those the block reached (`checkmark.circle 3/10`; the percentage is
  VoiceOver's), "never reached" for the rest (`forward.end`), and a `current`
  `TintCapsule` on the active one.
- *Lifts across blocks*: a chip row (44 pt targets) of every lift and currency
  — rounds, minutes, km — with points in the window; the chart plots the
  heaviest completed set's est-1RM per session over real dates with the
  blocks as `RectangleMark` bands. Under it the trend as an arrow and
  %/session (`.subheadline`), and one row per block: first → last, best,
  sessions, Δ.
- *TRIMP per week by block*: weekly TRIMP as bars coloured by block over the
  whole history (Load's card is the last 12 weeks); hidden when no workout
  carried load.
- *Standards over time*: per standard the name, the latest result, the level
  badge and a chevron, levels gained under it, then its history chart
  (`StandardHistoryChart`); a row opens the standard (Profile ▸ Standards,
  through the router), as does "Log a result". Hidden when nothing is logged.

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

`StartPhasePicker` (in `ProgramBuilderFlow.swift`) picks where a program
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


---

### 6.23 Workout Row and Linked Workouts

**A recorded workout looks the same wherever it is listed.**
`Views/WorkoutRow.swift` is one recorded workout: the activity icon (§6.12),
what the device recorded, date, time and duration, distance and average HR,
the source chip, the linked-session chip and the TRIMP badge. Log ▸ Workouts
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
`Views/WorkoutFilterMenu.swift`. Log ▸ Workouts used to stack three bands
under the title — the section picker, the period pills and a scroller of
sort and activity chips — so the list started a third of the way down the
screen. The system's own apps (Mail, Files, Photos) put filtering behind
one `line.3.horizontal.decrease.circle` button.

- **One value.** `WorkoutListFilter` (period, sort, activity) is held by the
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
`ScoreExplanation` in `Views/ProgressionView.swift`, with the band from
`ProgressionScore` (`ProgressionScore.swift`). Today's Progress card no longer
shows the score (2026-10-16): it shows the methodology's headline measure, worded
by the server (`headlineSummary`), and Adherence beside it carries completion. Analytics ▸ Progress read 70 "On Track" in week 1 for an athlete who
had done every session: compliance × 0.4 plus a neutral 50 × 0.6 for a measure
with no data, a number nobody could reconstruct. Since 2026-10-16 the score is
the measures' trends alone; before any has one there is no score, and the card
says why under "Not enough data yet".

- **The words are the server's** (`score_breakdown`, `score_status`,
  `scope_label`, `pending_measures` from `src/analytics/review.py`; the phone
  leaves out `purpose`, the intro sentence, since 2026-10-16),
  so the web says the same; the phone only lays them out. Older servers send
  none of them and the card falls back to the thresholds alone.
- **The reason is always shown; the sum is folded.** One line under the band
  ("Every session due so far is done; no lift or skill trend yet") answers the
  common question; "How is this scored?" opens the parts and the three bands,
  the current one bold. A single part (sessions only) is the summary already
  and gets no sum row.
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

- **The Phases card** (`ProgramOverviewTab`, an `AnalyticsCard`, §6.15) is one row per
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
`Views/ProgramHeaderCard.swift` — an `AnalyticsCard` headed "Program": the
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
- *Analytics ▸ Program* (first card): every tag — how it progresses,
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
- *The planned session* (`WorkoutCompletion.Match`), as an `AnalyticsCard`
  with a status capsule:
  - **Linked** (green): the server, the watch or another client already
    linked it; the session row carries the check. A match the server dates
    to an earlier block shows no session of this program (§6.23).
  - **Suggested** (orange): the server's weak match, with *Not this* on the
    row and **Confirm & complete** (green) as the sheet's primary action;
    the day's other open sessions are offered under it.
  - **Unlinked**: no suggestion, but sessions planned that day are open —
    each with *Link*.
  - **Extra**: nothing open that day.
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
server's five-zone arrays). Analytics ▸ Program's intensity card draws it over the block
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

- **`AnalyticsDetailCard`** (`AppCard.swift`) is an `AnalyticsCard` that is
  one `NavigationLink`: the whole card is the target, `chevron.right` follows
  the header's badge, `accessibilityHint` names the destination. Its content
  is the summary state only — the current value in its own currency, a status,
  a trend, a `Sparkline`, at most one line of words (a coverage reason) — and
  holds nothing interactive, since the card itself is the button.
- **A row that opens something** inside a card (an exercise, a standard) is
  its own `NavigationLink` or button with a trailing chevron, not the card.
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
- A detail a deep link can open, for screenshots and other screens:
  `analytics?section=progress&measure=<entry id>` and `&exercise=<id>`,
  `analytics?open=readiness|sleep|hrv|resting-hr|checkins`
  (`AppRouter.openAnalyticsDetail`; each section pushes its own).

Users: Analytics ▸ Progress's measure cards (`MeasureDetailView`), its
Exercises rows (`ExerciseHistoryView`), its Standards rows (the standard's
sheet, §6.32); Analytics ▸ Recovery's readiness (`ReadinessDetailView`, §6.21),
sleep (`SleepDetailView` — Sleep Debt, Last Night and Sleep Stages were three
cards), HRV and resting heart rate (`RecoveryTrendDetailView`, one view for
both, like `RecoveryTrendChartView`) and "All check-ins" (`CheckInHistoryView`;
the card keeps the last seven `CheckInRow`s); Analytics ▸ Load's Performance
Management (`PMCDetailView`: today's CTL, ATL and TSB — whole numbers, one
decimal under ten — over a compact `PMCChart` on the card, the full chart with
a drag-to-read rule on the screen); and Program ▸ Overview's phases (§6.26,
before this section was written).

Where two cards were the same data two ways they became one card with a
segmented display picker (§6.8's "mode inside content"): Load's **Mix**
(modality share of minutes · activity hours, the period's) and **Weekly**
(sessions · TRIMP, twelve weeks; "On device" beside the header only for TRIMP,
whose request is its own).

Terms that are not a measure — TRIMP, CTL, ATL, TSB, readiness, HRV, resting
HR, sleep debt — take their About from `vocabulary.TERMS`, served by the
static `GET /api/analytics/vocabulary` and cached in
`AppState.analyticsTerms` (`AboutText(terms:from:)`).
