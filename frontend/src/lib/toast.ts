/**
 * The toast — for the two answers that have nowhere else to appear
 * (docs/frontend-design.md §11.6). Everything else answers in place: the
 * button that was pressed, the row that changed.
 *
 *   toast.undo    — something was removed, so its row is gone and cannot carry
 *                   its own Undo.
 *   toast.failed  — a write made in the background (an optimistic change, a
 *                   removal already off screen) did not reach the server.
 *
 * This is the only file that imports sonner's `toast`
 * (`test/designRules.test.ts`). A success is never a toast: the screen already
 * shows it.
 */
import { toast as sonner } from 'sonner'
import { announce } from '@/lib/announce'

/** Long enough to read and reach; short enough that the write is not in doubt. */
export const UNDO_WINDOW_MS = 6000

export interface UndoOptions {
  /** Put it back. */
  undo: () => void
  /** The window closed without an undo: make it permanent. Omit when the write already happened. */
  commit?: () => void
}

/**
 * "Workout removed · Undo". With `commit` the write waits for the window to
 * close (or the page to be left); without it the removal is already saved and
 * `undo` reverses it.
 */
function undo(message: string, { undo: undoFn, commit }: UndoOptions): void {
  let settled = false
  const settle = (fn?: () => void) => {
    if (settled) return
    settled = true
    window.removeEventListener('pagehide', onLeave)
    fn?.()
  }
  // Leaving the page inside the window must not quietly keep what was removed.
  const onLeave = () => settle(commit)
  window.addEventListener('pagehide', onLeave)

  announce(`${message}. Undo is available.`)
  sonner(message, {
    duration: UNDO_WINDOW_MS,
    action: {
      label: 'Undo',
      onClick: () => settle(() => { undoFn(); announce('Restored.') }),
    },
    onAutoClose: () => settle(commit),
    onDismiss: () => settle(commit),
  })
}

/** A background write failed: what did not happen, and the way to try again. */
function failed(message: string, retry?: () => void): void {
  sonner.error(message, {
    duration: retry ? 10_000 : UNDO_WINDOW_MS,
    action: retry ? { label: 'Try again', onClick: retry } : undefined,
  })
}

export const toast = { undo, failed }
