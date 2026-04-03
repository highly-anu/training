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

```swift
enum TrainingPhase: String {
    case base, build, peak, taper, deload, maintenance, rehab, post_op
    
    var color: Color {
        switch self {
        case .base:        return Color(hex: "#0ea5e9")
        case .build:       return Color(hex: "#f59e0b")
        case .peak:        return Color(hex: "#ef4444")
        case .taper:       return Color(hex: "#22c55e")
        case .deload:      return Color(hex: "#94a3b8")
        case .maintenance: return Color(hex: "#a1a1aa")
        case .rehab:       return Color(hex: "#84cc16")
        case .post_op:     return Color(hex: "#a855f7")
        }
    }
    
    var label: String { rawValue.capitalized.replacingOccurrences(of: "_", with: "-") }
}
```

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

```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color("SecondaryText"))
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("PrimaryText"))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color("SecondaryText"))
                .multilineTextAlignment(.center)
            if let label = actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .tint(Color("Accent"))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
```

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

### 9.4 Motion on Watch

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
