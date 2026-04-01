import { useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useCreateArchetype } from '@/api/archetypes'
import type { Archetype, ModalityId, EquipmentId, TrainingPhase, TrainingLevel } from '@/api/types'

const MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power', 'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning', 'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab']
const CATEGORIES = ['strength', 'conditioning', 'kettlebell', 'gpp_durability', 'movement_skill']
const EQUIPMENT_OPTIONS: EquipmentId[] = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'ruck_pack', 'open_space', 'rings', 'sandbag', 'bike', 'rower', 'ghd', 'box', 'resistance_band', 'medicine_ball']
const PHASES: TrainingPhase[] = ['base', 'build', 'peak', 'taper', 'deload', 'maintenance', 'rehab', 'post_op']
const LEVELS: TrainingLevel[] = ['novice', 'intermediate', 'advanced', 'elite']
const SLOT_TYPES = ['sets_reps', 'time_domain', 'amrap', 'emom', 'rounds_for_time']
const INTENSITIES = ['zone1', 'zone2', 'zone3', 'zone4', 'zone4_5', 'submaximal', 'moderate', 'heavy', 'progressing', 'max', 'max_effort']

interface SlotDraft {
  role: string
  slot_type: string
  sets?: number
  reps?: number
  duration_sec?: number
  intensity: string
  rest_sec?: number
  notes: string
}

function emptySlot(): SlotDraft {
  return { role: '', slot_type: 'sets_reps', intensity: 'moderate', notes: '' }
}

function slugify(s: string) {
  return s.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '')
}

interface Props {
  open: boolean
  onClose: () => void
}

export function AddArchetypeDialog({ open, onClose }: Props) {
  const createMutation = useCreateArchetype()

  const [name, setName] = useState('')
  const [id, setId] = useState('')
  const [idManual, setIdManual] = useState(false)
  const [modality, setModality] = useState<ModalityId | ''>('')
  const [category, setCategory] = useState('')
  const [duration, setDuration] = useState('')
  const [equipment, setEquipment] = useState<EquipmentId[]>([])
  const [phases, setPhases] = useState<TrainingPhase[]>([])
  const [levels, setLevels] = useState<TrainingLevel[]>([])
  const [slots, setSlots] = useState<SlotDraft[]>([emptySlot()])
  const [notes, setNotes] = useState('')

  function handleNameChange(v: string) {
    setName(v)
    if (!idManual) setId(slugify(v))
  }

  function toggleEquipment(e: EquipmentId) {
    setEquipment(prev => prev.includes(e) ? prev.filter(x => x !== e) : [...prev, e])
  }

  function togglePhase(p: TrainingPhase) {
    setPhases(prev => prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p])
  }

  function toggleLevel(l: TrainingLevel) {
    setLevels(prev => prev.includes(l) ? prev.filter(x => x !== l) : [...prev, l])
  }

  function updateSlot(i: number, field: keyof SlotDraft, value: unknown) {
    setSlots(prev => prev.map((s, idx) => idx === i ? { ...s, [field]: value } : s))
  }

  function removeSlot(i: number) {
    setSlots(prev => prev.filter((_, idx) => idx !== i))
  }

  function reset() {
    setName(''); setId(''); setIdManual(false); setModality(''); setCategory('')
    setDuration(''); setEquipment([]); setPhases([]); setLevels([])
    setSlots([emptySlot()]); setNotes('')
    createMutation.reset()
  }

  async function handleSubmit() {
    if (!id || !name || !modality || !category) return
    const archetype: Partial<Archetype> = {
      id,
      name,
      modality: modality as ModalityId,
      category,
      duration_estimate_minutes: duration ? Number(duration) : 60,
      required_equipment: equipment,
      applicable_phases: phases,
      training_levels: levels,
      slots: slots.map(s => ({
        role: s.role,
        slot_type: s.slot_type,
        ...(s.sets != null ? { sets: s.sets } : {}),
        ...(s.reps != null ? { reps: s.reps } : {}),
        ...(s.duration_sec != null ? { duration_sec: s.duration_sec } : {}),
        intensity: s.intensity,
        ...(s.rest_sec != null ? { rest_sec: s.rest_sec } : {}),
        ...(s.notes ? { notes: s.notes } : {}),
      })),
      sources: [],
      ...(notes ? { notes } : {}),
    }
    try {
      await createMutation.mutateAsync(archetype)
      reset()
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!id && !!name && !!modality && !!category && !createMutation.isPending

  function toggleBtn(active: boolean) {
    return cn(
      'px-2 py-0.5 rounded text-[10px] border transition-colors font-mono',
      active
        ? 'bg-primary/15 border-primary/40 text-primary'
        : 'border-border text-muted-foreground hover:bg-muted'
    )
  }

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) { reset(); onClose() } }}>
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Archetype</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Name & ID */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Name *</Label>
              <Input value={name} onChange={e => handleNameChange(e.target.value)} placeholder="5×5 Linear" className="h-8 text-xs" />
            </div>
            <div>
              <Label className="text-xs mb-1 block">ID *</Label>
              <Input value={id} onChange={e => { setId(e.target.value); setIdManual(true) }} placeholder="5x5_linear" className="h-8 text-xs font-mono" />
            </div>
          </div>

          {/* Modality & Category */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Modality *</Label>
              <Select value={modality} onValueChange={v => setModality(v as ModalityId)}>
                <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Select…" /></SelectTrigger>
                <SelectContent>
                  {MODALITIES.map(m => <SelectItem key={m} value={m} className="text-xs">{m}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label className="text-xs mb-1 block">Category *</Label>
              <Select value={category} onValueChange={setCategory}>
                <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Select…" /></SelectTrigger>
                <SelectContent>
                  {CATEGORIES.map(c => <SelectItem key={c} value={c} className="text-xs">{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Duration */}
          <div className="w-32">
            <Label className="text-xs mb-1 block">Duration (min)</Label>
            <Input value={duration} onChange={e => setDuration(e.target.value)} type="number" placeholder="60" className="h-8 text-xs" />
          </div>

          {/* Equipment */}
          <div>
            <Label className="text-xs mb-1.5 block">Required Equipment</Label>
            <div className="flex flex-wrap gap-1">
              {EQUIPMENT_OPTIONS.map(eq => (
                <button key={eq} onClick={() => toggleEquipment(eq)} className={toggleBtn(equipment.includes(eq))}>
                  {eq}
                </button>
              ))}
            </div>
          </div>

          {/* Phases */}
          <div>
            <Label className="text-xs mb-1.5 block">Applicable Phases</Label>
            <div className="flex flex-wrap gap-1">
              {PHASES.map(p => (
                <button key={p} onClick={() => togglePhase(p)} className={toggleBtn(phases.includes(p))}>
                  {p}
                </button>
              ))}
            </div>
          </div>

          {/* Training levels */}
          <div>
            <Label className="text-xs mb-1.5 block">Training Levels</Label>
            <div className="flex flex-wrap gap-1">
              {LEVELS.map(l => (
                <button key={l} onClick={() => toggleLevel(l)} className={toggleBtn(levels.includes(l))}>
                  {l}
                </button>
              ))}
            </div>
          </div>

          {/* Slots */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <Label className="text-xs">Slots</Label>
              <Button size="sm" variant="outline" className="h-6 text-xs" onClick={() => setSlots(prev => [...prev, emptySlot()])}>
                <Plus className="size-3 mr-1" /> Add Slot
              </Button>
            </div>
            <div className="space-y-2">
              {slots.map((slot, i) => (
                <div key={i} className="rounded border bg-muted/30 p-3 space-y-2">
                  <div className="flex items-center gap-2">
                    <Input
                      value={slot.role}
                      onChange={e => updateSlot(i, 'role', e.target.value)}
                      placeholder="role (e.g. primary_squat)"
                      className="h-7 text-xs font-mono flex-1"
                    />
                    <Select value={slot.slot_type} onValueChange={v => updateSlot(i, 'slot_type', v)}>
                      <SelectTrigger className="h-7 text-xs w-36"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {SLOT_TYPES.map(t => <SelectItem key={t} value={t} className="text-xs">{t}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <button onClick={() => removeSlot(i)} className="text-muted-foreground hover:text-destructive transition-colors">
                      <Trash2 className="size-3.5" />
                    </button>
                  </div>
                  <div className="grid grid-cols-4 gap-2">
                    {(slot.slot_type === 'sets_reps' || slot.slot_type === 'emom') && (
                      <>
                        <Input value={slot.sets ?? ''} onChange={e => updateSlot(i, 'sets', e.target.value ? Number(e.target.value) : undefined)} type="number" placeholder="Sets" className="h-7 text-xs" />
                        <Input value={slot.reps ?? ''} onChange={e => updateSlot(i, 'reps', e.target.value ? Number(e.target.value) : undefined)} type="number" placeholder="Reps" className="h-7 text-xs" />
                      </>
                    )}
                    {(slot.slot_type === 'time_domain' || slot.slot_type === 'amrap' || slot.slot_type === 'rounds_for_time') && (
                      <Input value={slot.duration_sec ?? ''} onChange={e => updateSlot(i, 'duration_sec', e.target.value ? Number(e.target.value) : undefined)} type="number" placeholder="Duration (s)" className="h-7 text-xs col-span-2" />
                    )}
                    <Select value={slot.intensity} onValueChange={v => updateSlot(i, 'intensity', v)}>
                      <SelectTrigger className="h-7 text-xs"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {INTENSITIES.map(t => <SelectItem key={t} value={t} className="text-xs">{t}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <Input value={slot.rest_sec ?? ''} onChange={e => updateSlot(i, 'rest_sec', e.target.value ? Number(e.target.value) : undefined)} type="number" placeholder="Rest (s)" className="h-7 text-xs" />
                  </div>
                  <Input
                    value={slot.notes}
                    onChange={e => updateSlot(i, 'notes', e.target.value)}
                    placeholder="Slot notes…"
                    className="h-7 text-xs"
                  />
                </div>
              ))}
            </div>
          </div>

          {/* Notes */}
          <div>
            <Label className="text-xs mb-1 block">Notes</Label>
            <textarea
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="Implementation notes…"
              className="w-full rounded-md border bg-transparent px-3 py-2 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={3}
            />
          </div>

          {createMutation.isError && (
            <p className="text-xs text-destructive">{(createMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => { reset(); onClose() }}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit}>
            <Plus className="size-3 mr-1" />
            {createMutation.isPending ? 'Adding…' : 'Add Archetype'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
