import { AlertTriangle, RefreshCw } from 'lucide-react'
import { useProgramStore } from '@/store/programStore'
import { Button } from '@/components/ui/button'

/**
 * Tells the athlete when a program change did not reach the server.
 *
 * Every program mutation persists fire-and-forget. Before this, a failed save
 * was completely silent: the browser kept showing a program the server never
 * received, and it vanished on the next reload with no explanation. Given this
 * app has already lost a program once, a silent write failure is the last
 * thing it should do.
 */
export function ProgramSaveBanner() {
  const error = useProgramStore((s) => s.programSaveError)
  const currentProgram = useProgramStore((s) => s.currentProgram)
  const reload = useProgramStore((s) => s.loadFromServer)

  if (!error) return null

  // A stale revision is a conflict, not an outage: someone else's copy won, so
  // the honest fix is to re-pull rather than retry this write over the top.
  const isConflict = error === 'stale_revision'

  return (
    <div
      role="alert"
      className="flex items-center gap-3 border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-sm"
    >
      <AlertTriangle className="size-4 shrink-0 text-amber-500" />
      <p className="flex-1 leading-snug">
        {isConflict
          ? 'This program was changed somewhere else. Your latest edit was not saved — reload to pick up the newer version.'
          : "Your last change couldn't be saved. It's still on screen but not on the server, and will be lost if you reload."}
      </p>
      {isConflict ? (
        <Button size="sm" variant="outline" onClick={() => void reload()}>
          <RefreshCw className="size-3.5 mr-1" />
          Reload
        </Button>
      ) : (
        <Button
          size="sm"
          variant="outline"
          onClick={() => {
            // Re-saving the program already in the store is the retry.
            if (currentProgram) useProgramStore.getState().setCurrentProgram(currentProgram)
          }}
        >
          <RefreshCw className="size-3.5 mr-1" />
          Retry
        </Button>
      )}
    </div>
  )
}
