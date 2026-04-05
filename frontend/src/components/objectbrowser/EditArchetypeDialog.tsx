import { useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useUpdateArchetype } from '@/api/archetypes'
import type { Archetype, ModalityId, EquipmentId, TrainingPhase, TrainingLevel } from '@/api/types'

const MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power', 'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning', 'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab']
const CATEGORIES = ['strength', 'conditioning', 'kettlebell', 'gpp_durability', 'movement_skill', 'combat_sport']
const EQUIPMENT_OPTIONS: EquipmentId[] = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'ruck_pack', 'open_space', 'rings', 'sandbag', 'bike', 'rower', 'ghd', 'box', 'resistance_band', 'medicine_ball']
const PHASES: TrainingPhase[] = ['base', 'build', 'peak', 'taper', 'deload', 'maintenance', 'rehab', 'post_op']
const LEVELS: TrainingLevel[] = ['novice', 'intermediate', 'advanced', 'elite']
const SLOT_TYPES = ['sets_reps', 'time_domain', 'amrap', 'emom', 'rounds_for_time', 'static_hold', 'for_time', 'skill_practice', 'distance', 'amrap_movement']
const INTENSITIES = ['zone1', 'zone2', 'zone3', 'zone4', 'zone4_5', 'submaximal', 'moderate', 'heavy', 'light', 'progressing', 'max', 'max_effort']

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

function toSlotDraft(slot: Record<string, unknown>): SlotDraft {
  return {
    role: (slot.role as string) ?? '',
    slot_type: (slot.slot_type as string) ?? 'sets_reps',
    sets: slot.sets as number | undefined,
    reps: slot.reps as number | undefined,
    duration_sec: slot.duration_sec as number | undefined,
    intensity: (slot.intensity as string) ?? 'moderate',
    rest_sec: slot.rest_sec as number | undefined,
    notes: (slot.notes as string) ?? '',
  }
}

interface Props {
  archetype: Archetype
  open: boolean
  onClose: () => void
}

export function EditArchetypeDialog({ archetype, open, onClose }: Props) {
  const updateMutation = useUpdateArchetype()

  const [name, setName] = useState(archetype.name ?? '')
  const [modality, setModality] = useState<ModalityId | ''>(archetype.modality ?? '')
  const [category, setCategory] = useState(archetype.category ?? '')
  const [duration, setDuration] = useState(String(archetype.duration_estimate_minutes ?? ''))
  const [equipment, setEquipment] = useState<EquipmentId[]>((archetype.required_equipment as EquipmentId[]) ?? [])
  const [phases, setPhases] = useState<TrainingPhase[]>((archetype.applicable_phases as TrainingPhase[]) ?? [])
  const [levels, setLevels] = useState<TrainingLevel[]>((archetype.training_levels as TrainingLevel[]) ?? [])
  const [slots, setSlots] = useState<SlotDraft[]>(
    ((archetype.slots as unknown as Record<string, unknown>[]) ?? []).map(toSlotDraft)
  )
  const [notes, setNotes] = useState(archetype.notes ?? '')

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

  async function handleSubmit() {
    if (!name || !modality || !category) return
    const payload: Partial<Archetype> & { id: string } = {
      id: archetype.id,
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
      ...(notes ? { notes } : {}),
    }
    try {
      await updateMutation.mutateAsync(payload)
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!name && !!modality && !!category && !updateMutation.isPending

  function toggleBtn(active: boolean) {
    return cn(
      'px-2 py-0.5 rounded text-[10px] border transition-colors font-mono',
      active
        ? 'bg-primary/15 border-primary/40 text-primary'
        : 'border-border text-muted-foreground hover:bg-muted'
    )
  }

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose() }}>
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Archetype — <span className="font-mono text-sm text-muted-foreground">{archetype.id}</span></DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Name (ID is read-only) */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Name *</Label>
              <Input value={name} onChange={e => setName(e.target.value)} className="h-8 text-xs" />
            </div>
            <div>
              <Label className="text-xs mb-1 block">ID (read-only)</Label>
              <Input value={archetype.id} readOnly className="h-8 text-xs font-mono opacity-50" />
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
            <Input value={duration} onChange={e => setDuration(e.target.value)} type="number" className="h-8 text-xs" />
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
              <Button size="sm" variant="outline" className="h-6 text-xs"
                onClick={() => setSlots(prev => [...prev, { role: '', slot_type: 'sets_reps', intensity: 'moderate', notes: '' }])}>
                <Plus className="size-3 mr-1" /> Add Slot
              </Button>
            </div>
            <div className="space-y-2">
              {slots.map((slot, i) => (
                <div key={i} className="rounded border bg-muted/30 p-3 space-y-2">
                  <div className="flex items-center gap-2">
                    <Input value={slot.role} onChange={e => updateSlot(i, 'role', e.target.value)}
                      placeholder="role" className="h-7 text-xs font-mono flex-1" />
                    <Select value={slot.slot_type} onValueChange={v => updateSlot(i, 'slot_type', v)}>
                      <SelectTrigger className="h-7 text-xs w-40"><SelectValue /></SelectTrigger>
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
                    {(slot.slot_type === 'time_domain' || slot.slot_type === 'amrap' || slot.slot_type === 'rounds_for_time' || slot.slot_type === 'static_hold' || slot.slot_type === 'skill_practice') && (
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
                  <Input value={slot.notes} onChange={e => updateSlot(i, 'notes', e.target.value)}
                    placeholder="Slot notes…" className="h-7 text-xs" />
                </div>
              ))}
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
