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
    const block = css.match(new RegExp(`${selector}\\s*\\{([\\s\\S]*?)\\n\\}`))
    if (!block) throw new Error(`No block for ${selector}`)
    const bg = block[1].match(/--background:\s*(oklch\([^)]+\))/)
    if (!bg) throw new Error(`No --background in ${selector}`)
    return parseOklch(bg[1])
  }
  return { light: grab(':root'), dark: grab('\\.dark'), military: grab('\\.military'), zen: grab('\\.zen') }
})()

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

