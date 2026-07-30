# Frontend Design System

A complete record of the visual language, interaction patterns, component architecture, and implementation details used in this project. Written to be portable — everything here can be used to establish the same design system in a new project from scratch.

**Scope:** the web app (`frontend/`) only. iOS and watchOS have their own design docs at `ios/docs/design-system.md` and `ios/docs/ios-interactive-design.md`. Modality and phase hex values are shared across all three platforms — see §8.9 before changing any of them.

### Reading the divergence callouts

Where this document and the code disagree, the divergence is marked inline at the rule it affects, in one of two forms:

> **Code diverges — code is correct.** The rule below has been rewritten to describe what the code does. No code change needed.

> **Code diverges — doc is correct.** The rule below is the target. The code has drifted and should be brought back. Tracked in `docs/frontend-fix-plan.md`.

Anything not marked is believed to match the code as of 2026-07-30.

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Technology Stack](#2-technology-stack)
3. [Color Architecture](#3-color-architecture)
4. [Typography](#4-typography)
5. [Spacing & Layout](#5-spacing--layout)
6. [Border, Radius & Shadow](#6-border-radius--shadow)
7. [Component Library](#7-component-library)
8. [Semantic Color Systems](#8-semantic-color-systems)
9. [Motion & Animation](#9-motion--animation)
10. [Interaction Patterns](#10-interaction-patterns)
11. [State Variations](#11-state-variations)
12. [Data Visualization](#12-data-visualization)
13. [Page & Layout Patterns](#13-page--layout-patterns)
14. [Responsive Design](#14-responsive-design)
15. [Icon System](#15-icon-system)
16. [Implementation Checklist](#16-implementation-checklist)
17. [Tab Header Pattern](#17-tab-header-pattern)

**Companion doc:** `docs/frontend-fix-plan.md` — the prioritized work list for every **"doc is correct"** divergence flagged below, i.e. the places where the code should change to meet this spec.

---

## 1. Design Philosophy

### 1.1 Core Principle: Substance Over Decoration

The UI exists to serve data, not to look impressive. Every visual element — color, motion, shadow, border — earns its place by conveying information or guiding attention. Decoration for its own sake is a failure mode.

Practical consequences:
- Color is used semantically (modality type, phase, completion state) rather than aesthetically
- Motion communicates transitions and state changes, not personality
- Whitespace communicates grouping and hierarchy, not generosity
- Shadows are used sparingly to establish elevation, not depth for its own sake

### 1.2 Dark-First, Theme-Capable

The application is built dark-first. The default theme is a dark navy/slate with amber primary. A light theme is available, along with Military (olive + monospace) and Zen (warm off-white + serif) variants. All color decisions use CSS custom properties — no hardcoded hex values in components.

This means:
- Never use raw Tailwind color classes (`bg-zinc-900`, `text-white`) for structural UI — use semantic tokens (`bg-background`, `text-foreground`)
- Reserve raw color classes for *semantic* color systems (modality badges, phase indicators, completion states) where the specific color is the point
- Every component works in all four themes without modification

### 1.3 Dense but Breathable

The app displays complex training data (7-day schedules, multi-session days, exercise lists with load prescriptions) in a compact interface. The challenge is presenting density without feeling overwhelming.

Solution: tight internal spacing within components, generous spacing between components. A session card is compact (`p-3`). The gap between session cards is comfortable (`space-y-2`). The gap between sections on a page is generous (`space-y-6`).

### 1.4 Progressive Disclosure

The interface reveals complexity as needed. The dashboard shows a week at a glance. Clicking a day opens a panel with sessions. Clicking a session opens the full detail. Each level only shows what the user needs at that moment.

This shapes component design: always have a collapsed/summary state and an expanded/detail state. EmptyState components should offer a clear path forward. Loading states should show the skeleton of what's coming.

### 1.5 Motion with Purpose

Animation serves three functions:
1. **Orientation** — page transitions tell the user where they are in the application
2. **Feedback** — micro-interactions confirm that an action was registered
3. **Continuity** — staggered list entries help the eye follow newly appearing content

Animation never serves as flair. Durations are kept short (150–300ms). Nothing blocks the user. Exit animations are always faster than entry animations.

### 1.6 Accessibility as Foundation

Radix UI primitives handle ARIA roles, keyboard navigation, and focus management. The design builds on top of this — it does not override it. Focus rings are always visible. Color is never the sole conveyor of meaning (icons and text labels accompany color).

> **Partially resolved 2026-07-30.** This was the least-honored principle in the document. Radix carries roles, keyboard, and focus for free, which made the first 80% feel solved; the remaining 20% — the parts Radix cannot infer — had never been done.
>
> | Gap | Status |
> |---|---|
> | Reduced motion unimplemented (FIX-2) | ✅ `MotionConfig` at the app root + `DumbbellLoader` gated |
> | Light-mode semantic text at ~2.3:1 (FIX-1) | ✅ every semantic system on the `-700`/`-300` pairing |
> | Icon-only buttons unnamed (FIX-8) | ✅ all 7 `size="icon"` buttons labeled |
>
> All three are closed. The remaining accessibility work is verification rather than repair — a contrast regression test (so this cannot silently return) and a keyboard/VoiceOver pass. Tracked in `docs/frontend-fix-plan.md`.

**What "foundation" obliges, concretely.** A component is not finished until:

- Every interactive element has an accessible name — visible text, or `aria-label` when the control is icon-only
- Every animation over a few pixels of travel has a reduced-motion answer (§9.10)
- Every color-carried meaning is duplicated in text or icon
- Every text/background pair clears 4.5:1 **in all four themes**, not just the one being developed in
- Focus is visible on every focusable element (Radix gives this; do not remove it with `outline-none` unless a `focus-visible:ring` replaces it)

---

## 2. Technology Stack

```
React 19 + Vite 8 + TypeScript 5.9
Tailwind CSS v4 (@tailwindcss/vite)
shadcn/ui (Radix UI primitives + custom styling)
Framer Motion v12
next-themes v0.4          (theme class switching — see §3.1)
tw-animate-css v1.4       (keyframe utilities)
@dnd-kit/core v6          (drag-and-drop)
Recharts v3               (data visualization — see §12)
react-leaflet v5 + leaflet v1.9   (GPS route maps)
CesiumJS (runtime CDN load, no npm dep)  (Swiss 3D terrain)
date-fns v4               (all date math — never hand-rolled)
react-day-picker v9       (calendar primitive behind ui/calendar.tsx)
Lucide React v1.7 (icons)
class-variance-authority (CVA, component variants)
clsx + tailwind-merge (cn() utility)
```

**Data / infra deps** (not design-system concerns, listed so the stack reads complete): `@tanstack/react-query` v5, `zustand` v5, `@supabase/supabase-js` v2, `axios`, `msw` v2, `react-router-dom` v7.

**Radix primitives in use:** alert-dialog, checkbox, dialog, label, popover, progress, scroll-area, select, separator, slider, slot, switch, tabs, toggle, tooltip.

### The `cn()` Utility

Every component uses `cn()` for conditional class composition. It merges Tailwind classes correctly (later classes win) and handles conditionals cleanly.

```typescript
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

Usage:
```tsx
className={cn(
  'base classes always applied',
  isComplete && 'bg-emerald-500/10 text-emerald-500',
  isToday && 'bg-primary text-primary-foreground',
  className   // always accept external className as override
)}
```

---

## 3. Color Architecture

### 3.1 CSS Custom Properties

> **Code diverges — code is correct.** An earlier revision of this section showed `:root` holding the *dark* palette and a `.light` class overriding it. That is backwards. `:root` holds the **light** palette and `.dark` overrides it — the conventional cascade, and the one `next-themes` expects. Section rewritten to match `src/styles/globals.css`.

All colors live in `src/styles/globals.css` as CSS custom properties. Components reference tokens, never raw values.

**How themes are applied.** `next-themes` writes a single class onto `<html>`. `:root` is the light baseline; `.dark`, `.military`, and `.zen` override it. Configured in `src/App.tsx:45`:

```tsx
<ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false}
               themes={['light', 'dark', 'military', 'zen']}>
```

**"Dark-first" means dark is the default theme, not that dark is the base cascade layer.** `defaultTheme="dark"` and `enableSystem={false}` — a first-time visitor gets dark regardless of OS preference. Light is a deliberate opt-in, not a fallback.

**Tailwind v4 token bridge.** Tailwind v4 has no JS config; utilities are generated from an `@theme inline` block that maps each custom property to a `--color-*` name. This block is load-bearing — a token with no entry here produces no utility class:

```css
@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card:       var(--card);
  /* … popover, primary, secondary, muted, accent, destructive, border, input, ring */

  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);

  --font-sans: var(--font-sans-family);
  --font-mono: var(--font-mono-family);
}
```

Radius utilities derive from a single `--radius` token, so a theme can reshape the whole app by setting one value (Military uses `0.25rem`, Zen `0.75rem`).

**Light theme (`:root` — the base cascade):**
```css
:root {
  --background:        oklch(1 0 0);
  --foreground:        oklch(0.141 0.005 285.823);
  --card:              oklch(1 0 0);
  --card-foreground:   oklch(0.141 0.005 285.823);
  --primary:           oklch(0.769 0.188 70.08);     /* amber-500 */
  --primary-foreground: oklch(0.282 0.065 51.617);
  --secondary:         oklch(0.967 0.001 286.375);
  --muted:             oklch(0.967 0.001 286.375);
  --muted-foreground:  oklch(0.552 0.016 285.938);
  --destructive:       oklch(0.577 0.245 27.325);
  --border:            oklch(0.92 0.004 286.32);
  --input:             oklch(0.92 0.004 286.32);
  --ring:              oklch(0.769 0.188 70.08);
  --radius:            0.5rem;
  --font-sans-family:  ui-sans-serif, system-ui, sans-serif;
  --font-mono-family:  ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, monospace;
}
```

**Dark theme (`.dark` — the default):**
```css
.dark {
  --background:        oklch(0.141 0.005 285.823);  /* dark navy */
  --foreground:        oklch(0.985 0 0);             /* near-white */
  --card:              oklch(0.21 0.006 285.885);    /* slightly lighter navy */
  --card-foreground:   oklch(0.985 0 0);
  --primary:           oklch(0.769 0.188 70.08);     /* amber — unchanged */
  --primary-foreground: oklch(0.282 0.065 51.617);
  --secondary:         oklch(0.274 0.006 286.033);
  --muted:             oklch(0.274 0.006 286.033);
  --muted-foreground:  oklch(0.705 0.015 286.067);   /* NOT 0.552 — brighter than light */
  --destructive:       oklch(0.704 0.191 22.216);
  --border:            oklch(1 0 0 / 10%);           /* white 10% */
  --input:             oklch(1 0 0 / 15%);           /* white 15% */
  --ring:              oklch(0.769 0.188 70.08);
}
```

Note `--muted-foreground` is *lighter* in dark mode (0.705) than in light mode (0.552). Both are pulling away from their own background — the token is "recede by roughly this much," not a fixed gray.

**Key principle:** `--primary` (amber) is identical in light and dark. Brand color is consistent. Military and Zen deliberately break this — they are character themes, not light/dark variants of one identity.

### 3.1.1 Character Themes (Military, Zen)

Military and Zen go beyond token swaps. They are the only places in the app where a theme owns typography, texture, and scrollbar chrome:

| | Military | Zen |
|---|---|---|
| `--primary` | olive `oklch(0.58 0.13 130)` | sage `oklch(0.55 0.1 155)` |
| `--radius` | `0.25rem` (hard corners) | `0.75rem` (soft) |
| Font | `"IBM Plex Mono"` — sans *and* mono slots | `"Lora", Georgia, serif` |
| Body texture | 20px radial dot-grid in primary @ 14% | two soft radial gradient washes (sage NW, stone SE) |
| Letter-spacing | `-0.01em` (tightened) | `0.012em` + `line-height: 1.65` |
| Scrollbar | 4px, square thumb | 6px, pill thumb |

**Rule for new themes:** override tokens in a class block, and only reach for `body` background-image / letter-spacing if the theme is a *character* theme. Light and dark must stay texture-free.

**Web fonts:** `IBM Plex Mono` and `Lora` are loaded from Google Fonts in `index.html:9-11` (`preconnect` ×2 + one stylesheet `<link>`, `display=swap`). This is the only external font dependency in the app. Note it loads **unconditionally**, so light and dark users pay for two fonts they never render — see `docs/frontend-fix-plan.md` for the deferred-load option.

### 3.2 Tailwind Token Mapping

| Tailwind class | What it maps to |
|---|---|
| `bg-background` | Page background |
| `bg-card` | Card/panel surface |
| `bg-muted` | Subtle backgrounds (inputs, tabs, skeletons) |
| `bg-primary` | Primary action backgrounds |
| `bg-accent` | Hover state backgrounds |
| `text-foreground` | Primary text |
| `text-muted-foreground` | Secondary/caption text |
| `text-primary` | Brand-colored text (load specs, active states) |
| `border-border` | Default borders |
| `border-input` | Form control borders |
| `ring-ring` | Focus rings |

### 3.3 Opacity Modifier Convention

Opacity suffixes encode information density and hierarchy:

| Suffix | Use |
|---|---|
| `/5` | Extremely subtle background tint (completion states) |
| `/10` | Light semantic background (complete, error bg) |
| `/15` | Badge backgrounds (standard) |
| `/20` | Hover variant of semantic bg |
| `/30` | Semantic borders (complete, dashed outlines) |
| `/40` | Hover borders, interactive borders |
| `/50` | Mid-opacity icons, disabled states |
| `/60` | Active/selected borders |
| `/80` | Overlay backdrops |

Example — completion state:
```tsx
// All three use the same /N scale, just different properties
className="border-emerald-500/30 bg-emerald-500/10 text-emerald-500"
//         ← border      →  ← bg          →  ← text: full opacity
```

---

## 4. Typography

### 4.1 Font Stack

**Default (all themes):**
```css
font-family: ui-sans-serif, system-ui, sans-serif;
font-family: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, monospace;
```

**Military theme override:**
```css
font-family: "IBM Plex Mono", ui-monospace, monospace;
```

**Zen theme override:**
```css
font-family: "Lora", Georgia, serif;   /* sans slot only — mono stays system */
```

Light and dark render entirely in system fonts — zero layout cost, no FOUT. Military and Zen use web fonts served from Google Fonts, declared once in `index.html` (see §3.1.1). Military overrides *both* the sans and mono slots with IBM Plex Mono; Zen overrides only the sans slot, so load prescriptions stay in the system mono face and remain scannable.

### 4.2 Scale

| Role | Size | Weight | Tracking | Usage |
|---|---|---|---|---|
| Page title | `text-2xl` (24px) | `font-bold` | `tracking-tight` | Dashboard H1 |
| Section label | `text-xs` uppercase | `font-semibold` | `tracking-wider` | Cards headers, group labels |
| Card title | `text-sm` (14px) | `font-semibold` | — | Component titles |
| Body | `text-sm` (14px) | `font-medium` | — | Primary readable text |
| Label | `text-sm` (14px) | `font-medium` | — | Form labels |
| Caption | `text-xs` (12px) | — | — | Metadata, timestamps |
| Micro | `text-[10px]` | `font-semibold` | — | Badges, tags, tight labels |
| Mono | `text-xs font-mono` | — | — | Load specs (`3×5 @ 85%`) |

### 4.3 Hierarchy in Practice

Three levels of text prominence, achieved through size + color, never weight alone:

```tsx
<h3 className="text-sm font-semibold text-foreground">    {/* Primary */}
<p  className="text-xs text-muted-foreground">            {/* Secondary */}
<p  className="text-[10px] text-muted-foreground/70">     {/* Tertiary */}
```

Load prescriptions use monospace + primary color to make them scannable at a glance:
```tsx
<p className="text-xs font-mono text-primary">3×5 @ 85% 1RM</p>
```

### 4.4 Truncation

Always truncate text that may overflow its container. Never let text break layout:
```tsx
<p className="text-xs font-semibold truncate">{session.archetype.name}</p>
<div className="min-w-0 flex-1">   {/* flex children need min-w-0 to truncate */}
```

---

## 5. Spacing & Layout

### 5.1 Base Unit

The spacing system is built on `0.25rem` (4px) increments, with `0.5rem` (8px) as the effective base unit for most decisions.

### 5.2 Component Internal Padding

| Component type | Padding |
|---|---|
| Card (standard) | `p-6` (24px) |
| Card (compact) | `p-4` or `p-3` |
| Session card | `p-3` |
| Exercise row | `p-4` |
| Badge | `px-2.5 py-0.5` |
| Badge (small) | `px-1.5 py-0.5` (or `px-2 py-0.5`) |
| Button (default) | `px-4 py-2` (h-10) |
| Button (sm) | `px-3` (h-9) |
| Sheet/panel content | `px-5 py-4` or `p-5` |
| Page content | `p-6` |
| Sidebar nav | `p-2` with `space-y-0.5` |

### 5.3 Gap / Space Scale

| Value | Use |
|---|---|
| `gap-1` / `space-y-1` | Tightest: badge groups, nav items |
| `gap-1.5` / `space-y-1.5` | Icon + label pairs, card header fields |
| `gap-2` / `space-y-2` | Standard within-component spacing |
| `gap-3` / `space-y-3` | Between related elements in a form |
| `gap-4` / `space-y-4` | Between sections within a component |
| `gap-6` / `space-y-6` | Between major sections on a page |
| `gap-1.5` | WeekCalendar day grid |

### 5.4 Layout Structure

**App shell:**
```
┌─────────────────────────────────────────────┐
│ Sidebar (w-56, hidden on mobile)            │
├─────────────────────────────────────────────┤
│ TopBar (h-14, visible on mobile)            │
├───────────┬─────────────────────────────────┤
│           │                                 │
│  Main     │  Right panel (AnimatePresence,  │
│  content  │  w-[420px], slides in/out)      │
│  (flex-1) │                                 │
│           │                                 │
└───────────┴─────────────────────────────────┘
```

**Page content max-width:** `max-w-5xl` on wide pages, `max-w-2xl` on focused flows (builder), `max-w-md` on sheets.

**Standard page structure:**
```tsx
<motion.div className="flex h-full flex-col overflow-hidden">
  {/* Optional sticky header with border-b */}
  <div className="border-b bg-card/50 px-6 py-3 shrink-0">...</div>

  {/* Scrollable content */}
  <div className="flex-1 overflow-y-auto p-6 space-y-6">
    ...
  </div>
</motion.div>
```

---

## 6. Border, Radius & Shadow

### 6.1 Border Radius

| Class | px | Use |
|---|---|---|
| `rounded-sm` | 2px | Almost never |
| `rounded-md` | 6px | Buttons (sm), small chips |
| `rounded-lg` | 8px | Cards, inputs, session cards, dialogs |
| `rounded-xl` | 12px | Large panels, TodaySession card |
| `rounded-full` | 999px | Badges, switches, numbered circles |

**Rule:** Nested elements use the same or smaller radius than their parent. A `rounded-lg` card contains `rounded-md` buttons.

### 6.2 Border Styling

Default border: `border border-border` — one pixel, CSS token.

| Pattern | Use |
|---|---|
| `border-dashed border-border/50` | Empty states, rest day cells |
| `border-dashed border-border/60` | TodaySession rest day |
| `hover:border-primary/40` | Hover state on interactive cards |
| `hover:border-primary/50` | Slightly stronger hover |
| `border-emerald-500/30` | Session complete state |
| `border-destructive/40` | Error/destructive alert |

**Transparent borders on semantic elements:** Using `border border-{color}/30` (not `border-transparent`) means the border slot is always occupied — no layout shift when border appears on hover.

### 6.3 Shadow

Shadows are used minimally:

| Class | Use |
|---|---|
| `shadow-sm` | Cards on hover, TodaySession card |
| `shadow-md` | Popover content, drag ghost |
| `shadow-lg` | Dialog overlays |
| `shadow-xl` | Dragging session card |
| No shadow | Most components at rest |

---

## 7. Component Library

### 7.1 Architecture

Components are Radix UI primitives wrapped with shadcn/ui styling patterns. The wrapping follows three principles:

1. **CVA for variants** — `cva()` defines the variant/size matrix; `cn()` applies it
2. **`className` always forwarded** — every component accepts and applies external `className` as a final override
3. **`asChild` on interactive wrappers** — allows polymorphic rendering (`<Button asChild><Link/></Button>`)

### 7.2 Button

```typescript
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default:     'bg-primary text-primary-foreground hover:bg-primary/90',
        destructive: 'bg-destructive text-destructive-foreground hover:bg-destructive/90',
        outline:     'border border-input bg-background hover:bg-accent hover:text-accent-foreground',
        secondary:   'bg-secondary text-secondary-foreground hover:bg-secondary/80',
        ghost:       'hover:bg-accent hover:text-accent-foreground',
        link:        'text-primary underline-offset-4 hover:underline',
      },
      size: {
        default: 'h-10 px-4 py-2',
        sm:      'h-9 rounded-md px-3',
        lg:      'h-11 rounded-md px-8',
        icon:    'h-10 w-10',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  }
)
```

**Usage patterns:**
- Primary action: `<Button>` (default variant)
- Secondary/nav action: `<Button variant="outline" size="sm">`
- Icon-only: `<Button variant="ghost" size="icon">`
- Destructive: `<Button variant="destructive">`
- In-text link: `<Button variant="link">`

### 7.3 Card

```tsx
<Card>                                          {/* rounded-lg border bg-card shadow-sm */}
  <CardHeader>                                  {/* p-6, space-y-1.5 */}
    <CardTitle />                               {/* text-2xl font-semibold leading-none tracking-tight */}
    <CardDescription />                         {/* text-sm text-muted-foreground */}
  </CardHeader>
  <CardContent />                               {/* p-6 pt-0 */}
  <CardFooter />                                {/* p-6 pt-0 flex items-center */}
</Card>
```

### 7.4 Badge

```typescript
const badgeVariants = cva(
  'inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors',
  {
    variants: {
      variant: {
        default:     'border-transparent bg-primary text-primary-foreground',
        secondary:   'border-transparent bg-secondary text-secondary-foreground',
        destructive: 'border-transparent bg-destructive text-destructive-foreground',
        outline:     'text-foreground',
      },
    },
  }
)
```

Semantic badges (modality, phase) are not built on this variant — they use their own color tokens (see §8).

### 7.5 Tabs

```tsx
<Tabs defaultValue="browse">
  <TabsList className="mx-5 mt-4">                    {/* h-10 rounded-md bg-muted p-1 */}
    <TabsTrigger value="browse" className="flex-1">   {/* active: bg-background shadow-sm */}
      Browse
    </TabsTrigger>
  </TabsList>
  <TabsContent value="browse" className="mt-0">
    ...
  </TabsContent>
</Tabs>
```

**Layout note:** `TabsList` typically gets `shrink-0` when inside a flex column, and `TabsContent` gets `flex-1 flex flex-col overflow-hidden` to fill remaining space.

### 7.6 Sheet

The primary surface for contextual detail panels (replace session, day workout, exercise detail).

```tsx
<Sheet open={open} onOpenChange={onOpenChange}>
  <SheetContent side="right" className="sm:max-w-md flex flex-col p-0">
    <SheetHeader className="px-5 py-4 border-b shrink-0">
      <SheetTitle>...</SheetTitle>
    </SheetHeader>

    {/* Flexible body */}
    <div className="flex-1 flex flex-col overflow-hidden">
      ...
    </div>

    {/* Sticky footer (optional) */}
    <div className="px-5 py-4 border-t shrink-0">
      <Button className="w-full">Confirm</Button>
    </div>
  </SheetContent>
</Sheet>
```

**Width convention:** `sm:max-w-sm` (384px) for simple sheets, `sm:max-w-md` (448px) for sheets with forms or lists.

**Anatomy:** `p-0` on SheetContent + manual padding on children gives full control over what scrolls and what sticks.

### 7.7 Dialog

For confirmations and focused actions. Smaller than sheets.

```tsx
<Dialog>
  <DialogContent className="sm:max-w-md">     {/* max-w-lg default */}
    <DialogHeader>
      <DialogTitle />
      <DialogDescription />
    </DialogHeader>
    {/* body */}
    <DialogFooter>
      <Button variant="outline" onClick={onClose}>Cancel</Button>
      <Button onClick={onConfirm}>Confirm</Button>
    </DialogFooter>
  </DialogContent>
</Dialog>
```

### 7.8 Input

```tsx
<Input
  className="h-9 text-sm"       {/* override size when compact */}
  placeholder="Search…"
  value={query}
  onChange={e => setQuery(e.target.value)}
  autoFocus                       {/* always autoFocus in modals/sheets */}
/>
```

Base: `h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-base focus-visible:ring-2 focus-visible:ring-ring`

### 7.9 Select

```tsx
<Select value={value} onValueChange={setValue}>
  <SelectTrigger className="h-9 text-xs">
    <SelectValue />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="normal">Normal</SelectItem>
  </SelectContent>
</Select>
```

### 7.10 Slider

```tsx
<Slider
  min={15}
  max={120}
  step={5}
  value={[value]}
  onValueChange={([v]) => setValue(v)}
  className="w-full"
/>
```

Track: `h-2 rounded-full bg-secondary`. Range: `bg-primary`. Thumb: `h-5 w-5 rounded-full border-2 border-primary bg-background`.

### 7.11 ScrollArea

Use instead of `overflow-y-auto` when you need styled scrollbars or need to avoid clipping box shadows:

```tsx
<ScrollArea className="h-[calc(100vh-260px)]">
  <div className="space-y-1.5 pb-2">
    {items.map(...)}
  </div>
</ScrollArea>
```

### 7.12 Separator

```tsx
<Separator />                    {/* horizontal, full width, h-[1px] bg-border */}
<Separator orientation="vertical" className="h-4" />
```

---

## 8. Semantic Color Systems

Domain-specific color vocabularies sit on top of the base token system. These use raw Tailwind color classes (not tokens) because the specific color is intentional information.

There are now **six** of them, each owning one axis of meaning. Two colors may look alike across two systems and still mean unrelated things — that is fine, because they never appear on the same axis:

| System | Lives in | Axis it encodes |
|---|---|---|
| Modality (§8.1) | `lib/modalityColors.ts` | *what kind of training* |
| Phase (§8.2) | `lib/phaseColors.ts` | *where in the program* |
| Completion (§8.3) | `lib/completionColors.ts` | *done or not done* |
| Fatigue (§8.4) | `SessionNotes` | *how hard it felt* (subjective, 1–5) |
| HR zone (§8.7) | `lib/hrZones.ts` | *measured intensity* |
| Readiness / status (§8.8) | `lib/statusColors.ts` | *how well is this going* |

### 8.1 Modality Colors

Training modalities are color-coded consistently everywhere: badges, session card top bars, chart series, drag ghost indicators.

The `hex` field is the source of truth for anything that isn't a Tailwind class — chart fills, SVG strokes, inline `style` color bars — and is mirrored into the iOS and watchOS apps (§8.9).

```typescript
// lib/modalityColors.ts
const MODALITY_COLORS: Record<ModalityId, ModalityColor> = {
  max_strength:            { hex: '#ef4444', bg: 'bg-red-500/15',    text: 'text-red-700 dark:text-red-300',       border: 'border-red-500/40',    label: 'Max Strength' },
  strength_endurance:      { hex: '#f97316', bg: 'bg-orange-500/15', text: 'text-orange-700 dark:text-orange-300', border: 'border-orange-500/40', label: 'Strength Endurance' },
  relative_strength:       { hex: '#f43f5e', bg: 'bg-rose-500/15',   text: 'text-rose-700 dark:text-rose-300',     border: 'border-rose-500/40',   label: 'Relative Strength' },
  aerobic_base:            { hex: '#0ea5e9', bg: 'bg-sky-500/15',    text: 'text-sky-700 dark:text-sky-300',       border: 'border-sky-500/40',    label: 'Aerobic Base' },
  anaerobic_intervals:     { hex: '#06b6d4', bg: 'bg-cyan-500/15',   text: 'text-cyan-700 dark:text-cyan-300',     border: 'border-cyan-500/40',   label: 'Anaerobic Intervals' },
  mixed_modal_conditioning:{ hex: '#8b5cf6', bg: 'bg-violet-500/15', text: 'text-violet-700 dark:text-violet-300', border: 'border-violet-500/40', label: 'Mixed Modal' },
  power:                   { hex: '#eab308', bg: 'bg-yellow-500/15', text: 'text-yellow-700 dark:text-yellow-300', border: 'border-yellow-500/40', label: 'Power' },
  mobility:                { hex: '#10b981', bg: 'bg-emerald-500/15',text: 'text-emerald-700 dark:text-emerald-300',border:'border-emerald-500/40',label: 'Mobility' },
  movement_skill:          { hex: '#14b8a6', bg: 'bg-teal-500/15',   text: 'text-teal-700 dark:text-teal-300',     border: 'border-teal-500/40',   label: 'Movement Skill' },
  durability:              { hex: '#f59e0b', bg: 'bg-amber-500/15',  text: 'text-amber-700 dark:text-amber-300',   border: 'border-amber-500/40',  label: 'Durability' },
  combat_sport:            { hex: '#ec4899', bg: 'bg-pink-500/15',   text: 'text-pink-700 dark:text-pink-300',     border: 'border-pink-500/40',   label: 'Combat Sport' },
  rehab:                   { hex: '#84cc16', bg: 'bg-lime-500/15',   text: 'text-lime-700 dark:text-lime-300',     border: 'border-lime-500/40',   label: 'Rehab' },
}
```

Each entry carries a `label` — the badge component reads it, so modality display names are never re-derived from the ID at the call site.

> **Resolved 2026-07-30 (was FIX-1).** This map previously shipped `text-{c}-400 dark:text-{c}-300`, which was **inverted**: because `:root` is light (§3.1), the bare `-400` shade was what light mode rendered, on a `/15`-tinted white background — `text-red-400` (#f87171) on ≈#fce3e3 measures **2.27:1** against a WCAG AA floor of 4.5:1, at `text-[10px]`. The `dark:` half was brightening an already-passing dark mode while light mode went unaddressed. All 12 entries now use the `-700`/`-300` pairing shown above.

**The rule this encodes:** in a two-theme system, a semantic color needs a *pair* of shades pulling in opposite directions from their backgrounds — dark text on light, light text on dark. A single mid-shade cannot serve both, and no single shade in the `-400`/`-500` band clears AA on the light end (measurements in §8.8).

**Semantic grouping behind the colors:**
- Warm (red → orange → rose): strength modalities
- Cool (sky → cyan): aerobic/interval work
- Purple/violet: mixed/complex conditioning
- Green spectrum (emerald → teal → lime): recovery, skill, rehab
- Pink: combat/sport-specific
- Amber/yellow: power, durability

**Usage in a badge:**
```tsx
export function ModalityBadge({ modality, size = 'default' }) {
  const c = MODALITY_COLORS[modality]
  return (
    <span className={cn(
      'inline-flex items-center rounded-full border font-medium',
      size === 'sm' ? 'px-1.5 py-0.5 text-[10px]' : 'px-2 py-0.5 text-xs',
      c.bg, c.text, c.border
    )}>
      {c.label}
    </span>
  )
}
```

**Usage as a color bar (session card top stripe):**
```tsx
<div className="h-0.5 w-full" style={{ backgroundColor: MODALITY_COLORS[modality].hex }} />
```

### 8.2 Training Phase Colors

```typescript
// lib/phaseColors.ts — 11 entries keyed by TrainingPhase
const PHASE_COLORS = {
  base:        { hex: '#0ea5e9', bg: 'bg-sky-500/15',    text: 'text-sky-700 dark:text-sky-300',       label: 'Base'        },
  build:       { hex: '#f59e0b', bg: 'bg-amber-500/15',  text: 'text-amber-700 dark:text-amber-300',   label: 'Build'       },
  peak:        { hex: '#ef4444', bg: 'bg-red-500/15',    text: 'text-red-700 dark:text-red-300',       label: 'Peak'        },
  taper:       { hex: '#22c55e', bg: 'bg-green-500/15',  text: 'text-green-700 dark:text-green-300',   label: 'Taper'       },
  deload:      { hex: '#94a3b8', bg: 'bg-slate-500/15',  text: 'text-slate-700 dark:text-slate-300',   label: 'Deload'      },
  maintenance: { hex: '#a1a1aa', bg: 'bg-zinc-500/15',   text: 'text-zinc-700 dark:text-zinc-300',     label: 'Maintenance' },
  rehab:       { hex: '#84cc16', bg: 'bg-lime-500/15',   text: 'text-lime-700 dark:text-lime-300',     label: 'Rehab'       },
  post_op:     { hex: '#a855f7', bg: 'bg-purple-500/15', text: 'text-purple-700 dark:text-purple-300', label: 'Post-Op'     },
  active:      { hex: '#94a3b8', bg: 'bg-slate-500/15',  text: 'text-slate-700 dark:text-slate-300',   label: 'Active'      },
  transition:  { hex: '#8b5cf6', bg: 'bg-violet-500/15', text: 'text-violet-700 dark:text-violet-300', label: 'Transition'  },
  specific:    { hex: '#f97316', bg: 'bg-orange-500/15', text: 'text-orange-700 dark:text-orange-300', label: 'Specific'    },
}
```

`transition` and `specific` belong to Uphill Athlete's four-phase sequence (transition → base → specific → taper). They reuse the violet and orange hexes from `mixed_modal_conditioning` and `strength_endurance` — acceptable because phase and modality never render on the same mark.

> **Resolved 2026-07-30 (was FIX-1).** Same inverted pattern as §8.1, fixed the same way across all 11 entries.

**Intuitive mapping:** Blue = foundation, Amber = building heat, Red = peak intensity, Green = tapering down, Gray = recovery/maintenance.

`active` and `deload` intentionally share the same slate hex. `active` is a non-periodized fallback for programs with no phase structure; it should read as "no phase signal," which is exactly what neutral slate says.

### 8.3 Completion State (Emerald)

One color owns the "done" state throughout the entire application: `emerald-500`.

```typescript
// Complete: all three properties use the same hue, different opacity
const completeStyles = {
  border: 'border-emerald-500/30',
  bg:     'bg-emerald-500/10',
  text:   'text-emerald-500',
  hover:  'hover:bg-emerald-500/20',
  icon:   CheckCircle2,
}
```

Applied to: session cards, day headers, completion buttons, "all done" state of TodaySession, week-complete banners.

> **Resolved 2026-07-30 (was FIX-1).** Completion styles were previously written inline at every call site with no `dark:` variant, so `text-emerald-500` measured **2.33:1** in light mode. Now extracted to `lib/completionColors.ts`.

**The module** (`lib/completionColors.ts`):

```typescript
export const COMPLETION = {
  border:   'border-emerald-500/30',
  bg:       'bg-emerald-500/5',          // card/panel surface
  bgStrong: 'bg-emerald-500/10',         // interactive controls
  hover:    'hover:bg-emerald-500/20',
  text:     'text-emerald-700 dark:text-emerald-300',
  hex:      '#10b981',                   // charts, SVG, inline style
} as const

export const COMPLETION_SURFACE     = `${COMPLETION.border} ${COMPLETION.bg} ${COMPLETION.text}`
export const COMPLETION_INTERACTIVE = `${COMPLETION.border} ${COMPLETION.bgStrong} ${COMPLETION.text} ${COMPLETION.hover}`
```

Two fill strengths, because the original inline copies had silently diverged: cards used `/5`, interactive controls `/10`. Both are correct for their context, so the module names them rather than flattening them.

**Completion is not "good".** Do not reach for `COMPLETION` to mean positive, on-track, or passing — that is §8.8's axis, and it has its own module. Completion means the work is finished, regardless of how it went. A session completed badly is still complete.

### 8.4 Fatigue Gradient

A five-step traffic-light gradient from fresh (green) to cooked (red), used in session notes:

```typescript
const FATIGUE_STYLES = {
  1: 'border-emerald-500 bg-emerald-500/10 text-emerald-500',  // Fresh
  2: 'border-green-500   bg-green-500/10   text-green-500',    // Light
  3: 'border-amber-500   bg-amber-500/10   text-amber-500',    // Moderate
  4: 'border-orange-500  bg-orange-500/10  text-orange-500',   // Heavy
  5: 'border-red-500     bg-red-500/10     text-red-500',      // Cooked
}
```

### 8.5 Exercise Category Colors

```typescript
const CATEGORY_COLORS = {
  barbell:    'text-red-400',
  kettlebell: 'text-orange-400',
  bodyweight: 'text-emerald-400',
  aerobic:    'text-sky-400',
  carries:    'text-amber-400',
  sandbag:    'text-yellow-600',
  mobility:   'text-teal-400',
  skill:      'text-violet-400',
  rehab:      'text-lime-400',
  gym_jones:  'text-pink-400',
}
```

### 8.6 Effort Level Dots

```typescript
const EFFORT_DOT = {
  low:    'bg-emerald-400',
  medium: 'bg-yellow-400',
  high:   'bg-orange-500',
  max:    'bg-red-500',
}
```

Used as small `size-2 rounded-full` indicators on exercise cards.

### 8.7 Heart-Rate Zone Colors

The five-zone Friel/Coggan model. Unlike modality and phase colors, these encode a *measured* quantity, so the ramp must read as ordered — cool at rest, hot at max — not as a set of categories:

```typescript
const ZONE_COLORS = [
  '#94a3b8', // Z1 — slate  · Recovery   (<60% max HR)
  '#38bdf8', // Z2 — sky    · Aerobic    (60–70%)
  '#fbbf24', // Z3 — amber  · Tempo      (70–80%)
  '#f97316', // Z4 — orange · Threshold  (80–90%)
  '#ef4444', // Z5 — red    · Max        (90%+)
]
```

Boundaries live in `lib/hrZones.ts` as `DEFAULT_ZONE_BOUNDARIES = [0.60, 0.70, 0.80, 0.90]`.

**Why these differ from modality colors:** Z2 is `#38bdf8` (sky-400) where `aerobic_base` is `#0ea5e9` (sky-500), and Z5 shares red with `max_strength`. Deliberate — a zone ramp needs even perceptual spacing across five steps, which a categorical palette does not provide. The two systems never co-occur on the same mark.

`lib/hrZones.ts` also owns the non-color half of the zone model: `parseZoneTarget()` (reads "Zone 2 — HR < 135 bpm" off a prescription), `isZoneCompliant()` (≥50% of session time in the prescribed zone), and `BANISTER_ZONE_WEIGHTS = [1.0, 1.5, 2.0, 3.0, 4.5]` for TRIMP.

> **Resolved 2026-07-30 (was FIX-4).** This ramp was previously triplicated verbatim across `HRTimeline`, `HRZoneChart`, and `GPSMap` — one copy even carried the comment "Must match HRZoneChart ZONE_META colors," which is the duplication admitting itself. It now lives once in `lib/hrZones.ts`.

**Canonical shape** — `ZONES` carries color *and* naming, with `ZONE_COLORS` / `ZONE_BG` derived from it:

```typescript
export const ZONES = [
  { key: 'z1', label: 'Z1', description: 'Recovery',  color: '#94a3b8', bg: 'rgba(148,163,184,0.06)' },
  // … z2–z5
] as const

export const ZONE_COLORS: readonly string[] = ZONES.map((z) => z.color)
export const ZONE_BG:     readonly string[] = ZONES.map((z) => z.bg)
```

`bg` is the faint band fill painted behind `HRTimeline`'s plot. Zone labels and descriptions are no longer re-derived per consumer.

### 8.8 Readiness Status

`lib/readiness.ts` computes a 0–100 score from four weighted components (resting HR, HRV, accumulated fatigue, sleep) and resolves it to one of three statuses. The green/amber/red style set lives in `lib/statusColors.ts`:

```typescript
export const STATUS_STYLES: Record<StatusLevel, StatusStyle> = {
  green:  { ring: 'ring-emerald-500/30', score: 'text-emerald-700 dark:text-emerald-300', badge: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30' },
  yellow: { ring: 'ring-amber-500/30',   score: 'text-amber-700 dark:text-amber-300',     badge: 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30'         },
  red:    { ring: 'ring-red-500/30',     score: 'text-red-700 dark:text-red-300',         badge: 'bg-red-500/10 text-red-700 dark:text-red-300 border-red-500/30'                 },
}
```

> **Resolved 2026-07-30 (was FIX-1).** This triplet was duplicated **verbatim** in `ReadinessWidget`, `DevelopmentWidget` and `ProgressionReviewCard` — identical `ring`/`score`/`badge` values in all three, differing only in `label`. Found while fixing the contrast bug; extracted at the same time.

**`label` deliberately stays with the consumer.** The *scale* is shared, the vocabulary is not: the same green means "Ready" on readiness, "On Track" on development, "Ahead" on progression. Each file keeps a local `STATUS_LABEL` map and imports only the styles. Pulling labels into the module would have forced one vocabulary onto three different questions.

Two things worth copying from this component:

1. **The score renders `text-4xl font-bold tabular-nums`.** `tabular-nums` is mandatory on any number that updates in place — without it the score jitters horizontally as digits change.
2. **The status is never color-only.** A text badge sits beside the number, and `ReadinessFlag` values (`elevated_rhr_3d`, `suppressed_hrv_3d`, `insufficient_sleep`, …) surface as written reasons. This is §1.6 done properly.

> **Code diverges — doc is correct.** The `-500` family used here is *better* than the `-400` of §8.1 but still does not clear WCAG AA on a `/10` tint over white. Measured: `text-amber-500` **2.00:1**, `text-emerald-500` **2.33:1**, `text-red-500` **3.29:1** — floor is 4.5:1. Rolled into FIX-1.

**The corrected rule.** The pairing shape is always:

```
text-{color}-{700|800} dark:text-{color}-300
```

The dark half is settled — `-300` clears every dark surface. **The light half is per-entry, and there is no single shade that works.** `-600` and lighter never clear 4.5:1. `-700` clears it for the darker hues (red, sky, violet, purple, slate, zinc). The *bright* hues — orange, amber, yellow, lime, green, emerald, teal, cyan, pink, rose — still fail at `-700` on a `/15` tint and need `-800`:

| | `-700` result | Shipped |
|---|---|---|
| `red`, `sky`, `violet`, `purple`, `slate`, `zinc` | passes | `-700` |
| `orange`, `amber`, `yellow`, `lime`, `green`, `emerald`, `teal`, `cyan`, `pink`, `rose` | **2.25–4.49:1** | `-800` |

Two things make this unintuitive, and both are why it must be measured rather than reasoned about:

1. **The tint strength matters.** `emerald-700` passes on completion's `/10` tint (5.05:1) but fails on modality's `/15` tint (4.31:1) — the heavier tint is more saturated, so it sits closer to the text. The same hue can legitimately need different shades in different systems.
2. **Zen is the binding constraint, not light.** Zen's `oklch(0.97 0.012 90)` background is a warm off-white slightly darker than pure white, so every tint composites darker over it. Several entries pass in Light and fail only in Zen.

**Do not hand-pick these.** `test/semanticContrast.test.ts` checks every entry of every system against all four themes, resolving classes against Tailwind's own palette and the app's own theme tokens. Add an entry, run `npm test`, and it will tell you the shade you need — see §8.10.

This applies to every semantic system in §8 — modality, phase, completion, fatigue, zone, status. The `-400`/`-500` shades are correct *only* as the dark-mode half.

### 8.9 Cross-Platform Color Parity

The `hex` values in §8.1 and §8.2 are **not web-only**. They are mirrored by hand into:

- `ios/TrainingCompanion/ModalityStyle.swift` (iPhone)
- `ios/TrainingCompanionWatch Watch App/ModalityStyle.swift` (watchOS)

Both Swift files carry the web hex in a trailing comment on every line (`// #ef4444`) so a mismatch is visible in review.

**Rule:** changing a modality or phase hex is a three-file change. Update the web map and both Swift files in the same commit, or the platforms drift silently — nothing enforces this at build time.

### 8.10 The Contrast Guard

`test/semanticContrast.test.ts` is the only thing keeping §8 honest. Run by `npm test` and by CI on every frontend PR.

**What it checks.** Every entry of `MODALITY_COLORS`, `PHASE_COLORS`, `COMPLETION`, `STATUS_STYLES` and `STATUS_TEXT`, against all four themes:

1. **Contrast ≥ 4.5:1** — composites the `/N` tint over that theme's `--background`, picks the light or dark half of the pair depending on the theme, and measures.
2. **Both halves declared** — a bare `text-*` and a `dark:text-*`. This is the structural half of the rule: a single mid-shade cannot serve both themes, so an entry missing one half is wrong even if it happens to pass numerically today.

**Why it reads from source rather than a table.** The palette comes from `node_modules/tailwindcss/theme.css` and the backgrounds from `src/styles/globals.css`. A hardcoded hex table would drift the moment Tailwind updated a shade or a theme changed its background — and drift silently, since the test would keep passing against stale values. Two self-checks assert the parsers actually matched something, so a regex that silently matches nothing fails loudly instead of passing everything.

**Adding a colour.** Add the entry, run `npm test`. A failure prints the measured ratio, the theme, and the exact class strings:

```
modality/power in "zen": 4.25:1 (need 4.5:1)
  text: text-yellow-700 dark:text-yellow-300
  bg:   bg-yellow-500/15
```

Bump the light half one step and re-run. Do not lower the threshold, and do not exempt a theme.

**Why this exists at all.** This bug class is invisible to every other gate — `tsc`, `vite build`, and `eslint` all pass on a badge at 2.3:1, and Tailwind emits no error for a nonsense variant chain like `dark:hover:text-x-700 dark:hover:text-x-300`. It only shows in a theme most development never opens. When the guard was first written it immediately found **14 entries** that a careful manual sweep had missed.

---

## 9. Motion & Animation

### 9.1 Page Transitions (Universal)

Every page uses the same transition. This creates the sense of a single coherent application rather than separate pages.

```tsx
// Applied to the outermost element of every page component
<motion.div
  key="unique-page-key"
  initial={{ opacity: 0, y: 16 }}
  animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
  exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
  className="flex h-full flex-col"
>
```

**Rules:**
- `key` must be unique per route — without it AnimatePresence can't distinguish pages
- Exit is always faster than enter (0.15 vs 0.25s) — leaving is quicker than arriving
- `y: 16` enter, `y: -8` exit — content slightly rises as it exits (sense of upward motion)
- Wrap in `AnimatePresence mode="wait"` in the router to sequence enter/exit

**Router setup:**
```tsx
<AnimatePresence mode="wait">
  <Routes location={location} key={location.pathname}>
    ...
  </Routes>
</AnimatePresence>
```

### 9.2 Staggered List Entry

When a list appears, items enter sequentially rather than all at once. The delay is proportional to the list density.

```typescript
// Dense lists (exercises, catalog items: many items, small delay)
delay: index * 0.03,  duration: 0.2

// Medium lists (days of the week, goals: ~5-10 items)
delay: index * 0.04,  duration: 0.2

// Sparse lists (philosophy cards, goals grid: few, more visible items)
staggerChildren: 0.06,  duration: 0.25
```

**Implementation with variants (preferred for grids):**
```typescript
const containerVariants = {
  animate: { transition: { staggerChildren: 0.04 } }
}
const itemVariants = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.2 } }
}

// Usage
<motion.div variants={containerVariants} initial="initial" animate="animate">
  {items.map(item => (
    <motion.div key={item.id} variants={itemVariants}>
      ...
    </motion.div>
  ))}
</motion.div>
```

**Implementation with index delay (preferred for fixed sequences):**
```tsx
// DayColumn — days always appear left to right
<motion.div
  initial={{ opacity: 0, y: 8 }}
  animate={{ opacity: 1, y: 0, transition: { delay: dayIndex * 0.04, duration: 0.2 } }}
/>
```

### 9.3 Card Interactions

**Standard (session cards, exercise cards):**
```tsx
<motion.button
  whileHover={{ scale: 1.02 }}
  whileTap={{ scale: 0.98 }}
>
```

**Premium (goal selection cards — spring physics for elevated feel):**
```tsx
<motion.div
  whileHover={{ scale: 1.02, y: -2 }}
  transition={{ type: 'spring', stiffness: 300, damping: 20 }}
>
```

Spring physics (`type: 'spring'`) adds subtle bounce. Use only for high-stakes selections (goal cards) where you want to communicate importance. Regular cards use default easing.

### 9.4 Panel Slide-In

The dashboard right panel slides in from the side when a day is selected:

```tsx
<AnimatePresence mode="wait">
  {selectedDay && (
    <motion.div
      initial={{ width: 0 }}
      animate={{ width: 420, transition: { duration: 0.25, ease: 'easeInOut' } }}
      exit={{ width: 0, transition: { duration: 0.25, ease: 'easeInOut' } }}
      className="overflow-hidden shrink-0"
    >
      <div className="w-[420px]">
        <DayWorkoutPanel ... />
      </div>
    </motion.div>
  )}
</AnimatePresence>
```

The inner div has a fixed width; the outer div animates from 0 to that width, creating a clean slide. Without the inner fixed-width div, content would reflow during the animation.

### 9.5 Directional Step Navigation

The program builder wizard uses direction-aware transitions:

```typescript
function getStepVariants(direction: 'forward' | 'backward') {
  return {
    enter:  { x: direction === 'forward' ? 60 : -60, opacity: 0 },
    center: { x: 0, opacity: 1, transition: { duration: 0.28, ease: [0.25, 0.1, 0.25, 1] } },
    exit:   { x: direction === 'forward' ? -60 : 60, opacity: 0, transition: { duration: 0.18 } },
  }
}
```

Forward: new step slides in from right, old step exits left.
Backward: new step slides in from left, old step exits right.
Custom easing: `[0.25, 0.1, 0.25, 1]` is a cubic-bezier that feels snappier than ease-in-out.

### 9.6 Expand/Collapse (Height Animation)

```tsx
<AnimatePresence>
  {isExpanded && (
    <motion.div
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: 'auto' }}
      exit={{ opacity: 0, height: 0 }}
      transition={{ duration: 0.18 }}
      className="overflow-hidden"
    >
      {/* content */}
    </motion.div>
  )}
</AnimatePresence>
```

`overflow-hidden` is essential — without it, content is visible outside the collapsing boundary. `height: 'auto'` works in Framer Motion (it measures the natural height).

### 9.7 Set Completion Micro-interaction

The fastest animation in the system — must feel instant:

```tsx
<motion.button
  whileTap={{ scale: 1.3 }}
  animate={{ backgroundColor: done ? 'var(--color-primary)' : undefined }}
  transition={{ duration: 0.15 }}
>
  {setNumber}
</motion.button>
```

Scale 1.3 on tap gives strong tactile feedback. 0.15s color transition is fast enough to feel immediate.

### 9.8 Loading State (Skeleton)

```tsx
// Component loading
<div className="space-y-3 animate-pulse">
  <div className="h-4 rounded-md bg-muted w-2/3" />
  <div className="h-3 rounded-md bg-muted w-full" />
  <div className="h-3 rounded-md bg-muted w-1/2" />
</div>

// Inline spinner
<Loader2 className="size-4 animate-spin text-muted-foreground" />

// Custom spinner (no Lucide dependency)
<div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
```

Skeleton widths (2/3, full, 1/2) simulate text line lengths. Multiple lines at different widths look more natural than identical widths.

**Branded loader — `components/shared/DumbbellLoader.tsx`.** For full-page waits where a generic spinner feels cheap (currently the Dashboard's program load), the app draws the Lucide `Dumbbell` glyph at rest and animates a highlight tracing its outline. Construction:

- The five real Lucide paths render dim as a static base, so the icon is pixel-identical to the icon used everywhere else.
- A separate single **closed** contour path carries the traveling highlight — one continuous path is required because `pathOffset` cannot animate across a multi-path shape.

**When to reach for it:** one per view, on waits over ~400ms, where the user has nothing else to look at. Everywhere else use skeletons — a skeleton communicates *what is coming*, a loader only communicates *that something is coming*. Do not add a second branded loader; if a new one seems necessary, the wait is probably a skeleton case.

### 9.10 Reduced Motion

> **Resolved 2026-07-30 (was FIX-2).** The app previously had no reduced-motion handling at all — every animation in §9 played at full amplitude for users who had asked their OS to stop them. `MotionConfig` now wraps the tree in `src/App.tsx`, and `DumbbellLoader` gates its loop explicitly.

**One provider at the app root covers the Framer Motion surface** (`src/App.tsx`):

```tsx
import { MotionConfig } from 'framer-motion'

<MotionConfig reducedMotion="user">
  {/* app */}
</MotionConfig>
```

`reducedMotion="user"` reads `prefers-reduced-motion` and disables *transform and layout* animations — `x`, `y`, `scale`, `rotate`, `height` — while letting `opacity` and `backgroundColor` through. That is the correct split for this design system: §9.1 page transitions degrade to clean cross-fades, §9.7's set-completion still flashes its color confirmation, and §9.6's expand/collapse snaps instead of sliding. Orientation and feedback survive; only the movement stops.

**What the provider does not cover** — handle these individually:

| Not covered | Why | Handling |
|---|---|---|
| `animate-pulse` skeletons | Tailwind CSS keyframes, not Framer | acceptable to leave — low-amplitude opacity only |
| `animate-spin` spinners | Tailwind CSS keyframes | acceptable — conveys liveness, no translation |
| `DumbbellLoader` | `pathOffset` is an SVG *attribute* animation, not a transform | ✅ done — gated on `useReducedMotion()`, falls back to the static glyph at `opacity 0.6` |
| Recharts entry animations | library-internal | still open — set `isAnimationActive={false}` when reduced |

The `DumbbellLoader` case is the general lesson: **`reducedMotion="user"` only suppresses transform and layout values.** Anything animating an SVG attribute, a gradient stop, or a CSS keyframe needs its own `useReducedMotion()` gate.

**Rule for new motion:** if an animation moves an element more than a few pixels, it must have a reduced-motion answer. "It's subtle" is not an exemption — vestibular triggers are not proportional to how subtle the author thinks the motion is.

### 9.9 Timing Reference

| Use case | Duration | Easing |
|---|---|---|
| Page exit | 150ms | ease |
| Set button color | 150ms | ease |
| Collapse/expand | 180ms | ease |
| Page enter | 250ms | ease |
| Panel slide | 250ms | easeInOut |
| Modal content | 250ms, 100ms delay | ease |
| Step wizard | 280ms enter, 180ms exit | cubic-bezier(0.25,0.1,0.25,1) |
| Pie chart | 500–800ms | Recharts default |
| Spring (goal cards) | physics | stiffness: 300, damping: 20 |

---

## 10. Interaction Patterns

### 10.1 Hover Conventions

**Clickable cards:**
```tsx
className="... hover:border-primary/50 hover:shadow-sm transition-shadow"
```

**Ghost/nav items:**
```tsx
className="... hover:bg-accent hover:text-accent-foreground transition-colors"
```

**Muted text that becomes interactive:**
```tsx
className="text-muted-foreground hover:text-foreground transition-colors"
```

**Rule:** Hover states use `transition-colors` (not `transition-all`) for performance. Only use `transition-all` when multiple properties (border + shadow) need to change simultaneously.

### 10.2 Drag and Drop

Built with `@dnd-kit/core`. Pattern:

```tsx
// Context wraps the droppable/draggable area
<DndContext onDragStart={handleDragStart} onDragEnd={handleDragEnd} onDragCancel={handleCancel}>

  {/* Droppable container */}
  <div ref={setNodeRef} className={cn(
    'transition-colors',
    isOver && 'border-primary/60 bg-primary/5 ring-1 ring-primary/20'
  )}>

    {/* Draggable item */}
    <div
      ref={setNodeRef}
      style={transform ? { transform: CSS.Transform.toString(transform) } : undefined}
      className={cn(isDragging && 'opacity-30')}
    >
      {/* Drag handle (hidden until hover) */}
      <div
        {...attributes} {...listeners}
        className="opacity-0 group-hover/card:opacity-50 hover:!opacity-100 transition-opacity cursor-grab"
      >
        <GripVertical className="size-3.5" />
      </div>
    </div>
  </div>

  {/* Visual ghost during drag */}
  <DragOverlay dropAnimation={null}>
    {activeItem && (
      <div className="rotate-1 shadow-xl ring-2 ring-primary/40 opacity-95 rounded-lg">
        <SessionCard ... />
      </div>
    )}
  </DragOverlay>

</DndContext>
```

**Design details:**
- Original item becomes 30% opacity while dragging (ghost effect)
- Drag overlay rotates 1 degree and gets a ring highlight
- Drop zones get a primary-colored ring when hovered
- `dropAnimation={null}` — instant snap on drop (no animation back)
- Drag handle shows on hover (`group-hover`) with `cursor-grab`

### 10.3 Toggle / Completion Buttons

State-switching buttons use visual inversion to show current state clearly:

```tsx
// Incomplete → primary action
// Complete → semantic success color
<button className={cn(
  'w-full flex items-center justify-center gap-2 h-10 rounded-lg text-sm font-medium transition-colors',
  isComplete
    ? 'bg-emerald-500/10 text-emerald-500 border border-emerald-500/30 hover:bg-emerald-500/20'
    : 'bg-primary text-primary-foreground hover:bg-primary/90'
)}>
  {isComplete
    ? <><CheckCircle2 className="size-4" /> Completed — tap to undo</>
    : <><Circle className="size-4" /> Mark Session Complete</>
  }
</button>
```

**The "undo" label** is important — it tells the user the action is reversible. Always include it on toggleable completion buttons.

### 10.4 Search with Live Filtering

No debounce for small lists (< 50 items). Immediate filter on every keystroke:

```tsx
const filtered = useMemo(() => {
  const q = searchQuery.toLowerCase()
  return items
    .filter(item => !q || item.name.toLowerCase().includes(q))
    .sort((a, b) => a.name.localeCompare(b.name))
}, [items, searchQuery])
```

`useMemo` prevents re-running the filter on every render. `autoFocus` on the input when the panel opens.

For larger lists (> 50), debounce with 250ms.

---

## 11. State Variations

### 11.1 The Five States Every Component Needs

1. **Default** — resting state
2. **Hover** — `hover:` prefix, usually border/shadow change
3. **Active/Selected** — distinct from hover; persists after interaction
4. **Disabled** — `disabled:opacity-50 disabled:pointer-events-none`
5. **Complete/Success** — emerald palette (for completion-tracking components)

### 11.2 Empty State Pattern

```tsx
function EmptyState({ title, description, action, icon, className }) {
  return (
    <div className={cn(
      'flex flex-col items-center justify-center rounded-lg border border-dashed bg-card/50 p-12 text-center',
      className
    )}>
      {icon && (
        <div className="mb-4 text-muted-foreground/40">{icon}</div>
      )}
      <h3 className="text-base font-semibold text-foreground">{title}</h3>
      {description && (
        <p className="mt-1 text-sm text-muted-foreground max-w-sm">{description}</p>
      )}
      {action && (
        <Button onClick={action.onClick} className="mt-4">{action.label}</Button>
      )}
    </div>
  )
}
```

Always provide a `action` CTA that resolves the empty state (e.g., "Build a Program"). The dashed border (`border-dashed`) visually distinguishes empty slots from loaded content.

> **Code diverges — doc is correct.** `components/shared/EmptyState.tsx` is imported by **6** files, while **25** hand-rolled `border-dashed` empty states exist across the app. The *pattern* was adopted; the *component* was not. The cost is not visual — most copies look right — it is that the `action` CTA is optional in a hand-rolled block and consistently gets dropped, so a good share of the app's zero-data states are dead ends with no path forward. That is a direct §1.4 violation. Tracked as FIX-5.

**Rule:** a zero-data view uses `<EmptyState>`. If it needs something the component cannot express, extend the component — do not fork it inline. The one legitimate exception is a *slot-sized* empty cell (an unscheduled day in the week grid), which is too small for a title/description/CTA and correctly uses a bare dashed cell.

### 11.3 Loading Card Pattern

```tsx
function LoadingCard() {
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3 animate-pulse">
      <div className="h-4 rounded-md bg-muted w-2/3" />
      <div className="h-3 rounded-md bg-muted w-full" />
      <div className="h-3 rounded-md bg-muted w-1/2" />
    </div>
  )
}
```

Match the skeleton's visual weight to the content it represents. A card with a title and two lines of metadata gets a taller block + two narrower blocks.

### 11.4 Error State

```tsx
<Alert variant="destructive" className="mt-4">
  <AlertCircle className="size-4" />
  <AlertTitle>Generation failed</AlertTitle>
  <AlertDescription>
    Could not connect to the API. Check that the server is running.
  </AlertDescription>
</Alert>
```

### 11.5 Selected vs. Complete

These are intentionally distinct:

| State | Color | Use |
|---|---|---|
| Selected/active | `primary` (amber) | Currently viewing, currently selected |
| Complete/done | `emerald` | Work finished, not necessarily viewing |
| Today | `primary` bg | Calendar: today's date |
| Today + complete | `emerald` | Calendar: today's session done |

---

## 12. Data Visualization

### 12.1 Chart Library: Recharts

All charts use Recharts with minimal configuration. Custom components handle wrapper sizing and tooltips. Geospatial views are the exception — see §12.9.

**Responsive container pattern:**
```tsx
<ResponsiveContainer width="100%" height={180}>
  <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
    ...
  </BarChart>
</ResponsiveContainer>
```

### 12.1.1 Chart Inventory

Visualization is now the largest single surface in the app — **18 files** render Recharts, plus two map components. This section previously documented four of them. Full inventory:

| Component | Form | Color source |
|---|---|---|
| `dashboard/ModalityDonut` | donut (§12.2) | modality hex |
| `dashboard/VolumeBar` | stacked bar (§12.3) | modality hex |
| `dashboard/DevelopmentWidget` | bar | modality hex |
| `program/ProgramOverview` | phase timeline (§12.5) | phase hex |
| `progression/ExerciseTrendChart` | line + trend | primary token |
| `bio/PMCChart` | dual-axis line + bar (§12.7) | fixed 3-series |
| `bio/SleepStageChart` | stacked bar (§12.6) | sleep-stage set |
| `bio/HRZoneChart` | horizontal bar | zone ramp (§8.7) |
| `bio/HRTrendChart`, `RHRTrendChart`, `HRVTrendChart` | sparkline-ish line (§12.4) | primary token |
| `bio/WeeklyLoadChart`, `WeeklyZoneSummary` | bar / stacked bar | zone ramp |
| `bio/ReadinessWidget` | radial + score (§8.8) | readiness set |
| `workout/HRTimeline` | gradient-stroke line (§12.8) | zone ramp |
| `workout/ElevationChart` | gradient area (§12.8) | teal `#14b8a6` |
| `workout/GPSMap` | Leaflet polyline (§12.9) | zone ramp |
| `workout/Swiss3DMap` | CesiumJS terrain (§12.9) | — |
| `devlab/PhilosophyExplorerPanel` | bar | modality hex |
| `pages/WorkoutAnalytics` | multiple, inline | mixed |

**Rule this inventory implies:** a chart's colors come from a *named system* (§8), not from the author's judgement at the call site. `WorkoutAnalytics` defines series colors inline and is the one place that breaks this — noted in the fix plan (FIX-6) as low priority, since the values it picks are correct today.

### 12.1.2 Chart Theme-Awareness

Charts split their colors into two categories, and the split is the thing to get right:

| Category | Source | Why |
|---|---|---|
| **Semantic marks** — bars, lines, cells that *mean* something | hardcoded hex from §8 | The color is the information. Amber must stay amber in Zen. |
| **Chart chrome** — axes, ticks, grid, cursor, tooltip surface | `var(--color-*)` tokens | Chrome must recede against whatever background the theme sets. |

Currently ~30 hardcoded hex values vs ~32 `var(--color-*)` references across the chart files — roughly the right ratio, but not cleanly split. Some axis and reference-line colors are still hardcoded and will read wrong in Military and Zen (FIX-6).

**Tooltip surface — always tokens, no exceptions:**
```tsx
<Tooltip
  cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }}
  contentStyle={{
    background: 'var(--color-card)',
    border: '1px solid var(--color-border)',
    borderRadius: '0.5rem',
    fontSize: '11px',
  }}
/>
```

Several components go further and render a fully custom tooltip node — `rounded border border-border bg-card px-2 py-1 text-[10px]` — with each series' label tinted to its own series color via inline `style={{ color: p.color }}`. Prefer this when a tooltip shows more than two series; the color tie-back is faster to read than a label list.

### 12.2 Donut Chart (Modality Distribution)

```tsx
<PieChart>
  <Pie
    data={data}
    cx="50%"
    cy="50%"
    innerRadius={54}
    outerRadius={80}
    paddingAngle={2}
    dataKey="value"
    animationBegin={200}
    animationDuration={800}
  >
    {data.map((entry) => (
      <Cell key={entry.modality} fill={MODALITY_COLORS[entry.modality].hex} />
    ))}
  </Pie>
</PieChart>
```

Center label (absolute positioned over the chart):
```tsx
<div className="absolute inset-0 flex flex-col items-center justify-center">
  <span className="text-2xl font-bold">{dominantPct}%</span>
  <span className="text-xs text-muted-foreground">{dominantLabel}</span>
</div>
```

### 12.3 Bar Chart (Volume Over Time)

```tsx
<BarChart data={weeklyVolume} barSize={8} barGap={2}>
  <XAxis
    dataKey="week"
    tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
    axisLine={false}
    tickLine={false}
  />
  <YAxis
    tick={{ fontSize: 10 }}
    width={28}
    axisLine={false}
    tickLine={false}
  />
  <Tooltip
    cursor={{ fill: 'var(--color-muted-foreground)', fillOpacity: 0.08 }}
    contentStyle={{
      background: 'var(--color-card)',
      border: '1px solid var(--color-border)',
      borderRadius: '0.5rem',
      fontSize: '11px',
    }}
  />
  <Bar dataKey="Strength"     fill="#ef4444" radius={[3, 3, 0, 0]} />
  <Bar dataKey="Conditioning" fill="#0ea5e9" radius={[3, 3, 0, 0]} />
  <Bar dataKey="Durability"   fill="#f59e0b" radius={[3, 3, 0, 0]} />
  <Bar dataKey="Mobility"     fill="#10b981" radius={[3, 3, 0, 0]} />
</BarChart>
```

**Key styling decisions:**
- `axisLine={false} tickLine={false}` — clean axes without ticks
- `radius={[3, 3, 0, 0]}` — rounded tops only (flat bottom touches the axis)
- Tooltip uses CSS tokens for theme-awareness
- Legend uses modality colors

### 12.4 Line Chart (Sparklines)

```tsx
<LineChart data={sparkData}>
  <Line
    type="monotone"
    dataKey="value"
    stroke={color}
    strokeWidth={1.5}
    dot={false}
    connectNulls
  />
</LineChart>
```

Sparklines have no axes, no tooltip, no legend — just the line. `connectNulls` handles gaps in data gracefully.

### 12.5 Phase Timeline (Custom, no Recharts)

Proportional segments using flex layout with percentage widths:

```tsx
<div className="flex h-2 rounded-full overflow-hidden">
  {phases.map(phase => (
    <div
      key={phase.id}
      className="transition-all"
      style={{
        width: `${phase.weeks / totalWeeks * 100}%`,
        backgroundColor: PHASE_COLORS[phase.phase].hex,
      }}
    />
  ))}
</div>
```

Current week marker:
```tsx
<div
  className="absolute top-0 bottom-0 w-0.5 bg-foreground"
  style={{ left: `${currentPct}%` }}
/>
```

### 12.6 Stacked Bar (Composition Over Time)

For "what was this made of" across a time axis — sleep stages per night, zone minutes per week:

```tsx
<Bar dataKey="Deep"  stackId="sleep" fill="#1d4ed8" radius={[0, 0, 0, 0]} />
<Bar dataKey="REM"   stackId="sleep" fill="#7c3aed" radius={[0, 0, 0, 0]} />
<Bar dataKey="Light" stackId="sleep" fill="#38bdf8" radius={[0, 0, 0, 0]} />
<Bar dataKey="Awake" stackId="sleep" fill="#6b7280" radius={[4, 4, 0, 0]} />
```

**Two rules that make stacks read correctly:**

1. **Only the topmost segment gets a radius.** Every lower segment is `[0,0,0,0]`; the last one declared is `[4,4,0,0]`. Rounding an interior segment carves a visible notch into the stack.
2. **Stack order is semantic, not arbitrary.** Deep → REM → Light → Awake runs deepest-at-the-bottom, so the stack reads as a depth profile. Reordering for visual balance destroys the meaning.

The sleep palette is its own ordered ramp (indigo → violet → sky → gray) — depth encoded as saturation, with wakefulness the only desaturated band so gaps in sleep are the thing the eye catches first.

### 12.7 Dual-Axis Composed Chart (PMC)

The Performance Management Chart plots three quantities with different units on one canvas — the densest chart in the app:

```tsx
<Cell fill={entry.tsb >= 0 ? '#10b981' : '#ef4444'} fillOpacity={0.7} />  {/* Form: bars, signed */}
<Line stroke="#f97316" ... />   {/* Fatigue (ATL) */}
<Line stroke="#3b82f6" ... />   {/* Fitness (CTL) */}
```

**Patterns worth reusing:**

- **Signed values get per-`Cell` conditional fill**, not two series. Form above zero is emerald, below is red — one dataset, colored by sign. This is the general answer for any diverging metric.
- **`fillOpacity={0.7}` on the bars** pushes them behind the lines without a z-index fight. Bars are context; lines are the trend.
- **Mixed forms encode mixed roles.** Bars = discrete daily state, lines = smoothed accumulation. Using three lines would make them look like three of the same thing.

**When to allow a second Y axis:** only when both series are genuinely watched together *and* their units cannot be normalized. Two axes double the reader's work — a second chart is usually the better answer.

### 12.8 Gradient Encoding (Continuous Data)

Two workout charts encode a continuous variable into a gradient rather than a discrete color.

**Gradient area — `ElevationChart`.** A single teal hue fading to near-transparent, giving the profile visual mass without competing with the line:

```tsx
<linearGradient id="elevGradient" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0%"   stopColor="#14b8a6" stopOpacity={0.4} />
  <stop offset="100%" stopColor="#14b8a6" stopOpacity={0.05} />
</linearGradient>
```

**Gradient stroke — `HRTimeline`.** The more interesting technique: the *line itself* is painted with a horizontal gradient whose stops are computed per-sample from HR zone, so a single continuous stroke shows zone drift over the session:

```tsx
stops.push({ offset: `${(offset * 100).toFixed(1)}%`, color: ZONE_COLORS[zone] })
```

Paired with faint zone bands behind the line (`rgba(148,163,184,0.06)` and siblings) so absolute zone position stays readable while the stroke shows the transitions.

**Rule:** reach for a gradient when the underlying variable is genuinely continuous. For categorical data a gradient invents an ordering that isn't there.

### 12.9 Maps (Leaflet + CesiumJS)

Two non-Recharts geospatial views:

**`GPSMap`** — `react-leaflet`, route drawn as `Polyline` segments colored by HR zone (§8.7), start/end marked with `#22c55e` / `#ef4444` dot icons. Container: `rounded-lg overflow-hidden border border-border isolate`.

`isolate` is required. Leaflet sets high z-indexes on its panes; without a new stacking context the map paints over sheets and dialogs.

> **Resolved 2026-07-30 (was FIX-3).** The tile layer was pinned to CartoDB's `dark_all` basemap, which dropped a ~360px dark slab into Light and Zen — the most visible theme break in the app. The basemap is now selected from the active theme:
>
> ```tsx
> const DARK_THEMES = new Set(['dark', 'military'])
> const { resolvedTheme } = useTheme()
> const tileUrl = basemapUrl(DARK_THEMES.has(resolvedTheme ?? 'dark'))
> …
> <TileLayer key={tileUrl} url={tileUrl} />   // key forces a clean tile swap
> ```

**Theme lightness grouping.** Military is a dark surface and groups with `dark`; Zen is warm off-white and groups with `light`. Any component branching on lightness rather than theme identity should use this same grouping — if a third such component appears, lift `DARK_THEMES` into a `useIsDarkTheme()` hook.

**`Swiss3DMap`** — CesiumJS over swisstopo terrain, loaded from CDN at runtime (`loadCesium()` injects the script, resolves once `window.Cesium` exists) rather than bundled. Keeps a very large 3D dependency out of the main bundle for a view most sessions never open.

**Rule for heavy visualization deps:** load at runtime behind an interaction, show the standard loading state while it resolves, and fail to a real error state — `Swiss3DMap` rejects with `Failed to load CesiumJS` rather than hanging.

### 12.10 Choosing a Chart Form

| The question | Form | Example |
|---|---|---|
| What is this made of, right now? | donut (§12.2) | modality distribution |
| What was this made of, over time? | stacked bar (§12.6) | sleep stages, weekly zones |
| How much, per period? | bar (§12.3) | weekly volume |
| Which direction is this trending? | line / sparkline (§12.4) | HRV, RHR, e1RM |
| Two accumulations plus a signed balance? | dual-axis composed (§12.7) | PMC |
| How did a continuous value vary along a path? | gradient stroke/area (§12.8) | HR timeline, elevation |
| Where did this happen? | map (§12.9) | GPS route |
| How are fixed spans laid out in sequence? | flex timeline, no library (§12.5) | phase bar |

**Before adding a new chart:** find its row here first. If nothing fits, the new form needs a subsection in this section, not a one-off in a page component.

---

## 13. Page & Layout Patterns

### 13.1 App Shell

```tsx
<div className="flex h-screen overflow-hidden bg-background">

  {/* Desktop sidebar */}
  <aside className="hidden md:flex flex-col w-56 border-r bg-card/50 transition-all duration-200">
    <Sidebar />
  </aside>

  {/* Mobile overlay */}
  <AnimatePresence>
    {sidebarOpen && (
      <div className="fixed inset-0 z-40 md:hidden">
        <div className="absolute inset-0 bg-background/80 backdrop-blur-sm" onClick={close} />
        <aside className="relative z-50 w-56 h-full bg-card border-r">
          <Sidebar />
        </aside>
      </div>
    )}
  </AnimatePresence>

  {/* Main area */}
  <div className="flex flex-1 flex-col overflow-hidden">
    <TopBar />
    <main className="flex-1 overflow-hidden flex flex-col">
      <AnimatePresence mode="wait">
        <Outlet />
      </AnimatePresence>
    </main>
  </div>

</div>
```

### 13.2 Sidebar Navigation

```tsx
<nav className="p-2 space-y-0.5">
  {navItems.map(item => (
    <NavLink
      to={item.path}
      className={({ isActive }) => cn(
        'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
        isActive
          ? 'bg-primary/10 text-primary'
          : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <item.icon className="size-4 shrink-0" />
      {item.label}
    </NavLink>
  ))}
</nav>
```

Active state: primary-tinted background + primary text. Inactive: muted text that brightens on hover.

### 13.3 Dashboard with Side Panel

```tsx
<div className="flex h-full overflow-hidden">

  {/* Main scrollable content */}
  <div className="flex-1 min-w-0 overflow-y-auto p-6 space-y-6">
    ...content...
  </div>

  {/* Right panel — slides in */}
  <AnimatePresence mode="wait">
    {selectedDay && (
      <motion.div
        initial={{ width: 0 }}
        animate={{ width: 420, transition: { duration: 0.25, ease: 'easeInOut' } }}
        exit={{ width: 0, transition: { duration: 0.25, ease: 'easeInOut' } }}
        className="shrink-0 overflow-hidden border-l"
      >
        <div className="w-[420px] h-full overflow-y-auto">
          <DayWorkoutPanel day={selectedDay} onClose={() => setSelectedDay(null)} />
        </div>
      </motion.div>
    )}
  </AnimatePresence>

</div>
```

### 13.4 7-Column Week Grid

```tsx
<div className="overflow-x-auto">
  <div className="grid grid-cols-7 gap-1.5 min-w-[700px]">
    {DAYS.map(day => (
      <DayColumn key={day} day={day} ... />
    ))}
  </div>
</div>
```

`min-w-[700px]` + `overflow-x-auto` on the container allows horizontal scroll on mobile without breaking the 7-column layout.

### 13.5 Step Wizard Layout

```tsx
<div className="flex h-full flex-col overflow-hidden">

  {/* Progress indicator */}
  <StepIndicator currentStep={step} totalSteps={4} />

  {/* Step content — animated */}
  <div className="flex-1 overflow-hidden relative">
    <AnimatePresence mode="wait" custom={direction}>
      <motion.div
        key={step}
        custom={direction}
        variants={getStepVariants(direction)}
        initial="enter"
        animate="center"
        exit="exit"
        className="absolute inset-0 overflow-y-auto p-6"
      >
        {renderStep(step)}
      </motion.div>
    </AnimatePresence>
  </div>

  {/* Nav buttons */}
  <div className="border-t p-4 flex items-center justify-between shrink-0">
    <Button variant="ghost" onClick={goBack}>Back</Button>
    <Button onClick={goForward}>
      {isLastStep ? 'Generate' : 'Next'}
    </Button>
  </div>

</div>
```

`absolute inset-0` on the step content div allows `AnimatePresence mode="wait"` to stack-and-replace without layout shifts.

### 13.6 Explorer Landing Page Pattern

**Use case:** Browsing/selecting from a collection (philosophies, modalities, exercises, equipment profiles, injury flags, benchmarks).

**Structure:**
```tsx
<div className="h-full overflow-y-auto">
  <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
    
    {/* Header section */}
    <div className="space-y-3">
      <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
        Category label
      </p>
      <h2 className="text-2xl font-semibold leading-snug">
        {count} items.
      </h2>
      <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
        Brief description of what this collection represents and how it's used in the system.
      </p>
    </div>

    {/* Card grid */}
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        {items.map(item => (
          <button
            key={item.id}
            onClick={() => onSelect(item)}
            className="flex items-start gap-2.5 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 text-left
                       transition-all hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20 group cursor-pointer"
            style={{ borderLeftColor: item.color, borderLeftWidth: 2 }}
          >
            <div className="min-w-0 flex-1">
              <p className="text-xs font-medium leading-snug truncate group-hover:text-primary transition-colors">
                {item.name}
              </p>
              <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                {item.metadata}
              </p>
            </div>
          </button>
        ))}
      </div>
    </div>

    {/* Footer hint */}
    <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
      Select an item to see details
    </p>
    
  </div>
</div>
```

**Key patterns:**
- **Centered column:** `max-w-2xl mx-auto` keeps content readable, not stretched
- **Generous top padding:** `py-12` gives breathing room
- **Hierarchical spacing:** Small gaps within sections (`space-y-3`), larger between sections (`space-y-10`)
- **Color-coded borders:** `borderLeftColor: item.color, borderLeftWidth: 2` — semantic color shows category/type at a glance
- **Hover feedback:** `hover:-translate-y-px hover:shadow-md` — lift on hover confirms interactivity
- **Metadata line:** `text-[10px] text-muted-foreground/60` — shows count or secondary info without competing with title

**When to use:**
- Browsing mode before selection (Explore tab for philosophies/modalities/exercises)
- Profile tab sub-sections (equipment picker, injury flags, benchmarks)
- Any "choose from collection" UI

**When NOT to use:**
- Active training view (calendar, session detail) — use dense layouts
- Forms with many fields — use vertical stack with labels
- Dashboards with live data — use cards with metrics, not landing page pattern

---

## 14. Responsive Design

### 14.1 Breakpoint Usage

| Breakpoint | px | Primary use |
|---|---|---|
| (default) | — | Mobile layout: single column, full width |
| `sm:` | 640px | 2-column grids, constrained sheets (`sm:max-w-md`) |
| `md:` | 768px | Sidebar visible, 2–3 column layouts |
| `lg:` | 1024px | Full multi-column, full nav |

### 14.2 Mobile Adaptations

**Typography:** Day names use abbreviated form on mobile:
```tsx
<span className="hidden sm:block">{day}</span>      {/* "Monday" */}
<span className="sm:hidden">{DAY_SHORT[day]}</span>  {/* "Mon" */}
```

**Sheet width:** Always full-width on mobile, constrained at sm:
```tsx
className="w-full sm:max-w-md"
```

**Grid fallback:** 7-column week grid gets `overflow-x-auto` + `min-w-[700px]` to scroll rather than collapse.

**Sidebar:** Hidden on mobile, replaced by topbar hamburger + overlay.

### 14.3 Mobile-First Rules

1. Style the mobile view first, enhance for larger screens with `sm:`, `md:`, `lg:`
2. Use `hidden md:flex` (not `md:flex hidden`) for desktop-only elements
3. Use `md:hidden` for mobile-only elements
4. `flex-col` default, `md:flex-row` when layout should change at desktop
5. Full-width inputs/buttons on mobile, auto-width at `sm:`

---

## 15. Icon System

All icons come from `lucide-react`. Sizing uses Tailwind's `size-*` shorthand (sets both width and height).

### 15.1 Size Convention

| Size | Use |
|---|---|
| `size-3` | Inline with `text-[10px]` text |
| `size-3.5` | Badge icons, tight metadata |
| `size-4` | Standard button icons, form icons |
| `size-5` | Medium emphasis icons |
| `size-6` | Feature icons within cards |
| `size-8` | Empty state decorative icons |
| `size-10` | Hero empty state icons |

### 15.2 Color Convention

Icons inherit `currentColor` by default, so they follow their parent's `text-*` class:

```tsx
{/* Icon inherits text-primary from parent */}
<span className="text-primary">
  <CheckCircle2 className="size-4" />
</span>

{/* Icon has its own color */}
<Dumbbell className="size-8 text-muted-foreground/40" />
```

### 15.3 Semantic Icon Vocabulary

| Icon | Meaning |
|---|---|
| `CheckCircle2` | Complete state |
| `Circle` | Incomplete / to-do |
| `Check` | Compact complete indicator (in day headers) |
| `RefreshCw` | Replace / regenerate |
| `Loader2` (+ `animate-spin`) | Loading |
| `ChevronLeft/Right` | Navigation |
| `ChevronDown/Up` | Expand/collapse |
| `X` | Close panel/dialog |
| `Wand2` | AI generation / magic action |
| `Dumbbell` | Rest day / workout placeholder |
| `Clock` | Duration |
| `GripVertical` | Drag handle |
| `ArrowRight` | Call to action / proceed |
| `Plus` | Add |
| `Trash2` | Delete |
| `Settings` | Configuration |

---

## 16. Implementation Checklist

Use this to set up the design system in a new project.

### Foundation

- [ ] Install: `tailwindcss`, `@radix-ui/*`, `class-variance-authority`, `clsx`, `tailwind-merge`, `framer-motion`, `lucide-react`
- [ ] Create `lib/utils.ts` with `cn()` utility
- [ ] Set up CSS custom properties for all color tokens (dark theme first)
- [ ] Add `.light`, `.military`, `.zen` theme classes for optional variants
- [ ] Set `--radius: 0.5rem` as base radius token

### Colors

- [ ] Create `lib/categoryColors.ts` (or equivalent) mapping your domain categories to color token sets (`hex`, `bg`, `text`, `border`)
- [ ] Create `lib/statusColors.ts` for any multi-value status fields (phases, states, severity)
- [ ] Reserve `emerald` for completion/success states only — keep it consistent
- [ ] Use amber as primary — it works in both light and dark themes
- [ ] Establish the `/15` bg, `/30` border, full-opacity text pattern for semantic badges

### Components

- [ ] Set up shadcn/ui base components (button, card, badge, tabs, sheet, dialog, input, select, slider, separator, scroll-area, skeleton, tooltip, popover)
- [ ] Build shared: `EmptyState`, `LoadingCard`, semantic badge components
- [ ] Ensure every component forwards `className` as a final override

### Motion

- [ ] Wrap the app in `<MotionConfig reducedMotion="user">` — **do this before writing any animation**, not after (§9.10)
- [ ] Set up `AnimatePresence mode="wait"` in the router
- [ ] Apply the standard page transition to every page component
- [ ] Add staggered entry to any list/grid with > 3 items
- [ ] Use `whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}` on interactive cards
- [ ] Use the expand/collapse pattern for any collapsible section
- [ ] Gate any continuous/looping animation behind `useReducedMotion()`

### Accessibility

- [ ] `aria-label` on every icon-only button (§17.7 headers are the usual offenders)
- [ ] Verify every semantic color pair clears 4.5:1 in **all** themes, not just the default one
- [ ] Confirm no meaning is carried by color alone — text or icon accompanies it
- [ ] Test one full flow with reduced motion enabled at the OS level
- [ ] Test one full flow by keyboard only

### Data Visualization

- [ ] Semantic marks read hex from a named system (§8); chrome reads `var(--color-*)` tokens
- [ ] Tooltip surface uses tokens so it inverts with the theme
- [ ] Check every chart in the non-default themes before shipping it

### Patterns

- [ ] Empty state for every zero-data view with a CTA that resolves it
- [ ] Loading skeleton that matches the shape of the loaded content
- [ ] Toggle buttons that show current state + "undo" affordance
- [ ] Search inputs with `autoFocus` when opened in a modal/sheet
- [ ] Truncate all text that may overflow (`truncate` + `min-w-0` on flex parents)

### Layout

- [ ] `h-screen overflow-hidden` on app root
- [ ] Sidebar: `w-56` desktop, overlay on mobile
- [ ] Page content: `flex-1 overflow-y-auto p-6`
- [ ] Sheets: `flex flex-col p-0` with manual padding on children sections
- [ ] Use `shrink-0` on headers/footers within flex columns

---

## Appendix: Quick Reference

### The Most Common Patterns

**Semantic badge:**
```tsx
<span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium bg-sky-500/15 text-sky-400 border-sky-500/40">
  Aerobic Base
</span>
```

**Interactive card:**
```tsx
<motion.button
  whileHover={{ scale: 1.02 }}
  whileTap={{ scale: 0.98 }}
  className="w-full rounded-lg border bg-card p-3 text-left transition-shadow hover:shadow-sm hover:border-primary/50"
>
```

**Complete state:**
```tsx
className={isComplete
  ? 'border-emerald-500/30 bg-emerald-500/5 text-emerald-500'
  : 'border-border bg-card text-foreground'
}
```

**Page wrapper:**
```tsx
<motion.div
  key="page-name"
  initial={{ opacity: 0, y: 16 }}
  animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
  exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
  className="flex h-full flex-col overflow-hidden"
>
```

**Staggered list:**
```tsx
{items.map((item, i) => (
  <motion.div
    key={item.id}
    initial={{ opacity: 0, y: 8 }}
    animate={{ opacity: 1, y: 0, transition: { delay: i * 0.04, duration: 0.2 } }}
  >
    ...
  </motion.div>
))}
```

**Empty state:**
```tsx
<div className="flex flex-col items-center justify-center rounded-lg border border-dashed bg-card/50 p-12 text-center">
  <Icon className="size-8 text-muted-foreground/40 mb-2" />
  <p className="text-sm font-medium text-muted-foreground">Nothing here</p>
  <Button className="mt-4" onClick={action}>Do something</Button>
</div>
```

---

## 17. Tab Header Pattern

The "tab header" is the entire top row of a page — icon, page name, subtitle, sub-tabs, step indicators, and action buttons. Every primary tab must implement this pattern consistently so users develop reliable spatial expectations: identity is always top-left, navigation is always to its right, actions are always far right.

**The canonical model is the Dev Lab header.** All new pages and all refactored pages should match this specification.

### 17.1 Purpose and Scope

This pattern applies to every **primary tab** (top-level page reachable from the sidebar). It does not apply to:
- Detail views that navigate back to a parent (Session Detail, Workout Detail) — these use the back-nav pattern (§13)
- The Dashboard — see §17.9 for the Program View Header exception

### 17.2 Container & Spacing

```tsx
<div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
  {/* content */}
</div>
```

| Property | Value | Reason |
|---|---|---|
| `flex items-center` | All children vertically centered | Consistent alignment across icon sizes |
| `gap-2` | 8px between icon and title | Tight identity pairing |
| `border-b` | Separator from content | Always present on primary headers |
| `px-6 py-4` | Standard header padding | Matches page content horizontal padding |
| `shrink-0` | Prevents flex compression | Required in `flex-col` page layouts |

**Always one horizontal row.** Do not stack the header into two rows for primary tabs — if content won't fit, it means there's too much content, not that the layout needs a second row.

### 17.3 Identity Block (Icon + Title)

```tsx
<Icon className="size-5 text-primary" />
<h1 className="text-lg font-semibold">{PageName}</h1>
```

- **Icon:** `size-5 text-primary` — always amber, always Lucide React. Every primary tab gets an icon; no exceptions.
- **Title:** `text-lg font-semibold` — not `text-xl` or `text-2xl`. The larger scales are for content titles (program names, workout names), not page chrome.
- **Title is the canonical page name** — not a dynamic value, not a description. "Bio Log", "Exercises", "Profile", "Dev Lab". Short and stable.

### 17.4 Subtitle Rules

Subtitles go on the same row, inline, after a muted dot separator:

```tsx
<span className="text-muted-foreground/50 text-xs select-none">·</span>
<span className="text-xs text-muted-foreground">{subtitle}</span>
```

**When to include a subtitle:**
- The subtitle must be ≤ 6 words and genuinely informative at a glance (e.g., "Readiness · Sleep · HRV", "198 exercises")
- Dynamic counts ("198 exercises") are ideal — they carry live information
- Facet summaries ("Readiness · Sleep · HRV") are ideal — they orient the user to what's inside

**When to omit:**
- Descriptive sentences ("The source methodologies that shape how programs are generated") → drop entirely or move to an empty state
- Anything that restates what the icon + title already communicate
- Long phrases that force the header to wrap

**Default: no subtitle** unless one of the above applies. Most tabs are self-explanatory.

### 17.5 Sub-tab Style

Sub-tabs in the header row use **pill button style** — not Radix `TabsList`. This is a deliberate distinction:

- **Header-level sub-tabs** (views of the same page): pill buttons
- **Content-level tabs** (tab groups within a section of the page): Radix `TabsList` with the standard `bg-muted` track

```tsx
<div className="ml-4 flex gap-1">
  {TABS.map(tab => (
    <button
      key={tab.id}
      onClick={() => setTab(tab.id)}
      className={cn(
        'px-3 py-1 rounded text-xs border transition-colors',
        activeTab === tab.id
          ? 'bg-primary/15 border-primary/40 text-primary'
          : 'border-border text-muted-foreground hover:bg-muted'
      )}
    >
      {tab.label}
    </button>
  ))}
</div>
```

- `ml-4` creates a visual separation from the identity block (not `gap-2` — the gap between identity and nav should be wider than the internal `gap-2`)
- Active: `bg-primary/15 border-primary/40 text-primary`
- Inactive: `border-border text-muted-foreground hover:bg-muted`
- Size: `px-3 py-1 text-xs` — compact, never taller than the title

### 17.6 Step Indicators (Wizard Flows)

For multi-step flows (Program Builder), replace sub-tabs with a step indicator pushed to the right:

```tsx
{/* after identity block */}
<span className="ml-auto text-xs text-muted-foreground">
  Step {currentStep} of {totalSteps}
</span>
```

Or dot indicators for ≤ 5 steps:

```tsx
<div className="ml-auto flex items-center gap-1.5">
  {Array.from({ length: totalSteps }, (_, i) => (
    <div
      key={i}
      className={cn(
        'size-1.5 rounded-full transition-colors',
        i < currentStep ? 'bg-primary' : 'bg-border'
      )}
    />
  ))}
</div>
```

Keep it small and muted — the step indicator orients, it doesn't dominate.

### 17.7 Action Buttons

Action buttons live at the far right, separated from navigation with `ml-auto` (or placed after a `flex-1` spacer if sub-tabs are also present):

```tsx
<div className="ml-auto flex items-center gap-1">
  <Button variant="ghost" size="icon" className="size-8">
    <SomeIcon className="size-4" />
  </Button>
</div>
```

- Always `variant="ghost" size="icon"` at `size-8` (32px) — stays compact in the header row
- Icon at `size-4` inside
- Only include actions that are genuinely page-level (not content-level). "Export", "Refresh", "Settings" — not "Add item" (that belongs in the content area).

**Layout when both sub-tabs and actions are present:**

```tsx
<div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
  <Icon className="size-5 text-primary" />
  <h1 className="text-lg font-semibold">Page Name</h1>
  {/* optional inline subtitle */}
  <span className="text-muted-foreground/50 text-xs">·</span>
  <span className="text-xs text-muted-foreground">subtitle</span>
  {/* sub-tabs pushed to center-right */}
  <div className="ml-4 flex gap-1">{/* pill tabs */}</div>
  {/* actions at far right */}
  <div className="ml-auto flex items-center gap-1">{/* icon buttons */}</div>
</div>
```

### 17.8 Per-Page Reference

Status as of 2026-07-30. ✅ = matches the spec in code; ⚠️ = documented divergence.

| Page | Icon | Title | Inline subtitle | Sub-tabs | Actions | Status |
|---|---|---|---|---|---|---|
| **Dashboard** | `LayoutDashboard` | "Dashboard" | None | Week · Overview (`TabSelector`) | Program settings sheet | ✅ — see §17.9 |
| **Bio Log** | `Activity` | "Bio Log" | "Readiness · Sleep · HRV" | None | None | ✅ |
| **Philosophies** | `BookOpen` | "Philosophies" | None | None | None | ✅ |
| **Program Builder** | `Wand2` | Dynamic step title | None | None | "Step N of 4" (right) | ✅ wizard variant |
| **Program View** | `CalendarDays` | Program name | "{N}-week program" | Overview · Calendar | Injury flags | ⚠️ two-row (`space-y-3`) — see §17.2 |
| **Profile** | `User` | "Profile" | None | Setup · Benchmarks | None | ✅ |
| **Exercises** | `Dumbbell` | "Exercises" | "{count} exercises" | None | None | ⚠️ two-row (`space-y-3`) — search row below |
| **Explore** | `Compass` | "Explore" | None | Section pills **+** topic selector (two tiers) | None | ✅ two-tier variant — see below |
| **Analytics** | `BarChart3` | "Analytics" | None | None | None | ✅ |
| **Dev Lab** | `Terminal` | "Dev Lab" | None | Pipeline Trace · Object Browser · Ontology | None | ✅ |
| **Import Workouts** | `ArrowDownToLine` | "Import Workouts" | None | None | None | ✅ |
| **Login** | — | "Training" | — | — | — | Exempt — pre-auth, centered card, outside app shell |
| **Session Detail** | Back-nav | Day/session context | — | — | — | Back-nav pattern, not tab header |
| **Workout Detail** | Back-nav | Workout type | — | — | — | Back-nav pattern, not tab header |

**On the two-row headers (Program View, Exercises).** §17.2 says a primary header is always one row. Both of these break it to host a secondary control strip — a search input, a week selector. The rule holds for the *identity row*; what these pages actually demonstrate is a legitimate second pattern:

```tsx
<div className="border-b px-6 py-4 space-y-3 shrink-0">
  <div className="flex items-center gap-2">{/* identity row — §17.2 exactly */}</div>
  <div>{/* control strip: search, week nav, filters */}</div>
</div>
```

The identity row keeps its contract; the strip below is content-scoped chrome. **Use it only for controls that filter or navigate the page's own content.** Page-level actions still belong in the identity row per §17.7.

Exercises is the clean example: identity row, then `<ExerciseSearch>`, then `<ExerciseFilters>`, all inside one `space-y-3` header block.

**Two-tier navigation (Explore).** Explore carries *two* levels of sub-tab — section pills (Explorer / Ontology / …), then a topic selector within the Explorer section — and stays on one row using `gap-3 flex-wrap` with `shrink-0` on each group:

```tsx
<div className="flex items-center gap-3 border-b px-6 py-4 shrink-0 flex-wrap">
  <Compass className="size-5 text-primary shrink-0" />
  <h1 className="text-lg font-semibold shrink-0">Explore</h1>
  <div className="flex gap-1 shrink-0">{/* tier 1: section pills */}</div>
  {section === 'explorer' && (
    <>
      <div className="w-px h-4 bg-border/60 shrink-0" />   {/* tier separator */}
      <TopicSelector active={topic} onChange={handleTopicChange} />
    </>
  )}
</div>
```

This is a legitimate third variant, not a violation. The rules it follows: `gap-3` (not `gap-2`) because two tab groups need more air between them than an icon needs from its title; `shrink-0` on every group so tabs never compress into illegibility; `flex-wrap` as the overflow behavior of last resort; and the second tier appears **conditionally**, only when its parent section is active — never two permanent tab rows.

**The `w-px h-4 bg-border/60` hairline is the established tier separator.** It appears in both Explore and Dashboard. Use it wherever a header holds two distinct control groups.

**On Dev Lab.** It remains the reference implementation for the header pattern, and now also carries the standard §9.1 page transition — so it is a valid whole-page reference again.

**Login is exempt.** It renders pre-auth, outside `RootLayout` and outside the router's `AnimatePresence`, so it has no sibling to transition against. It uses a centered card rather than a tab header. Intentional, not a gap.

### 17.9 Dashboard: Standard Header (revised)

> **Code diverges — code is correct.** This section previously declared Dashboard *exempt* from the tab header and prohibited a page-identity icon or "Dashboard" label. `Dashboard.tsx:351-353` now uses the standard header, with a `LayoutDashboard` icon and an h1 reading "Dashboard". **The code made the better call and the rule below is rewritten to match.**
>
> The exemption was written when Dashboard was a single view whose only meaningful title was the program name. It has since gained a Week/Overview sub-tab switcher. Once a page has sub-tabs, §17.5 governs where they live — immediately right of the identity block — and an identity block is exactly what the old rule forbade. The alternative would have been sub-tabs floating with no anchor, which reads as a detached control rather than page navigation.
>
> The old rule also over-weighted redundancy with the sidebar. The sidebar is hidden on mobile (§14.2), so on the layout where wayfinding is *most* fragile the h1 is the only page identity present. "Redundant on desktop" was the wrong axis to optimize.

**Dashboard uses the standard tab header.** As shipped:

```tsx
<div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
  <LayoutDashboard className="size-5 text-primary" />
  <h1 className="text-lg font-semibold">Dashboard</h1>
  <div className="ml-4 flex items-center gap-2">
    <div className="w-px h-4 bg-border/60 shrink-0" />   {/* vertical rule before sub-tabs */}
    <TabSelector active={activeTab} onChange={setActiveTab} />
  </div>
  <div className="ml-auto">
    <ProgramSettingsSheet program={program} />
  </div>
</div>
```

One refinement here is worth promoting to a general rule: **a `w-px h-4 bg-border/60` vertical rule between the identity block and the sub-tabs.** §17.5 specifies `ml-4` alone; the hairline reads more clearly when a page has both sub-tabs and right-aligned actions, because `ml-4` on its own is ambiguous against the `ml-auto` gap. Optional, but preferred on pages carrying both.

**Program identity moves into the content area.** The program name renders as `h1 text-2xl font-bold tracking-tight` at the top of the Week tab (`Dashboard.tsx:100`), with the week selector and phase bar beneath it. This is a better split than the old rule produced:

- **Header = page identity + page navigation.** Stable, always in the same place, matches every other tab.
- **Content = instance context.** The program name, week nav, and phase bar all describe *the program*, and they scroll with the program they describe.

The old design put instance context in fixed page chrome, which meant a user on the Overview tab still had week-navigation controls pinned above them that did nothing for that view.

**The "Program View Header" variant is retired.** Pages dedicated to one instance (Program View, Session Detail, Workout Detail) use either the standard header with the instance name as title, or the back-nav pattern (§13). There is no third variant.
