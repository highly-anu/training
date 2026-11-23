import { useState } from 'react'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useEditMethod } from '@/api/methods'
import { cleanName, editRefusal, NAME_MAX } from '@/lib/methodBuild'

/**
 * Renames one of the athlete's methods: saved at once, no build. The program
 * built from it takes the new name; earlier blocks keep theirs.
 */
export function RenameMethodDialog({ method, onClose }: {
  method: { id: string; name: string } | null
  onClose: () => void
}) {
  return (
    <Dialog open={method !== null} onOpenChange={(open) => { if (!open) onClose() }}>
      <DialogContent className="sm:max-w-md">
        {method && <RenameForm key={method.id} method={method} onClose={onClose} />}
      </DialogContent>
    </Dialog>
  )
}

function RenameForm({ method, onClose }: { method: { id: string; name: string }; onClose: () => void }) {
  const [text, setText] = useState(method.name)
  const edit = useEditMethod()
  const name = cleanName(text)
  const unchanged = name === method.name
  const save = () => {
    if (!name || unchanged) return
    edit.mutate({ id: method.id, edits: { name } }, { onSuccess: onClose })
  }
  return (
    <form onSubmit={(e) => { e.preventDefault(); save() }} className="space-y-4">
      <DialogHeader>
        <DialogTitle>Rename method</DialogTitle>
        <DialogDescription>
          Your program and its sessions keep running; only the name changes.
        </DialogDescription>
      </DialogHeader>
      <div className="space-y-1.5">
        <Input value={text} onChange={(e) => setText(e.target.value)} maxLength={NAME_MAX + 20}
          aria-label="Method name" aria-invalid={!name} />
        {!name && <p className="text-xs text-muted-foreground">A name is 1 to {NAME_MAX} characters.</p>}
        {edit.isError && <p role="alert" className="text-xs text-bad">{editRefusal(edit.error)}</p>}
      </div>
      <DialogFooter>
        <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
        <Button type="submit" disabled={!name || unchanged} loading={edit.isPending}>Rename</Button>
      </DialogFooter>
    </form>
  )
}
