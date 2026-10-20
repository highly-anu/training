import { useState } from 'react'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { EquipmentPicker } from '@/components/builder/EquipmentPicker'
import { InjuryPicker } from '@/components/builder/InjuryPicker'
import type { AthleteConstraints, EquipmentId, InjuryFlagId, TrainingLevel } from '@/api/types'

export type AdjustableConstraints = Pick<AthleteConstraints, 'equipment' | 'injury_flags' | 'training_level'>

interface AdjustSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  constraints: AthleteConstraints
  /** Swaps and replaced sessions on the draft, which a re-preview discards. */
  edits: number
  onApply: (patch: AdjustableConstraints) => void
  /** Days and minutes come from the weekly schedule: the builder's step 3. */
  onEditSchedule: () => void
}

/**
 * The preview's Adjust: the constraints that decide what is held back —
 * equipment, injuries and level — edited for this program and previewed
 * again. The profile is untouched until the program is started.
 */
export function AdjustSheet({ open, onOpenChange, constraints, edits, onApply, onEditSchedule }: AdjustSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        {/* Remounted on every open, so it starts from the draft's constraints. */}
        {open && <AdjustForm constraints={constraints} edits={edits} onApply={onApply} onEditSchedule={onEditSchedule} />}
      </SheetContent>
    </Sheet>
  )
}

function AdjustForm({ constraints, edits, onApply, onEditSchedule }: Omit<AdjustSheetProps, 'open' | 'onOpenChange'>) {
  const [equipment, setEquipment] = useState<EquipmentId[]>((constraints.equipment ?? []) as EquipmentId[])
  const [flags, setFlags] = useState<InjuryFlagId[]>((constraints.injury_flags ?? []) as InjuryFlagId[])
  const [level, setLevel] = useState<TrainingLevel>(constraints.training_level ?? 'intermediate')

  return (
    <>
      <SheetHeader>
        <SheetTitle>Adjust this program</SheetTitle>
        <SheetDescription>
          Change what the program is built for and preview it again. Your profile stays as it is.
        </SheetDescription>
      </SheetHeader>

      <div className="mt-4 space-y-5">
        <div className="space-y-2">
          <Label>Training level</Label>
          <Select value={level} onValueChange={(v) => setLevel(v as TrainingLevel)}>
            <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="novice">Novice</SelectItem>
              <SelectItem value="intermediate">Intermediate</SelectItem>
              <SelectItem value="advanced">Advanced</SelectItem>
              <SelectItem value="elite">Elite</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <Separator />
        <div className="space-y-2">
          <Label>Equipment</Label>
          <EquipmentPicker selected={equipment} onChange={setEquipment} />
        </div>
        <Separator />
        <div className="space-y-2">
          <Label>Injuries</Label>
          <InjuryPicker selected={flags} onChange={setFlags} />
        </div>
        <Separator />
        <p className="text-xs text-muted-foreground">
          Days and session length come from your weekly schedule.{' '}
          <button type="button" className="underline hover:text-foreground" onClick={onEditSchedule}>
            Change the schedule
          </button>
        </p>
        {edits > 0 && (
          <p className="text-xs text-amber-700 dark:text-amber-300">
            Previewing again replaces your {edits} swap{edits === 1 ? '' : 's'} on this draft.
          </p>
        )}
        <Button className="w-full" onClick={() => onApply({ equipment, injury_flags: flags, training_level: level })}>
          Update preview
        </Button>
      </div>
    </>
  )
}
