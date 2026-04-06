# iOS Interactive Design Best Practices

Great questions — the "twitchy" feeling you're describing is almost always a combination of missing spring physics, wrong animation durations, and lack of gesture velocity handling. Here's how Apple's first-party apps handle these, and how to centralize it all.

## 1. Centralized Design System (do this first)

Before touching any gesture code, create a single source of truth. This is the #1 thing that will keep your tabs consistent.

```swift
// AppAnimationSettings.swift
import SwiftUI

enum AppAnimation {
    // Use these everywhere — never hardcode .easeInOut in views
    static let springStandard = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    static let springSnappy   = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0)
    static let springBouncy   = Animation.spring(response: 0.55, dampingFraction: 0.72, blendDuration: 0)
    static let springGentle   = Animation.spring(response: 0.6,  dampingFraction: 0.9,  blendDuration: 0)

    // For layout changes (cards moving up/down)
    static let layoutChange   = Animation.spring(response: 0.5, dampingFraction: 0.88)

    // NOTE: interactiveDrag is defined here but do NOT apply it as a view-level
    // .animation(_:value:) modifier on swipeable cards — see section 3 for why.
    static let interactiveDrag = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.25)
}

enum AppHaptics {
    static func light()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()    { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid()     { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft()      { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum AppMetrics {
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let swipeThreshold: CGFloat = 80       // points before commit
    static let swipeVelocityThreshold: CGFloat = 400  // pts/sec for flick commit
}
```

**Key point:** Understanding SwiftUI's `spring(response:dampingFraction:)` is crucial. `response` is roughly the duration in seconds (how long it takes to settle). `dampingFraction` of 1.0 = no bounce, 0.7 = noticeable bounce, 0.5 = very bouncy. Apple's system animations sit around 0.82–0.86 damping. Below 0.7 starts feeling unprofessional for UI (fine for playful moments).

## 2. Pull to Refresh

For iOS 15+, SwiftUI's built-in `.refreshable` is the right answer — it matches system behavior automatically (bounce, the stretched indicator, release threshold). Don't build your own unless you need custom visuals.

```swift
.refreshable {
    AppHaptics.light()           // fire on pull trigger
    await viewModel.reload()
    AppHaptics.success()         // fire on completion
}
```

**Minimum display time** — if your refresh is too fast, add a floor so the spinner doesn't flash:

```swift
.refreshable {
    AppHaptics.light()
    async let delay: () = Task.sleep(nanoseconds: 600_000_000)
    await viewModel.reload()
    _ = try? await delay
    AppHaptics.success()
}
```

Start the timer with `async let` at the top so it runs concurrently with the real work. Await it at the end — if the work already took longer than 600 ms it's a no-op.

### Critical: don't change layout-affecting state at the start of the block

`.refreshable`'s async block fires **at pull threshold**, which may be before the user releases their finger. Any `@Published` state change that alters the ScrollView's content height will fight the ongoing pull-to-refresh animation and cause the content to snap or get stuck.

```swift
// BAD — state change at top collapses/expands content while animation is active
.refreshable {
    AppHaptics.light()
    currentIndex = 0          // ← triggers re-render mid-animation → snap
    await reload()
}

// GOOD — all layout-affecting state changes go after the work completes
.refreshable {
    AppHaptics.light()
    async let delay: () = Task.sleep(nanoseconds: 600_000_000)
    await reload()
    _ = try? await delay
    currentIndex = 0          // ← ScrollView is back at rest, safe to update
    AppHaptics.success()
}
```

This is especially dangerous when the state change causes a conditional view switch (e.g. `if isLoading { LoadingView() } else { ContentView() }`). If `isLoading` flips true at the top of the block, `ContentView` is unmounted and the scroll height collapses — the ScrollView position becomes invalid mid-animation. Fix: **only show the loading state on the initial load** (when no data has arrived yet), not during subsequent refreshes:

```swift
// BAD — shows loading spinner on every refresh, collapsing the scroll content
if isLoading {
    LoadingView()
} else {
    ContentView()
}

// GOOD — loading spinner only when there is nothing to show yet
if isLoading && data == nil {
    LoadingView()
} else {
    ContentView()   // stays mounted during pull-to-refresh even while isLoading == true
}
```

### Coexistence with horizontal swipe gestures

If the view inside a ScrollView also has a horizontal `DragGesture` (e.g. a swipeable card stack), the gesture **must** be `.simultaneousGesture`, not `.gesture`. Using `.gesture` gives the DragGesture exclusive ownership of the touch event, which prevents the ScrollView from receiving the vertical pull that triggers pull-to-refresh:

```swift
// BAD — DragGesture steals the touch, pull-to-refresh can't fire from this area
.gesture(DragGesture(minimumDistance: 10) { ... })

// GOOD — both recognizers run in parallel; direction guards sort out who acts
.simultaneousGesture(DragGesture(minimumDistance: 10) { ... })
```

Inside `onChanged`, keep the direction guard (`abs(h) > abs(v)`) so the horizontal gesture only updates `dragOffset` when motion is clearly horizontal. Vertical pulls fall through to the ScrollView untouched.

## 3. Swipeable Cards (fixing the twitchy flip)

The twitchy feeling comes from three things: (1) using `.easeInOut` or no animation during the drag, (2) only checking distance not velocity, and (3) snapping back with too stiff a spring.

```swift
struct SwipeableCardStack: View {
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0

    private var cardWidth: CGFloat { UIScreen.main.bounds.width - 32 }

    var body: some View {
        let gap: CGFloat = 14
        let exitDistance = cardWidth + gap

        ZStack {
            // Peek card — rendered behind, offset to the incoming side
            peekCard
                .offset(x: dragOffset + peekSign * exitDistance)
                .allowsHitTesting(false)

            // Main card — tracks finger 1:1, no implicit animation modifier
            mainCard
                .offset(x: dragOffset)
        }
        .clipped()
        .contentShape(Rectangle())
        // Use .simultaneousGesture if this ZStack lives inside a ScrollView
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let h = value.translation.width
                    guard abs(h) > abs(value.translation.height) else { return }
                    dragOffset = h   // 1:1 tracking — no resistance multiplier needed
                }
                .onEnded { value in
                    let h = value.translation.width
                    guard abs(h) > abs(value.translation.height),
                          abs(value.predictedEndTranslation.width) > AppMetrics.swipeThreshold
                          || abs(value.velocity.width) > AppMetrics.swipeVelocityThreshold else {
                        withAnimation(AppAnimation.springStandard) { dragOffset = 0 }
                        return
                    }
                    let goNext = h < 0
                    AppHaptics.soft()
                    withAnimation(AppAnimation.springSnappy) {
                        dragOffset = goNext ? -exitDistance : exitDistance
                    }
                    // Delay index update until exit animation has settled (~1× response)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        currentIndex += goNext ? 1 : -1
                        dragOffset = 0
                    }
                }
        )
    }
}
```

**Critical fixes for the twitchy feel:**

- **`minimumDistance: 10`** — without this, the gesture fires on any micro-movement. This alone fixes ~40% of twitch complaints.
- **`predictedEndTranslation`** uses UIKit's physics prediction. If the user flicks fast, this extrapolates where the finger would land. Much better than raw translation.
- **Velocity check** — `value.velocity` (iOS 17+) lets a fast flick commit even if distance is short. 400 pts/sec is a good threshold.
- **Haptic on commit, not on drag** — firing haptics during `onChanged` feels awful. Only fire at the moment of decision.
- **1:1 finger tracking** — set `dragOffset = h` directly without a resistance multiplier. The card follows the finger exactly; spring physics only apply at commit/cancel.

### Do NOT use `.animation(_:value:)` on the card for dragOffset

It seems natural to apply `.animation(AppAnimation.interactiveDrag, value: dragOffset)` to the card so it "follows the finger with physics." In practice this causes two bugs:

1. **Snap-back on vertical scroll.** If a brief horizontal component during a vertical scroll sets `dragOffset` to a small non-zero value, the view-level animation fires when `dragOffset` resets to 0 in `onEnded` — producing a visible spring snap that has nothing to do with a swipe.

2. **Double-animation on commit.** When `dragOffset = 0` is set in the `asyncAfter` (after the index advances), the view-level `interactiveDrag` spring re-animates the new card from the exit position back to centre — perceived as an unwanted bounce-back.

The fix: use only **explicit** `withAnimation(...)` calls at commit and cancel. During drag, `dragOffset = h` updates synchronously with the finger (1:1, no implicit animation). This is the correct pattern for direct manipulation — the spring only plays at decision points.

### Remove the isAnimating lock

An `isAnimating: Bool` flag that blocks new gesture events causes the twitchy interrupted-snap behavior:

```swift
// BAD
.onChanged { guard !isAnimating else { return } ... }
```

Remove it. Spring animations handle interruption gracefully by themselves — a new drag will naturally override the in-flight offset value and the spring re-targets. The only thing you need is the `asyncAfter` to delay the index update until the exit animation has settled.

## 4. Vertical Layout Changes (smoothing out collapse/expand)

When a card expands and others below slide up, the twitchiness usually means: (a) you're animating `.frame` or `.padding` directly with the wrong spring, or (b) SwiftUI is recomputing layout without a stable identity.

```swift
struct ExpandableCard: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(AppAnimation.layoutChange) {
                        isExpanded.toggle()
                    }
                    AppHaptics.light()
                }

            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(AppMetrics.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }
}

// Parent list
struct CardList: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    ExpandableCard(item: item)
                        .id(item.id)  // stable identity — critical
                }
            }
            .animation(AppAnimation.layoutChange, value: items.map(\.isExpanded))
        }
    }
}
```

**Why this fixes twitchiness:**

- `.id(item.id)` gives SwiftUI stable identity so it animates position changes instead of recreating views.
- `.animation(_, value:)` scoped to a specific value is much more predictable than the deprecated implicit `.animation(_)`.
- Asymmetric transitions let collapse be faster than expand, which feels more responsive.
- `response: 0.5, dampingFraction: 0.88` is the sweet spot — long enough to read as "physical," damped enough to not wobble.
- Use `LazyVStack` not `VStack` for long lists, but be aware lazy views can cause jumps; for short lists (<20 items) regular `VStack` animates more smoothly.

One gotcha: if you animate height changes and see a "pop" at the end, it's usually because a child view has an intrinsic size that changes discretely. Wrap the content in `.fixedSize(horizontal: false, vertical: true)` or give it a `.frame(minHeight:)`.

### ForEach stable identity

`id: \.offset` on an `.enumerated()` array is **unstable** — SwiftUI recreates views instead of animating them when items reorder. Prefer:

```swift
// BAD
ForEach(Array(items.enumerated()), id: \.offset) { _, item in ... }

// GOOD — use a stable semantic key
ForEach(items, id: \.stableKey) { item in ... }   // string/UUID key
ForEach(items.indices, id: \.self) { i in ... }   // index, fine for static lists
ForEach(dayNames, id: \.self) { day in ... }      // string value, always stable
```

## 5. Consistent Look Across Tabs

The cleanest pattern is a custom `ViewModifier` applied to the content inside each `NavigationStack`:

```swift
struct AppTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(.accentColor)
        // NOTE: Do NOT add .background(Color(.systemGroupedBackground)) here.
        // It overrides the view's own background with a dark-grey grouped color
        // in dark mode and can cause NavigationStack large titles to disappear.
        //
        // NOTE: Do NOT add .toolbarBackground(.visible, for: .navigationBar).
        // It conflicts with .navigationBarTitleDisplayMode(.large) and hides headers.
        // Apply toolbarBackground modifiers on individual views that actually need them.
    }
}

extension View {
    func appTabStyle() -> some View { modifier(AppTabStyle()) }
}
```

Apply `.appTabStyle()` inside each `NavigationStack`, on the root content view (not on the `NavigationStack` itself):

```swift
NavigationStack {
    MyContentView()
        .navigationTitle("Home")
        .appTabStyle()   // ← here, after navigationTitle
}
```

## Quick Reference: Animation Values That Feel Right

| Use case | response | damping |
|---|---|---|
| Following a finger (drag) | 0.28 | 0.86 (use `interactiveSpring`) |
| Snap-back after release | 0.45 | 0.82 |
| Layout reflow (cards moving) | 0.5 | 0.88 |
| Sheet/modal presentation | 0.55 | 0.85 |
| Playful bounce (mascot, success state) | 0.55 | 0.72 |
| Micro-interaction (tap feedback) | 0.3 | 0.9 |

## Haptic Reference

| Interaction | Haptic |
|---|---|
| Pull-to-refresh trigger | `.light()` |
| Pull-to-refresh complete | `.success()` |
| Swipe card commit | `.soft()` |
| Tap to open sheet | `.light()` |
| Segmented control / picker change | `.selection()` |
| Session / task marked complete | `.success()` |
| Destructive confirm | `.medium()` |
