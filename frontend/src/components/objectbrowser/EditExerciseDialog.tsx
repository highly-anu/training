import { useState, useEffect } from 'react'
import { X } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useUpdateExercise } from '@/api/exercises'
import type { Exercise, ModalityId, EquipmentId } from '@/api/types'

const CATEGORIES = ['barbell', 'kettlebell', 'bodyweight', 'aerobic', 'carries', 'sandbag', 'mobility', 'skill', 'rehab', 'gym_jones']
const EFFORTS = ['low', 'medium', 'high', 'max']
const MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power', 'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning', 'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab']
const EQUIPMENT_OPTIONS: EquipmentId[] = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'ruck_pack', 'open_space', 'rings', 'sandbag', 'bike', 'rower', 'ghd', 'box', 'resistance_band', 'medicine_ball']
const LEVELS = ['novice', 'intermediate', 'advanced', 'elite'] as const

interface Props {
  exercise: Exercise
  open: boolean
  onClose: () => void
}

export function EditExerciseDialog({ exercise, open, onClose }: Props) {
  const updateMutation = useUpdateExercise()

  const [category, setCategory] = useState(exercise.category ?? '')
  const [effort, setEffort] = useState(exercise.effort ?? '')
  const [bilateral, setBilateral] = useState(exercise.bilateral ?? true)
  const [modality, setModality] = useState<ModalityId[]>((exercise.modality ?? []) as ModalityId[])
  const [equipment, setEquipment] = useState<EquipmentId[]>((exercise.equipment ?? []) as EquipmentId[])
  const [movementPatterns, setMovementPatterns] = useState<string[]>(exercise.movement_patterns ?? [])
  const [patternInput, setPatternInput] = useState('')
  const [sets, setSets] = useState(String(exercise.typical_volume?.sets ?? ''))
  const [reps, setReps] = useState(String(exercise.typical_volume?.reps ?? ''))
  const [notes, setNotes] = useState(exercise.notes ?? '')
  // starting_load_kg per level
  const initLoads = exercise.starting_load_kg as Record<string, number | undefined> | undefined
  const [loadNovice, setLoadNovice] = useState(String(initLoads?.novice ?? ''))
  const [loadIntermediate, setLoadIntermediate] = useState(String(initLoads?.intermediate ?? ''))
  const [loadAdvanced, setLoadAdvanced] = useState(String(initLoads?.advanced ?? ''))
  const [loadElite, setLoadElite] = useState(String(initLoads?.elite ?? ''))
  const [weeklyIncrement, setWeeklyIncrement] = useState(String((exercise as Record<string, unknown>).weekly_increment_kg ?? ''))

  // Sync state when exercise prop changes (e.g. dialog re-opened for different exercise)
  useEffect(() => {
    setCategory(exercise.category ?? '')
    setEffort(exercise.effort ?? '')
    setBilateral(exercise.bilateral ?? true)
    setModality((exercise.modality ?? []) as ModalityId[])
    setEquipment((exercise.equipment ?? []) as EquipmentId[])
    setMovementPatterns(exercise.movement_patterns ?? [])
    setPatternInput('')
    setSets(String(exercise.typical_volume?.sets ?? ''))
    setReps(String(exercise.typical_volume?.reps ?? ''))
    setNotes(exercise.notes ?? '')
    const loads = exercise.starting_load_kg as Record<string, number | undefined> | undefined
    setLoadNovice(String(loads?.novice ?? ''))
    setLoadIntermediate(String(loads?.intermediate ?? ''))
    setLoadAdvanced(String(loads?.advanced ?? ''))
    setLoadElite(String(loads?.elite ?? ''))
    setWeeklyIncrement(String((exercise as Record<string, unknown>).weekly_increment_kg ?? ''))
    updateMutation.reset()
  }, [exercise.id]) // eslint-disable-line react-hooks/exhaustive-deps

  function toggleModality(m: ModalityId) {
    setModality(prev => prev.includes(m) ? prev.filter(x => x !== m) : [...prev, m])
  }

  function toggleEquipment(e: EquipmentId) {
    setEquipment(prev => prev.includes(e) ? prev.filter(x => x !== e) : [...prev, e])
  }

  function addPattern(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && patternInput.trim()) {
      e.preventDefault()
      const val = patternInput.trim()
      if (!movementPatterns.includes(val)) {
        setMovementPatterns(prev => [...prev, val])
      }
      setPatternInput('')
    }
  }

  function removePattern(p: string) {
    setMovementPatterns(prev => prev.filter(x => x !== p))
  }

  async function handleSubmit() {
    const startingLoads: Record<string, number> = {}
    if (loadNovice)       startingLoads.novice       = Number(loadNovice)
    if (loadIntermediate) startingLoads.intermediate = Number(loadIntermediate)
    if (loadAdvanced)     startingLoads.advanced     = Number(loadAdvanced)
    if (loadElite)        startingLoads.elite        = Number(loadElite)

    const payload: Partial<Exercise> & { id: string } = {
      id: exercise.id,
      category,
      effort: effort as Exercise['effort'],
      bilateral,
      modality,
      equipment,
      movement_patterns: movementPatterns,
      ...(sets && reps ? { typical_volume: { sets: Number(sets), reps: Number(reps) } } : {}),
      ...(notes ? { notes } : {}),
      ...(Object.keys(startingLoads).length ? { starting_load_kg: startingLoads } : {}),
      ...(weeklyIncrement ? { weekly_increment_kg: Number(weeklyIncrement) } : {}),
    }
    try {
      await updateMutation.mutateAsync(payload)
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose() }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Exercise — <span className="font-mono text-sm text-muted-foreground">{exercise.id}</span></DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* ID (read-only) */}
          <div>
            <Label className="text-xs mb-1 block">ID (read-only)</Label>
            <Input value={exercise.id} readOnly className="h-8 text-xs font-mono bg-muted/30" />
          </div>

          {/* Category & Effort */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Category *</Label>
              <Select value={category} onValueChange={setCategory}>
                <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Select…" /></SelectTrigger>
                <SelectContent>
                  {CATEGORIES.map(c => <SelectItem key={c} value={c} className="text-xs">{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label className="text-xs mb-1 block">Effort</Label>
              <Select value={effort} onValueChange={setEffort}>
                <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Select…" /></SelectTrigger>
                <SelectContent>
                  {EFFORTS.map(e => <SelectItem key={e} value={e} className="text-xs">{e}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Bilateral */}
          <div className="flex items-center gap-2">
            <button
              onClick={() => setBilateral(b => !b)}
              className={cn(
                'w-8 h-4 rounded-full transition-colors relative',
                bilateral ? 'bg-primary' : 'bg-muted border'
              )}
            >
              <span className={cn('absolute top-0.5 size-3 rounded-full bg-white transition-all', bilateral ? 'left-4' : 'left-0.5')} />
            </button>
            <Label className="text-xs cursor-pointer" onClick={() => setBilateral(b => !b)}>Bilateral</Label>
          </div>

          {/* Modalities */}
          <div>
            <Label className="text-xs mb-1.5 block">Modalities</Label>
            <div className="flex flex-wrap gap-1">
              {MODALITIES.map(m => (
                <button
                  key={m}
                  onClick={() => toggleModality(m)}
                  className={cn(
                    'px-2 py-0.5 rounded text-[10px] border transition-colors font-mono',
                    modality.includes(m)
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}
                >
                  {m}
                </button>
              ))}
            </div>
          </div>

          {/* Equipment */}
          <div>
            <Label className="text-xs mb-1.5 block">Equipment</Label>
            <div className="flex flex-wrap gap-1">
              {EQUIPMENT_OPTIONS.map(eq => (
                <button
                  key={eq}
                  onClick={() => toggleEquipment(eq)}
                  className={cn(
                    'px-2 py-0.5 rounded text-[10px] border transition-colors',
                    equipment.includes(eq)
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}
                >
                  {eq}
                </button>
              ))}
            </div>
          </div>

          {/* Movement patterns */}
          <div>
            <Label className="text-xs mb-1 block">Movement Patterns</Label>
            <Input
              value={patternInput}
              onChange={e => setPatternInput(e.target.value)}
              onKeyDown={addPattern}
              placeholder="Type pattern and press Enter…"
              className="h-8 text-xs"
            />
            {movementPatterns.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-1.5">
                {movementPatterns.map(p => (
                  <span key={p} className="flex items-center gap-1 px-2 py-0.5 rounded text-xs bg-muted border border-border font-mono">
                    {p}
                    <button onClick={() => removePattern(p)} className="hover:text-destructive">
                      <X className="size-2.5" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>

          {/* Typical volume */}
          <div>
            <Label className="text-xs mb-1 block">Typical Volume</Label>
            <div className="flex items-center gap-2">
              <Input value={sets} onChange={e => setSets(e.target.value)} type="number" placeholder="Sets" className="h-8 text-xs w-20" />
              <span className="text-xs text-muted-foreground">×</span>
              <Input value={reps} onChange={e => setReps(e.target.value)} type="number" placeholder="Reps" className="h-8 text-xs w-20" />
            </div>
          </div>

          {/* Starting load override (A1) */}
          <div>
            <Label className="text-xs mb-1 block">Starting Load (kg) — optional override per level</Label>
            <div className="grid grid-cols-4 gap-2">
              {([['Novice', loadNovice, setLoadNovice], ['Inter.', loadIntermediate, setLoadIntermediate], ['Advanced', loadAdvanced, setLoadAdvanced], ['Elite', loadElite, setLoadElite]] as [string, string, (v: string) => void][]).map(([label, val, setter]) => (
                <div key={label}>
                  <Label className="text-[10px] mb-0.5 block text-muted-foreground">{label}</Label>
                  <Input value={val} onChange={e => setter(e.target.value)} type="number" placeholder="kg" className="h-7 text-xs" />
                </div>
              ))}
            </div>
          </div>

          {/* Weekly increment override (A1) */}
          <div>
            <Label className="text-xs mb-1 block">Weekly Increment (kg) — optional override</Label>
            <Input value={weeklyIncrement} onChange={e => setWeeklyIncrement(e.target.value)} type="number" placeholder="e.g. 2.5" className="h-8 text-xs w-32" />
          </div>

          {/* Notes */}
          <div>
            <Label className="text-xs mb-1 block">Notes</Label>
            <textarea
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="Coaching notes, implementation details…"
              className="w-full rounded-md border bg-transparent px-3 py-2 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={3}
            />
          </div>

          {updateMutation.isError && (
            <p className="text-xs text-destructive">{(updateMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!category || updateMutation.isPending}>
            {updateMutation.isPending ? 'Saving…' : 'Save Changes'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
