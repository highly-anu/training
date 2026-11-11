/**
 * Colour maths + palette/theme sourcing for the contrast guard.
 *
 * Kept out of src/ deliberately: this is test-only machinery, and nothing in the
 * shipped bundle should depend on reading node_modules or globals.css at runtime.
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))

/** WCAG 2.1 AA for normal-size text. These badges render at 10-12px. */
export const AA_NORMAL = 4.5

// ── colour maths ─────────────────────────────────────────────────────────────

export interface Rgb { r: number; g: number; b: number }   // gamma-encoded sRGB, 0–1

/** oklch → linear sRGB (Björn Ottosson's matrices). */
function oklchToLinearRgb(L: number, C: number, hDeg: number): Rgb {
  const h = (hDeg * Math.PI) / 180
  const a = C * Math.cos(h)
  const bb = C * Math.sin(h)

  const l_ = L + 0.3963377774 * a + 0.2158037573 * bb
  const m_ = L - 0.1055613458 * a - 0.0638541728 * bb
  const s_ = L - 0.0894841775 * a - 1.291485548 * bb

  const l = l_ ** 3, m = m_ ** 3, s = s_ ** 3

  return {
    r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    b: -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  }
}

const clamp01 = (v: number) => Math.min(1, Math.max(0, v))

/** linear → gamma-encoded sRGB. Compositing happens in this space, as browsers do it. */
function encode(v: number): number {
  const c = clamp01(v)
  return c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055
}

/** gamma-encoded sRGB → linear, for luminance. */
function decode(v: number): number {
  return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
}

export function parseOklch(value: string): Rgb {
  // Handles both `oklch(0.141 0.005 285.823)` and `oklch(87.9% 0.169 91.605)`.
  const m = value.match(/oklch\(\s*([\d.]+)(%?)\s+([\d.]+)\s+([\d.]+)/)
  if (!m) throw new Error(`Unparseable oklch: ${value}`)
  const L = m[2] === '%' ? parseFloat(m[1]) / 100 : parseFloat(m[1])
  const lin = oklchToLinearRgb(L, parseFloat(m[3]), parseFloat(m[4]))
  return { r: encode(lin.r), g: encode(lin.g), b: encode(lin.b) }
}

export function luminance({ r, g, b }: Rgb): number {
  return 0.2126 * decode(r) + 0.7152 * decode(g) + 0.0722 * decode(b)
}

export function contrast(fg: Rgb, bg: Rgb): number {
  const a = luminance(fg), b = luminance(bg)
  const [hi, lo] = a > b ? [a, b] : [b, a]
  return (hi + 0.05) / (lo + 0.05)
}

/** Composite a translucent foreground over an opaque background (sRGB space). */
export function over(fg: Rgb, alpha: number, bg: Rgb): Rgb {
  return {
    r: fg.r * alpha + bg.r * (1 - alpha),
    g: fg.g * alpha + bg.g * (1 - alpha),
    b: fg.b * alpha + bg.b * (1 - alpha),
  }
}

// ── palette + theme token sources ────────────────────────────────────────────

/** Tailwind's real palette, e.g. PALETTE['emerald-700']. */
export const PALETTE: Record<string, Rgb> = (() => {
  const css = readFileSync(resolve(HERE, '../node_modules/tailwindcss/theme.css'), 'utf8')
  const out: Record<string, Rgb> = {}
  for (const m of css.matchAll(/--color-([a-z]+-\d{2,3}):\s*(oklch\([^)]+\))/g)) {
    out[m[1]] = parseOklch(m[2])
  }
  return out
})()

/** Each theme's --background, read from the app's own stylesheet. */
export const THEME_BG: Record<string, Rgb> = (() => {
  const css = readFileSync(resolve(HERE, '../src/styles/globals.css'), 'utf8')
  const grab = (selector: string) => {
    // Every block of the selector: `:root` holds the motion tokens in one and the palette in another.
    const blocks = [...css.matchAll(new RegExp(`\\n${selector}\\s*\\{([\\s\\S]*?)\\n\\}`, 'g'))]
    if (!blocks.length) throw new Error(`No block for ${selector}`)
    const bg = blocks.map((b) => b[1]).join('\n').match(/--background:\s*(oklch\([^)]+\))/)
    if (!bg) throw new Error(`No --background in ${selector}`)
    return parseOklch(bg[1])
  }
  return { light: grab(':root'), dark: grab('\\.dark'), military: grab('\\.military'), zen: grab('\\.zen') }
})()

const THEME_SELECTORS: Record<string, string> = {
  light: ':root', dark: '\\.dark', military: '\\.military', zen: '\\.zen',
}

export interface Oklch { l: number; c: number; h: number }

/**
 * One theme token as the browser resolves it: the theme's own declaration,
 * else `:root`'s (a theme class sits on `<html>`, so it inherits what it does
 * not redefine), following `var(--other)` once per hop.
 */
export function themeToken(theme: string, name: string): Oklch {
  const css = readFileSync(resolve(HERE, '../src/styles/globals.css'), 'utf8')
  const block = (selector: string) => {
    const all = [...css.matchAll(new RegExp(`\\n${selector}\\s*\\{([\\s\\S]*?)\\n\\}`, 'g'))]
    if (!all.length) throw new Error(`No block for ${selector}`)
    return all.map((b) => b[1]).join('\n')
  }
  const own = block(THEME_SELECTORS[theme])
  const root = block(':root')
  const read = (token: string, hops = 0): string => {
    if (hops > 4) throw new Error(`--${token} does not resolve in ${theme}`)
    const decl = new RegExp(`--${token}:\\s*([^;]+);`)
    const value = (own.match(decl) ?? root.match(decl))?.[1].trim()
    if (!value) throw new Error(`No --${token} in ${theme}`)
    const ref = value.match(/^var\(--([a-z-]+)\)$/)
    return ref ? read(ref[1], hops + 1) : value
  }
  const m = read(name).match(/oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)/)
  if (!m) throw new Error(`--${name} in ${theme} is not oklch`)
  return { l: parseFloat(m[1]), c: parseFloat(m[2]), h: parseFloat(m[3]) }
}

export const toRgb = ({ l, c, h }: Oklch): Rgb => parseOklch(`oklch(${l} ${c} ${h})`)

/** Degrees between two hues, the short way round. */
export function hueDistance(a: Oklch, b: Oklch): number {
  const d = Math.abs(a.h - b.h) % 360
  return d > 180 ? 360 - d : d
}

/** Themes whose surface is dark, so the `dark:` half of a pair applies. */
export const DARK_THEMES = new Set(['dark', 'military'])

// ── class-string parsing ─────────────────────────────────────────────────────

export const SHADE = String.raw`[a-z]+-\d{2,3}`

/** `bg-emerald-500/15` → { key: 'emerald-500', alpha: 0.15 }. Alpha defaults to 1. */
export function parseBg(classes: string): { key: string; alpha: number } | null {
  const m = classes.match(new RegExp(String.raw`(?:^|\s)bg-(${SHADE})(?:/(\d+))?\b`))
  return m ? { key: m[1], alpha: m[2] ? Number(m[2]) / 100 : 1 } : null
}

/** Extracts the light (bare) and dark (`dark:`) text shades from a class string. */
export function parseText(classes: string): { light: string | null; dark: string | null } {
  const light = classes.match(new RegExp(String.raw`(?:^|\s)text-(${SHADE})\b`))
  const dark = classes.match(new RegExp(String.raw`dark:text-(${SHADE})\b`))
  return { light: light?.[1] ?? null, dark: dark?.[1] ?? null }
}

export function shade(key: string): Rgb {
  const c = PALETTE[key]
  if (!c) throw new Error(`Unknown Tailwind colour: ${key}`)
  return c
}

/**
 * Resolve the effective contrast of a semantic swatch in one theme.
 * The text sits on its own translucent tint, which sits on the theme background.
 */
export function ratioFor(theme: string, textClasses: string, bgClasses: string): number {
  const isDark = DARK_THEMES.has(theme)
  const text = parseText(textClasses)
  const key = isDark ? (text.dark ?? text.light) : text.light
  if (!key) throw new Error(`No text colour in: "${textClasses}"`)

  const pageBg = THEME_BG[theme]
  const tint = parseBg(bgClasses)
  const surface = tint ? over(shade(tint.key), tint.alpha, pageBg) : pageBg

  return contrast(shade(key), surface)
}

