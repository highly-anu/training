import { useState } from 'react'
import { X, Plus } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useCreateExercise } from '@/api/exercises'
import type { Exercise, ModalityId, EquipmentId, InjuryFlagId } from '@/api/types'

const CATEGORIES = ['barbell', 'kettlebell', 'bodyweight', 'aerobic', 'carries', 'sandbag', 'mobility', 'skill', 'rehab', 'gym_jones']
const EFFORTS = ['low', 'medium', 'high', 'max']
const MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power', 'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning', 'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab']
const EQUIPMENT_OPTIONS: EquipmentId[] = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'ruck_pack', 'open_space', 'rings', 'sandbag', 'bike', 'rower', 'ghd', 'box', 'resistance_band', 'medicine_ball']
const INJURY_FLAGS: InjuryFlagId[] = ['knee_meniscus_post_op', 'shoulder_impingement', 'shoulder_instability', 'lumbar_disc', 'hip_flexor_strain', 'ankle_sprain', 'tennis_elbow', 'golfers_elbow', 'neck_strain', 'achilles_tendinopathy', 'patellar_tendinopathy']

function slugify(s: string) {
  return s.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '')
}

interface Props {
  open: boolean
  onClose: () => void
}

export function AddExerciseDialog({ open, onClose }: Props) {
  const createMutation = useCreateExercise()

  const [name, setName] = useState('')
  const [id, setId] = useState('')
  const [idManual, setIdManual] = useState(false)
  const [category, setCategory] = useState('')
  const [effort, setEffort] = useState('')
  const [bilateral, setBilateral] = useState(true)
  const [modality, setModality] = useState<ModalityId[]>([])
  const [equipment, setEquipment] = useState<EquipmentId[]>([])
  const [movementPatterns, setMovementPatterns] = useState<string[]>([])
  const [patternInput, setPatternInput] = useState('')
  const [sets, setSets] = useState('')
  const [reps, setReps] = useState('')
  const [notes, setNotes] = useState('')

  function handleNameChange(v: string) {
    setName(v)
    if (!idManual) setId(slugify(v))
  }

  function handleIdChange(v: string) {
    setId(v)
    setIdManual(true)
  }

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

  function reset() {
    setName(''); setId(''); setIdManual(false); setCategory(''); setEffort('')
    setBilateral(true); setModality([]); setEquipment([]); setMovementPatterns([])
    setPatternInput(''); setSets(''); setReps(''); setNotes('')
    createMutation.reset()
  }

  async function handleSubmit() {
    if (!id || !name || !category) return
    const exercise: Partial<Exercise> = {
      id,
      name,
      category,
      effort: (effort || 'medium') as Exercise['effort'],
      bilateral,
      modality,
      equipment,
      movement_patterns: movementPatterns,
      progressions: {},
      requires: [],
      unlocks: [],
      contraindicated_with: [] as InjuryFlagId[],
      ...(sets && reps ? { typical_volume: { sets: Number(sets), reps: Number(reps) } } : {}),
      ...(notes ? { notes } : {}),
    }
    try {
      await createMutation.mutateAsync(exercise)
      reset()
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!id && !!name && !!category && !createMutation.isPending

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) { reset(); onClose() } }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Exercise</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Name & ID */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Name *</Label>
              <Input value={name} onChange={e => handleNameChange(e.target.value)} placeholder="Back Squat" className="h-8 text-xs" />
            </div>
            <div>
              <Label className="text-xs mb-1 block">ID *</Label>
              <Input value={id} onChange={e => handleIdChange(e.target.value)} placeholder="back_squat" className="h-8 text-xs font-mono" />
            </div>
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

          {createMutation.isError && (
            <p className="text-xs text-destructive">{(createMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => { reset(); onClose() }}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit}>
            <Plus className="size-3 mr-1" />
            {createMutation.isPending ? 'Adding…' : 'Add Exercise'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
