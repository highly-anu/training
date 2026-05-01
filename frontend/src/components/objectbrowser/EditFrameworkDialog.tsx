import { useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useUpdateFramework } from '@/api/frameworks'
import { usePhilosophies } from '@/api/philosophies'
import type { Framework, ModalityId } from '@/api/types'

const MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power', 'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning', 'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab']

interface SessionRow {
  modality: ModalityId | ''
  count: number
}

function sessionsToRows(spw: Record<string, number> | undefined): SessionRow[] {
  if (!spw) return []
  return Object.entries(spw).map(([modality, count]) => ({
    modality: modality as ModalityId,
    count,
  }))
}

interface Props {
  framework: Framework
  open: boolean
  onClose: () => void
}

export function EditFrameworkDialog({ framework, open, onClose }: Props) {
  const updateMutation = useUpdateFramework()
  const { data: philosophies = [] } = usePhilosophies()

  const [name, setName] = useState(framework.name ?? '')
  const [sourcePhilosophy, setSourcePhilosophy] = useState(
    (framework as unknown as Record<string, unknown>).source_philosophy as string ?? ''
  )
  const [sessionRows, setSessionRows] = useState<SessionRow[]>(
    sessionsToRows((framework as unknown as Record<string, unknown>).sessions_per_week as Record<string, number> | undefined)
  )
  const [notes, setNotes] = useState((framework as unknown as Record<string, unknown>).notes as string ?? '')

  function updateRow(i: number, field: keyof SessionRow, value: unknown) {
    setSessionRows(prev => prev.map((r, idx) => idx === i ? { ...r, [field]: value } : r))
  }

  function removeRow(i: number) {
    setSessionRows(prev => prev.filter((_, idx) => idx !== i))
  }

  function addRow() {
    setSessionRows(prev => [...prev, { modality: '', count: 1 }])
  }

  async function handleSubmit() {
    if (!name) return
    const sessions_per_week: Record<string, number> = {}
    for (const row of sessionRows) {
      if (row.modality) sessions_per_week[row.modality] = row.count
    }
    const payload = {
      id: framework.id,
      name,
      source_philosophy: sourcePhilosophy || undefined,
      sessions_per_week,
      ...(notes ? { notes } : {}),
    }
    try {
      await updateMutation.mutateAsync(payload as Parameters<ReturnType<typeof useUpdateFramework>['mutateAsync']>[0])
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!name && !updateMutation.isPending

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose() }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Framework — <span className="font-mono text-sm text-muted-foreground">{framework.id}</span></DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Name */}
          <div>
            <Label className="text-xs mb-1 block">Name *</Label>
            <Input value={name} onChange={e => setName(e.target.value)} className="h-8 text-xs" />
          </div>

          {/* Source philosophy */}
          <div>
            <Label className="text-xs mb-1 block">Source Philosophy</Label>
            <Select value={sourcePhilosophy} onValueChange={setSourcePhilosophy}>
              <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="None" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="" className="text-xs text-muted-foreground">None</SelectItem>
                {philosophies.map(p => (
                  <SelectItem key={p.id} value={p.id} className="text-xs">{p.name ?? p.id}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Sessions per week */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <Label className="text-xs">Sessions per Week</Label>
              <Button size="sm" variant="outline" className="h-6 text-xs" onClick={addRow}>
                <Plus className="size-3 mr-1" /> Add Modality
              </Button>
            </div>
            <div className="space-y-1.5">
              {sessionRows.map((row, i) => (
                <div key={i} className="flex items-center gap-2">
                  <Select value={row.modality} onValueChange={v => updateRow(i, 'modality', v as ModalityId)}>
                    <SelectTrigger className="h-7 text-xs flex-1"><SelectValue placeholder="Modality…" /></SelectTrigger>
                    <SelectContent>
                      {MODALITIES.map(m => <SelectItem key={m} value={m} className="text-xs">{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Input
                    value={row.count}
                    onChange={e => updateRow(i, 'count', Number(e.target.value) || 1)}
                    type="number" min={1} max={7}
                    className="h-7 text-xs w-14 text-center"
                  />
                  <span className="text-xs text-muted-foreground">×/wk</span>
                  <button onClick={() => removeRow(i)} className="text-muted-foreground hover:text-destructive transition-colors">
                    <Trash2 className="size-3.5" />
                  </button>
                </div>
              ))}
              {sessionRows.length === 0 && (
                <p className="text-xs text-muted-foreground">No sessions defined — add a modality above.</p>
              )}
            </div>
          </div>

          {/* Notes */}
          <div>
            <Label className="text-xs mb-1 block">Notes</Label>
            <textarea value={notes} onChange={e => setNotes(e.target.value)}
              className="w-full rounded-md border bg-transparent px-3 py-2 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={3} />
          </div>

          {updateMutation.isError && (
            <p className="text-xs text-destructive">{(updateMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit}>
            {updateMutation.isPending ? 'Saving…' : 'Save Changes'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
