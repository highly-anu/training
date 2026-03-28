import { useState } from 'react'
import { X, Plus } from 'lucide-react'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import type { CustomInjuryFlag, InjuryFlagId } from '@/api/types'

const INJURY_FLAGS: Array<{ id: InjuryFlagId; name: string; note: string }> = [
  { id: 'knee_meniscus_post_op', name: 'Knee — Meniscus Post-Op', note: 'No squatting, running, jumping' },
  { id: 'shoulder_impingement', name: 'Shoulder Impingement', note: 'No overhead pressing, pull-ups' },
  { id: 'shoulder_instability', name: 'Shoulder Instability', note: 'No overhead, no heavy pulling' },
  { id: 'lumbar_disc', name: 'Lumbar Disc', note: 'No deadlifts, no rowing, no heavy squat' },
  { id: 'ankle_sprain', name: 'Ankle Sprain', note: 'No running, no single-leg work' },
  { id: 'wrist_injury', name: 'Wrist Injury', note: 'No front rack, no push-ups' },
  { id: 'hip_flexor_strain', name: 'Hip Flexor Strain', note: 'No sprinting, no heavy squats' },
  { id: 'tennis_elbow', name: 'Tennis Elbow', note: 'No gripping under load' },
  { id: 'golfers_elbow', name: "Golfer's Elbow", note: 'No weighted pulling' },
  { id: 'neck_strain', name: 'Neck Strain', note: 'No overhead, no heavy carries' },
  { id: 'achilles_tendinopathy', name: 'Achilles Tendinopathy', note: 'No running, no jumping' },
  { id: 'patellar_tendinopathy', name: 'Patellar Tendinopathy', note: 'No squatting, no jumping' },
]

const BODY_PARTS: Array<{ id: string; label: string; patterns: string[] }> = [
  { id: 'lower_back', label: 'Lower Back',   patterns: ['hip_hinge', 'rotation', 'loaded_carry'] },
  { id: 'knee',       label: 'Knee',         patterns: ['squat', 'knee_extension', 'ballistic', 'locomotion'] },
  { id: 'shoulder',   label: 'Shoulder',     patterns: ['vertical_push', 'horizontal_push', 'ballistic', 'olympic_lift'] },
  { id: 'elbow',      label: 'Elbow',        patterns: ['horizontal_pull', 'vertical_pull', 'horizontal_push'] },
  { id: 'wrist',      label: 'Wrist / Hand', patterns: ['horizontal_push', 'vertical_push', 'olympic_lift'] },
  { id: 'ankle',      label: 'Ankle',        patterns: ['locomotion', 'ballistic'] },
  { id: 'hip_flexor', label: 'Hip Flexor',   patterns: ['hip_flexion', 'ballistic', 'locomotion'] },
  { id: 'neck',       label: 'Neck',         patterns: ['vertical_push', 'vertical_pull', 'loaded_carry', 'olympic_lift'] },
]

interface InjuryPickerProps {
  selected: InjuryFlagId[]
  onChange: (flags: InjuryFlagId[]) => void
  customInjuries?: CustomInjuryFlag[]
  onCustomInjuriesChange?: (injuries: CustomInjuryFlag[]) => void
}

export function InjuryPicker({
  selected,
  onChange,
  customInjuries,
  onCustomInjuriesChange,
}: InjuryPickerProps) {
  const [addingCustom, setAddingCustom] = useState(false)
  const [bodyPart, setBodyPart] = useState('')
  const [customName, setCustomName] = useState('')

  function toggle(id: InjuryFlagId) {
    onChange(
      selected.includes(id) ? selected.filter((f) => f !== id) : [...selected, id]
    )
  }

  function handleBodyPartChange(value: string) {
    setBodyPart(value)
    const part = BODY_PARTS.find((p) => p.id === value)
    if (part) setCustomName(`${part.label} Pain`)
  }

  function addCustom() {
    if (!bodyPart || !customName.trim() || !onCustomInjuriesChange) return
    const part = BODY_PARTS.find((p) => p.id === bodyPart)!
    const newFlag: CustomInjuryFlag = {
      id: `custom_${Date.now()}`,
      name: customName.trim(),
      body_part: bodyPart,
      excluded_movement_patterns: part.patterns,
      excluded_exercises: [],
    }
    onCustomInjuriesChange([...(customInjuries ?? []), newFlag])
    setAddingCustom(false)
    setBodyPart('')
    setCustomName('')
  }

  function removeCustom(id: string) {
    if (!onCustomInjuriesChange) return
    onCustomInjuriesChange((customInjuries ?? []).filter((f) => f.id !== id))
  }

  const selectedPatterns = bodyPart
    ? BODY_PARTS.find((p) => p.id === bodyPart)?.patterns ?? []
    : []

  return (
    <div className="space-y-4">
      {/* Preset injury flags */}
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {INJURY_FLAGS.map(({ id, name, note }) => (
          <div
            key={id}
            className="flex items-start gap-2.5 rounded-lg border border-border bg-card p-3 transition-colors hover:border-primary/40"
          >
            <Checkbox
              id={id}
              checked={selected.includes(id)}
              onCheckedChange={() => toggle(id)}
              className="mt-0.5"
            />
            <Label htmlFor={id} className="flex flex-col cursor-pointer">
              <span className="text-xs font-medium text-foreground">{name}</span>
              <span className="text-[10px] text-muted-foreground">{note}</span>
            </Label>
          </div>
        ))}
      </div>

      {/* Custom injuries section — only when onCustomInjuriesChange is wired */}
      {onCustomInjuriesChange && (
        <div className="space-y-2">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
            Custom Injuries
          </p>

          {/* Active custom injuries */}
          {(customInjuries ?? []).length > 0 && (
            <div className="space-y-1.5">
              {(customInjuries ?? []).map((flag) => (
                <div
                  key={flag.id}
                  className="flex items-center justify-between rounded-lg border bg-muted/30 px-3 py-2"
                >
                  <div>
                    <p className="text-xs font-medium">{flag.name}</p>
                    <p className="text-[10px] text-muted-foreground">
                      Excludes: {flag.excluded_movement_patterns.join(', ')}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => removeCustom(flag.id)}
                    className="ml-2 rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-colors"
                  >
                    <X className="size-3.5" />
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Add custom injury form */}
          {addingCustom ? (
            <div className="rounded-lg border bg-card p-3 space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div className="space-y-1">
                  <label className="text-[10px] text-muted-foreground">Body Part</label>
                  <Select value={bodyPart} onValueChange={handleBodyPartChange}>
                    <SelectTrigger className="h-8 text-xs">
                      <SelectValue placeholder="Select…" />
                    </SelectTrigger>
                    <SelectContent>
                      {BODY_PARTS.map((p) => (
                        <SelectItem key={p.id} value={p.id} className="text-xs">
                          {p.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <label className="text-[10px] text-muted-foreground">Name</label>
                  <input
                    type="text"
                    className="flex h-8 w-full rounded-md border border-input bg-transparent px-3 text-xs shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                    value={customName}
                    onChange={(e) => setCustomName(e.target.value)}
                    placeholder="e.g. Left Knee Pain"
                  />
                </div>
              </div>

              {selectedPatterns.length > 0 && (
                <p className="text-[10px] text-muted-foreground">
                  Will exclude: {' '}
                  {selectedPatterns.map((p) => (
                    <span key={p} className="inline-block bg-muted/60 px-1 py-0.5 rounded mr-1 font-mono">
                      {p}
                    </span>
                  ))}
                </p>
              )}

              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={addCustom}
                  disabled={!bodyPart || !customName.trim()}
                  className="h-7 rounded-md bg-primary px-3 text-[11px] font-medium text-primary-foreground disabled:opacity-40 transition-opacity"
                >
                  Add
                </button>
                <button
                  type="button"
                  onClick={() => { setAddingCustom(false); setBodyPart(''); setCustomName('') }}
                  className="h-7 rounded-md border px-3 text-[11px] font-medium text-muted-foreground hover:text-foreground transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setAddingCustom(true)}
              className="flex items-center gap-1.5 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            >
              <Plus className="size-3.5" />
              Add Custom Injury
            </button>
          )}
        </div>
      )}
    </div>
  )
}
