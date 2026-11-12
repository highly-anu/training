/**
 * The keyboard shortcuts (docs/frontend-design.md §11.10). One table: the
 * handler, the "?" sheet and the sidebar's hints all read it, so a shortcut
 * that works is a shortcut that is listed.
 *
 * `g` then a letter goes to a section, in the sidebar's order; `[` and `]`
 * step the program week; `?` lists them. Nothing fires while a field has the
 * keyboard or a dialog is open, and nothing uses a modifier, so no browser or
 * screen-reader command is taken.
 */

export type ShortcutAction =
  | { type: 'go'; to: string }
  | { type: 'week'; delta: -1 | 1 }
  | { type: 'help' }

export interface Shortcut {
  /** The keys in order, space-separated: "g t" is g, then t. */
  keys: string
  label: string
  group: 'Go to' | 'Program' | 'Help'
  action: ShortcutAction
}

export const SHORTCUTS: readonly Shortcut[] = [
  { keys: 'g t', label: 'Today', group: 'Go to', action: { type: 'go', to: '/' } },
  { keys: 'g p', label: 'Program', group: 'Go to', action: { type: 'go', to: '/program' } },
  { keys: 'g a', label: 'Analytics', group: 'Go to', action: { type: 'go', to: '/analytics' } },
  { keys: 'g l', label: 'Log', group: 'Go to', action: { type: 'go', to: '/log' } },
  { keys: 'g e', label: 'Explore', group: 'Go to', action: { type: 'go', to: '/explore' } },
  { keys: 'g u', label: 'Profile', group: 'Go to', action: { type: 'go', to: '/profile' } },
  { keys: 'g s', label: 'Settings', group: 'Go to', action: { type: 'go', to: '/settings' } },
  { keys: '[', label: 'Previous week', group: 'Program', action: { type: 'week', delta: -1 } },
  { keys: ']', label: 'Next week', group: 'Program', action: { type: 'week', delta: 1 } },
  { keys: '?', label: 'Keyboard shortcuts', group: 'Help', action: { type: 'help' } },
]

/** The keys that go to a route, for the sidebar's hint. */
export function keysFor(to: string): string | undefined {
  return SHORTCUTS.find((s) => s.action.type === 'go' && s.action.to === to)?.keys
}

/** How long a first key waits for its second. */
export const SEQUENCE_MS = 1200

export interface KeyResult {
  action?: ShortcutAction
  /** The first key of a sequence, waiting for the next. */
  prefix: string | null
}

/**
 * One key press against the table. `prefix` is the first key of a sequence
 * already pressed, or null. A key that completes nothing clears the prefix.
 */
export function readKey(prefix: string | null, key: string): KeyResult {
  const typed = prefix ? `${prefix} ${key}` : key
  const hit = SHORTCUTS.find((s) => s.keys === typed)
  if (hit) return { action: hit.action, prefix: null }
  if (!prefix && SHORTCUTS.some((s) => s.keys.startsWith(`${key} `))) return { prefix: key }
  return { prefix: null }
}

/** A field has the keyboard: letters are text, not commands. */
/** What owns the keyboard while it is open: a dialog, a sheet, a menu, a select's list. */
export const OWNS_KEYBOARD = '[role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"]'

export function isTyping(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  if (target.isContentEditable) return true
  const tag = target.tagName
  if (tag === 'TEXTAREA' || tag === 'SELECT') return true
  if (tag === 'INPUT') {
    const type = (target as HTMLInputElement).type
    return !['checkbox', 'radio', 'button', 'submit', 'range'].includes(type)
  }
  return target.getAttribute('role') === 'textbox' || target.getAttribute('role') === 'combobox'
}
