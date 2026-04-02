# Frontend Design System

A complete record of the visual language, interaction patterns, component architecture, and implementation details used in this project. Written to be portable — everything here can be used to establish the same design system in a new project from scratch.

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

---

## 2. Technology Stack

```
React 19 + Vite 8 + TypeScript
Tailwind CSS v4
shadcn/ui (Radix UI primitives + custom styling)
Framer Motion v12
@dnd-kit/core v6 (drag-and-drop)
Recharts v3 (data visualization)
Lucide React (icons)
class-variance-authority (CVA, component variants)
clsx + tailwind-merge (cn() utility)
```

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

All colors are defined as CSS custom properties on `:root` (light) and `.dark`, `.military`, `.zen` theme classes. Components reference tokens, never raw values.

**Dark theme (default):**
```css
:root {
  --background:        oklch(0.141 0.005 285.823);  /* dark navy */
  --foreground:        oklch(0.985 0 0);             /* near-white */
  --card:              oklch(0.21 0.006 285.885);    /* slightly lighter navy */
  --card-foreground:   oklch(0.985 0 0);
  --primary:           oklch(0.769 0.188 70.08);     /* amber-500 */
  --primary-foreground: oklch(0.282 0.065 51.617);   /* dark brown */
  --secondary:         oklch(0.274 0.006 286.033);   /* dark gray */
  --secondary-foreground: oklch(0.985 0 0);
  --muted:             oklch(0.274 0.006 286.033);
  --muted-foreground:  oklch(0.552 0.016 285.938);   /* medium gray */
  --accent:            oklch(0.274 0.006 286.033);
  --accent-foreground: oklch(0.985 0 0);
  --destructive:       oklch(0.704 0.191 22.216);    /* red */
  --border:            oklch(1 0 0 / 10%);           /* white 10% */
  --input:             oklch(1 0 0 / 15%);           /* white 15% */
  --ring:              oklch(0.769 0.188 70.08);     /* amber (focus) */
  --radius:            0.5rem;
}
```

**Light theme:**
```css
.light {
  --background:        oklch(1 0 0);
  --foreground:        oklch(0.141 0.005 285.823);
  --card:              oklch(1 0 0);
  --primary:           oklch(0.769 0.188 70.08);     /* amber — same as dark */
  --border:            oklch(0.92 0.004 286.32);
  --input:             oklch(0.92 0.004 286.32);
  --muted:             oklch(0.967 0.001 286.375);
  --muted-foreground:  oklch(0.552 0.016 285.938);
}
```

**Key principle:** `--primary` (amber) is identical in all themes. Brand color is consistent.

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
font-family: "Lora", Georgia, serif;
```

No web fonts are loaded by default — system fonts provide zero-cost performance. Theme variants that load web fonts (Zen, Military) do so optionally.

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

Three domain-specific color vocabularies sit on top of the base token system. These use raw Tailwind color classes (not tokens) because the specific color is intentional information.

### 8.1 Modality Colors

Training modalities are color-coded consistently everywhere: badges, session card top bars, chart series, drag ghost indicators.

```typescript
const MODALITY_COLORS = {
  max_strength:            { hex: '#ef4444', bg: 'bg-red-500/15',    text: 'text-red-400',    border: 'border-red-500/40'    },
  strength_endurance:      { hex: '#f97316', bg: 'bg-orange-500/15', text: 'text-orange-400', border: 'border-orange-500/40' },
  relative_strength:       { hex: '#f43f5e', bg: 'bg-rose-500/15',   text: 'text-rose-400',   border: 'border-rose-500/40'   },
  aerobic_base:            { hex: '#0ea5e9', bg: 'bg-sky-500/15',    text: 'text-sky-400',    border: 'border-sky-500/40'    },
  anaerobic_intervals:     { hex: '#06b6d4', bg: 'bg-cyan-500/15',   text: 'text-cyan-400',   border: 'border-cyan-500/40'   },
  mixed_modal_conditioning:{ hex: '#8b5cf6', bg: 'bg-violet-500/15', text: 'text-violet-400', border: 'border-violet-500/40' },
  power:                   { hex: '#eab308', bg: 'bg-yellow-500/15', text: 'text-yellow-500', border: 'border-yellow-500/40' },
  mobility:                { hex: '#10b981', bg: 'bg-emerald-500/15',text: 'text-emerald-400',border: 'border-emerald-500/40'},
  movement_skill:          { hex: '#14b8a6', bg: 'bg-teal-500/15',   text: 'text-teal-400',   border: 'border-teal-500/40'   },
  durability:              { hex: '#f59e0b', bg: 'bg-amber-500/15',  text: 'text-amber-500',  border: 'border-amber-500/40'  },
  combat_sport:            { hex: '#ec4899', bg: 'bg-pink-500/15',   text: 'text-pink-400',   border: 'border-pink-500/40'   },
  rehab:                   { hex: '#84cc16', bg: 'bg-lime-500/15',   text: 'text-lime-400',   border: 'border-lime-500/40'   },
}
```

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
const PHASE_COLORS = {
  base:        { hex: '#0ea5e9', bg: 'bg-sky-500/15',    text: 'text-sky-400',    label: 'Base'        },
  build:       { hex: '#f59e0b', bg: 'bg-amber-500/15',  text: 'text-amber-500',  label: 'Build'       },
  peak:        { hex: '#ef4444', bg: 'bg-red-500/15',    text: 'text-red-400',    label: 'Peak'        },
  taper:       { hex: '#22c55e', bg: 'bg-green-500/15',  text: 'text-green-400',  label: 'Taper'       },
  deload:      { hex: '#94a3b8', bg: 'bg-slate-500/15',  text: 'text-slate-400',  label: 'Deload'      },
  maintenance: { hex: '#a1a1aa', bg: 'bg-zinc-500/15',   text: 'text-zinc-400',   label: 'Maintenance' },
  rehab:       { hex: '#84cc16', bg: 'bg-lime-500/15',   text: 'text-lime-400',   label: 'Rehab'       },
  post_op:     { hex: '#a855f7', bg: 'bg-purple-500/15', text: 'text-purple-400', label: 'Post-Op'     },
}
```

**Intuitive mapping:** Blue = foundation, Amber = building heat, Red = peak intensity, Green = tapering down, Gray = recovery/maintenance.

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

All charts use Recharts with minimal configuration. Custom components handle wrapper sizing and tooltips.

**Responsive container pattern:**
```tsx
<ResponsiveContainer width="100%" height={180}>
  <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
    ...
  </BarChart>
</ResponsiveContainer>
```

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

- [ ] Set up `AnimatePresence mode="wait"` in the router
- [ ] Apply the standard page transition to every page component
- [ ] Add staggered entry to any list/grid with > 3 items
- [ ] Use `whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}` on interactive cards
- [ ] Use the expand/collapse pattern for any collapsible section

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
