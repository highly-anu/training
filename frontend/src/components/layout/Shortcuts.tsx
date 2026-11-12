import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Keys } from '@/components/shared/Tip'
import { announce } from '@/lib/announce'
import { SEQUENCE_MS, SHORTCUTS, isTyping, readKey, type Shortcut } from '@/lib/shortcuts'
import { useProgramStore } from '@/store/programStore'
import { useUiStore } from '@/store/uiStore'

const GROUPS: Shortcut['group'][] = ['Go to', 'Program', 'Help']

/**
 * The keyboard shortcuts and the sheet that lists them (`lib/shortcuts.ts`,
 * docs/frontend-design.md §11.10). Mounted once, in the shell.
 */
export function Shortcuts() {
  const navigate = useNavigate()
  const open = useUiStore((s) => s.shortcutsOpen)
  const setOpen = useUiStore((s) => s.setShortcutsOpen)
  const prefix = useRef<{ key: string; at: number } | null>(null)

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.metaKey || event.ctrlKey || event.altKey || event.defaultPrevented) return
      if (isTyping(event.target)) return
      // A dialog, sheet or menu owns the keyboard while it is open.
      if (document.querySelector('[role="dialog"], [role="alertdialog"], [role="menu"]')) return

      const waiting = prefix.current && Date.now() - prefix.current.at < SEQUENCE_MS ? prefix.current.key : null
      const result = readKey(waiting, event.key)
      prefix.current = result.prefix ? { key: result.prefix, at: Date.now() } : null
      const action = result.action
      if (!action) return
      event.preventDefault()

      if (action.type === 'go') {
        navigate(action.to)
      } else if (action.type === 'help') {
        setOpen(true)
      } else {
        const weeks = useProgramStore.getState().currentProgram?.weeks.length ?? 0
        if (weeks === 0) return
        const { selectedWeekIndex, setSelectedWeekIndex } = useUiStore.getState()
        const next = Math.min(weeks - 1, Math.max(0, selectedWeekIndex + action.delta))
        if (next === selectedWeekIndex) return
        setSelectedWeekIndex(next)
        announce(`Week ${next + 1} of ${weeks}.`)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [navigate, setOpen])

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Keyboard shortcuts</DialogTitle>
          <DialogDescription>Two keys are pressed one after the other.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          {GROUPS.map((group) => (
            <section key={group}>
              <h3 className="mb-1 text-[10px] font-medium uppercase tracking-widest text-muted-foreground">{group}</h3>
              <dl>
                {SHORTCUTS.filter((s) => s.group === group).map((s) => (
                  <div key={s.keys} className="flex items-center justify-between py-1 text-sm">
                    <dt>{s.label}</dt>
                    <dd><Keys keys={s.keys} spoken /></dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  )
}
