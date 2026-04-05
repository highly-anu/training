import { useState } from 'react'
import { Plus } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useCreateModality, useModalities } from '@/api/modalities'
import type { ModalityId } from '@/api/types'

const RECOVERY_COSTS = ['low', 'medium', 'high'] as const
const SESSION_POSITIONS = ['standalone', 'first', 'last', 'any'] as const

function slugify(s: string) {
  return s.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '')
}

interface Props {
  open: boolean
  onClose: () => void
}

export function AddModalityDialog({ open, onClose }: Props) {
  const createMutation = useCreateModality()
  const { data: existingModalities = [] } = useModalities()
  const existingIds = existingModalities.map(m => m.id as string)

  const [name, setName] = useState('')
  const [id, setId] = useState('')
  const [idManual, setIdManual] = useState(false)
  const [description, setDescription] = useState('')
  const [recoveryCost, setRecoveryCost] = useState<'low' | 'medium' | 'high'>('medium')
  const [recoveryHoursMin, setRecoveryHoursMin] = useState('0')
  const [sessionPosition, setSessionPosition] = useState('any')
  const [incompatible, setIncompatible] = useState<string[]>([])

  function handleNameChange(v: string) {
    setName(v)
    if (!idManual) setId(slugify(v))
  }

  function handleIdChange(v: string) {
    setId(v)
    setIdManual(true)
  }

  function toggleIncompatible(mid: string) {
    setIncompatible(prev => prev.includes(mid) ? prev.filter(x => x !== mid) : [...prev, mid])
  }

  function reset() {
    setName(''); setId(''); setIdManual(false); setDescription('')
    setRecoveryCost('medium'); setRecoveryHoursMin('0')
    setSessionPosition('any'); setIncompatible([])
    createMutation.reset()
  }

  async function handleSubmit() {
    if (!id || !name) return
    const payload = {
      id,
      name,
      description,
      recovery_cost: recoveryCost,
      recovery_hours_min: Number(recoveryHoursMin) || 0,
      session_position: sessionPosition,
      incompatible_in_session_with: incompatible,
      compatible_in_session_with: [],
    }
    try {
      await createMutation.mutateAsync(payload)
      reset()
      onClose()
    } catch (_) {
      // error shown below
    }
  }

  const canSubmit = !!id && !!name && !createMutation.isPending

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) { reset(); onClose() } }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Modality</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Name & ID */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Name *</Label>
              <Input value={name} onChange={e => handleNameChange(e.target.value)} placeholder="Custom Modality" className="h-8 text-xs" />
            </div>
            <div>
              <Label className="text-xs mb-1 block">ID *</Label>
              <Input value={id} onChange={e => handleIdChange(e.target.value)} placeholder="custom_modality" className="h-8 text-xs font-mono" />
            </div>
          </div>

          {/* Description */}
          <div>
            <Label className="text-xs mb-1 block">Description</Label>
            <textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              placeholder="What this modality trains…"
              className="w-full rounded-md border bg-transparent px-3 py-2 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={2}
            />
          </div>

          {/* Recovery cost & hours */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs mb-1 block">Recovery Cost *</Label>
              <Select value={recoveryCost} onValueChange={v => setRecoveryCost(v as typeof recoveryCost)}>
                <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {RECOVERY_COSTS.map(c => <SelectItem key={c} value={c} className="text-xs">{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label className="text-xs mb-1 block">Recovery Hours Min</Label>
              <Input value={recoveryHoursMin} onChange={e => setRecoveryHoursMin(e.target.value)} type="number" placeholder="0" className="h-8 text-xs" />
            </div>
          </div>

          {/* Session position */}
          <div>
            <Label className="text-xs mb-1 block">Session Position</Label>
            <Select value={sessionPosition} onValueChange={setSessionPosition}>
              <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
              <SelectContent>
                {SESSION_POSITIONS.map(p => <SelectItem key={p} value={p} className="text-xs">{p}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {/* Incompatible with */}
          {existingIds.length > 0 && (
            <div>
              <Label className="text-xs mb-1.5 block">Incompatible In Session With</Label>
              <div className="flex flex-wrap gap-1">
                {existingIds.map(mid => (
                  <button
                    key={mid}
                    onClick={() => toggleIncompatible(mid)}
                    className={cn(
                      'px-2 py-0.5 rounded text-[10px] border transition-colors font-mono',
                      incompatible.includes(mid)
                        ? 'bg-destructive/15 border-destructive/40 text-destructive'
                        : 'border-border text-muted-foreground hover:bg-muted'
                    )}
                  >
                    {mid}
                  </button>
                ))}
              </div>
            </div>
          )}

          {createMutation.isError && (
            <p className="text-xs text-destructive">{(createMutation.error as Error).message}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => { reset(); onClose() }}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit}>
            <Plus className="size-3 mr-1" />
            {createMutation.isPending ? 'Adding…' : 'Add Modality'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
