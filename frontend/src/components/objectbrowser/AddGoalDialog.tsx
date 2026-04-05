import { useState } from 'react'
import { Plus, Trash2, GripVertical } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useCreateGoal } from '@/api/goals'
import { useFrameworks } from '@/api/frameworks'
import type { ModalityId, TrainingPhase } from '@/api/types'

const MODALITIES: ModalityId[] = [
  'max_strength', 'relative_strength', 'strength_endurance', 'power',
  'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning',
  'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab',
]
const PHASES: TrainingPhase[] = ['base', 'build', 'peak', 'taper', 'deload', 'maintenance', 'rehab', 'post_op']

function slugify(s: string) {
  return s.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '')
}

interface PhaseRow {
  phase: TrainingPhase | ''
  weeks: string
  focus: string
}

interface PriorityRow {
  modality: ModalityId | ''
  weight: string
}

interface Props {
  open: boolean
  onClose: () => void
}

export function AddGoalDialog({ open, onClose }: Props) {
  const createMutation = useCreateGoal()
  const { data: frameworks = [] } = useFrameworks()

  const [name, setName] = useState('')
  const [id, setId] = useState('')
  const [idManual, setIdManual] = useState(false)
  const [description, setDescription] = useState('')
  const [forcedFramework, setForcedFramework] = useState('')
  const [priorities, setPriorities] = useState<PriorityRow[]>([{ modality: '', weight: '' }])
  const [phases, setPhases] = useState<PhaseRow[]>([{ phase: '', weeks: '', focus: '' }])

  function handleNameChange(v: string) {
    setName(v)
    if (!idManual) setId(slugify(v))
  }

  function handleIdChange(v: string) {
    setId(v)
    setIdManual(true)
  }

  // Priority rows
  function setPriorityField(i: number, field: keyof PriorityRow, val: string) {
    setPriorities(prev => prev.map((row, idx) => idx === i ? { ...row, [field]: val } : row))
  }
  function addPriorityRow() {
    setPriorities(prev => [...prev, { modality: '', weight: '' }])
  }
  function removePriorityRow(i: number) {
    setPriorities(prev => prev.filter((_, idx) => idx !== i))
  }

  // Phase rows
  function setPhaseField(i: number, field: keyof PhaseRow, val: string) {
    setPhases(prev => prev.map((row, idx) => idx === i ? { ...row, [field]: val } : row))
  }
  function addPhaseRow() {
    setPhases(prev => [...prev, { phase: '', weeks: '', focus: '' }])
  }
  function removePhaseRow(i: number) {
    setPhases(prev => prev.filter((_, idx) => idx !== i))
  }

  const priorityTotal = priorities.reduce((sum, r) => sum + (Number(r.weight) || 0), 0)
  const priorityOk = Math.abs(priorityTotal - 1.0) <= 0.05

  function reset() {
    setName(''); setId(''); setIdManual(false); setDescription('')
    setForcedFramework('')
    setPriorities([{ modality: '', weight: '' }])
    setPhases([{ phase: '', weeks: '', focus: '' }])
    createMutation.reset()
  }

  async function handleSubmit() {
    if (!id || !name) return
    const priorityMap: Record<string, number> = {}
    for (const row of priorities) {
      if (row.modality && row.weight) priorityMap[row.modality] = Number(row.weight)
    }
    const phaseSequence = phases
      .filter(r => r.phase && r.weeks)
      .map(r => ({ phase: r.phase, weeks: Number(r.weeks), ...(r.focus ? { focus: r.focus } : {}) }))

    const payload = {
      id,
      name,
      ...(description ? { description } : {}),
      priorities: priorityMap,
      phase_sequence: phaseSequence,
      primary_sources: [],
      minimum_prerequisites: {},
      incompatible_with: [],
      ...(forcedFramework ? { forced_framework: forcedFramework } : {}),
      framework_selection: {
        default_framework: forcedFramework || 'concurrent_training',
        alternatives: [],
      },
    }
    try {
      await createMutation.mutateAsync(payload)
      reset()
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!id && !!name && priorityOk && priorities.some(r => r.modality && r.weight) && !createMutation.isPending

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) { reset(); onClose() } }}>
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Goal</DialogTitle>
        </DialogHeader>

        <div className="space-y-5 py-2">
          {/* Name & ID */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Name *</Label>
              <Input value={name} onChange={e => handleNameChange(e.target.value)} placeholder="My Goal" className="h-8 text-xs" />
            </div>
            <div>
              <Label className="text-xs mb-1 block">ID *</Label>
              <Input value={id} onChange={e => handleIdChange(e.target.value)} placeholder="my_goal" className="h-8 text-xs font-mono" />
            </div>
          </div>

          {/* Description */}
          <div>
            <Label className="text-xs mb-1 block">Description</Label>
            <textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              placeholder="Goal description…"
              className="w-full rounded-md border bg-transparent px-3 py-2 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={2}
            />
          </div>

          {/* Priorities */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <Label className="text-xs">Priorities * <span className={cn('ml-2 font-mono', priorityTotal > 0 ? (priorityOk ? 'text-green-500' : 'text-destructive') : 'text-muted-foreground')}>sum={priorityTotal.toFixed(2)}</span></Label>
              <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={addPriorityRow}>
                <Plus className="size-3 mr-1" /> Add Row
              </Button>
            </div>
            <div className="space-y-1.5">
              {priorities.map((row, i) => (
                <div key={i} className="flex gap-2 items-center">
                  <Select value={row.modality} onValueChange={v => setPriorityField(i, 'modality', v)}>
                    <SelectTrigger className="h-7 text-xs flex-1"><SelectValue placeholder="Modality…" /></SelectTrigger>
                    <SelectContent>
                      {MODALITIES.map(m => <SelectItem key={m} value={m} className="text-xs font-mono">{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Input
                    value={row.weight}
                    onChange={e => setPriorityField(i, 'weight', e.target.value)}
                    type="number"
                    step="0.05"
                    min="0"
                    max="1"
                    placeholder="0.20"
                    className="h-7 text-xs w-20"
                  />
                  <button onClick={() => removePriorityRow(i)} className="text-muted-foreground hover:text-destructive">
                    <Trash2 className="size-3.5" />
                  </button>
                </div>
              ))}
            </div>
            {!priorityOk && priorityTotal > 0 && (
              <p className="text-xs text-destructive mt-1">Priorities must sum to ~1.0 (±0.05)</p>
            )}
          </div>

          {/* Phase sequence */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <Label className="text-xs">Phase Sequence</Label>
              <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={addPhaseRow}>
                <Plus className="size-3 mr-1" /> Add Phase
              </Button>
            </div>
            <div className="space-y-2">
              {phases.map((row, i) => (
                <div key={i} className="flex gap-2 items-start">
                  <GripVertical className="size-3.5 mt-2 text-muted-foreground/40 shrink-0" />
                  <Select value={row.phase} onValueChange={v => setPhaseField(i, 'phase', v)}>
                    <SelectTrigger className="h-7 text-xs w-28 shrink-0"><SelectValue placeholder="Phase…" /></SelectTrigger>
                    <SelectContent>
                      {PHASES.map(p => <SelectItem key={p} value={p} className="text-xs">{p}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Input
                    value={row.weeks}
                    onChange={e => setPhaseField(i, 'weeks', e.target.value)}
                    type="number"
                    min="1"
                    placeholder="wks"
                    className="h-7 text-xs w-14 shrink-0"
                  />
                  <Input
                    value={row.focus}
                    onChange={e => setPhaseField(i, 'focus', e.target.value)}
                    placeholder="Focus description…"
                    className="h-7 text-xs flex-1"
                  />
                  <button onClick={() => removePhaseRow(i)} className="text-muted-foreground hover:text-destructive mt-1.5">
                    <Trash2 className="size-3.5" />
                  </button>
                </div>
              ))}
            </div>
          </div>

          {/* Default framework */}
          <div>
            <Label className="text-xs mb-1 block">Default Framework (optional)</Label>
            <Select value={forcedFramework || '__none__'} onValueChange={v => setForcedFramework(v === '__none__' ? '' : v)}>
              <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Auto-select…" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__none__" className="text-xs text-muted-foreground">Auto-select</SelectItem>
                {frameworks.map(fw => (
                  <SelectItem key={fw.id} value={fw.id} className="text-xs font-mono">{fw.id}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {createMutation.isError && (
            <p className="text-xs text-destructive">{(createMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => { reset(); onClose() }}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit}>
            <Plus className="size-3 mr-1" />
            {createMutation.isPending ? 'Adding…' : 'Add Goal'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
