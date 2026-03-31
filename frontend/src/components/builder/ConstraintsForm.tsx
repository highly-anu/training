import { useEffect, useMemo, useRef } from 'react'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { EquipmentPicker } from './EquipmentPicker'
import { InjuryPicker } from './InjuryPicker'
import { FeasibilityPanel } from './FeasibilityPanel'
import { WeeklyScheduler } from './WeeklyScheduler'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import type { CustomInjuryFlag, EquipmentId, InjuryFlagId, TrainingLevel, FatigueState, TrainingPhase } from '@/api/types'

export function ConstraintsForm() {
  const constraints = useBuilderStore((s) => s.constraints)
  const update = useBuilderStore((s) => s.updateConstraints)
  const eventDate = useBuilderStore((s) => s.eventDate)
  const setEventDate = useBuilderStore((s) => s.setEventDate)
  const startDate = useBuilderStore((s) => s.startDate)
  const setStartDate = useBuilderStore((s) => s.setStartDate)

  // Monday of current week — default anchor and max allowed start date
  const currentMonday = useMemo(() => {
    const d = new Date()
    const day = d.getDay()
    d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day))
    return d.toISOString().split('T')[0]
  }, [])

  // Earliest allowed: 2 weeks back
  const twoWeeksAgoMonday = useMemo(() => {
    const d = new Date()
    const day = d.getDay()
    d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day) - 14)
    return d.toISOString().split('T')[0]
  }, [])
  const { equipment: profileEquipment, injuryFlags: profileInjuryFlags, trainingLevel: profileTrainingLevel, customInjuryFlags, addCustomInjuryFlag, removeCustomInjuryFlag } = useProfileStore()

  // Seed constraints from saved profile on every mount — constraints aren't persisted
  const profileSnapshot = useRef({ equipment: profileEquipment, injury_flags: profileInjuryFlags, training_level: profileTrainingLevel })
  useEffect(() => {
    update(profileSnapshot.current)
  }, [update])

  return (
    <Tabs defaultValue="schedule" className="w-full max-w-2xl">
      <TabsList className="mb-6">
        <TabsTrigger value="schedule">Schedule</TabsTrigger>
        <TabsTrigger value="equipment">Equipment</TabsTrigger>
        <TabsTrigger value="profile">Profile</TabsTrigger>
      </TabsList>

      {/* ── Tab 1: Schedule ─────────────────────────────────────────── */}
      <TabsContent value="schedule" className="space-y-6">
        <div>
          <p className="text-xs text-muted-foreground mb-4">
            Click days to activate or rest them. Set session length per day, and optionally add a short secondary session.
          </p>
          <WeeklyScheduler />
        </div>

        {/* Event / Target Date */}
        <div className="space-y-2 pt-2">
          <Label className="text-sm font-semibold">
            Event / Target Date <span className="text-muted-foreground font-normal">(optional)</span>
          </Label>
          <p className="text-xs text-muted-foreground">Auto-computes training phase and week from today</p>
          <div className="flex flex-wrap gap-1.5">
            {[
              { label: '4 wks',  weeks: 4  },
              { label: '8 wks',  weeks: 8  },
              { label: '12 wks', weeks: 12 },
              { label: '16 wks', weeks: 16 },
              { label: '6 mo',   weeks: 26 },
              { label: '1 yr',   weeks: 52 },
            ].map(({ label, weeks }) => {
              const d = new Date()
              d.setDate(d.getDate() + weeks * 7)
              const iso = d.toISOString().split('T')[0]
              const active = eventDate === iso
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => setEventDate(active ? null : iso)}
                  className={`rounded-md border px-2.5 py-1 text-xs transition-colors ${
                    active
                      ? 'border-primary bg-primary/10 text-primary font-medium'
                      : 'border-border text-muted-foreground hover:border-primary/50 hover:text-foreground'
                  }`}
                >
                  {label}
                </button>
              )
            })}
          </div>
          <input
            type="date"
            className="flex h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            value={eventDate ?? ''}
            min={new Date().toISOString().split('T')[0]}
            onChange={(e) => setEventDate(e.target.value || null)}
          />
        </div>

        {/* Program start date */}
        <div className="space-y-2 pt-2">
          <Label className="text-sm font-semibold">
            Program start <span className="text-muted-foreground font-normal">(optional)</span>
          </Label>
          <p className="text-xs text-muted-foreground">
            Default is Monday of the current week. Set to an earlier date to include past sessions in week 1.
          </p>
          <input
            type="date"
            className="flex h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            value={startDate ?? ''}
            min={twoWeeksAgoMonday}
            max={currentMonday}
            onChange={(e) => setStartDate(e.target.value || null)}
          />
        </div>

        {/* Feasibility signals */}
        <FeasibilityPanel mode="compact" />
      </TabsContent>

      {/* ── Tab 2: Equipment ────────────────────────────────────────── */}
      <TabsContent value="equipment" className="space-y-4">
        <p className="text-xs text-muted-foreground">Select a preset or build a custom list — exercises will be filtered to what you have.</p>
        <EquipmentPicker
          selected={(constraints.equipment ?? []) as EquipmentId[]}
          onChange={(eq) => update({ equipment: eq })}
        />
      </TabsContent>

      {/* ── Tab 3: Profile ──────────────────────────────────────────── */}
      <TabsContent value="profile" className="space-y-6">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <div className="space-y-2">
            <Label className="text-sm font-semibold">Training Level</Label>
            <p className="text-[11px] text-muted-foreground">Your overall experience in structured training</p>
            <Select
              value={constraints.training_level ?? 'intermediate'}
              onValueChange={(v) => update({ training_level: v as TrainingLevel })}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="novice">Novice</SelectItem>
                <SelectItem value="intermediate">Intermediate</SelectItem>
                <SelectItem value="advanced">Advanced</SelectItem>
                <SelectItem value="elite">Elite</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label className="text-sm font-semibold">Current Fatigue</Label>
            <p className="text-[11px] text-muted-foreground">How recovered do you feel right now?</p>
            <Select
              value={constraints.fatigue_state ?? 'normal'}
              onValueChange={(v) => update({ fatigue_state: v as FatigueState })}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="fresh">Fresh — well rested</SelectItem>
                <SelectItem value="normal">Normal — typical week</SelectItem>
                <SelectItem value="accumulated">Accumulated — some fatigue</SelectItem>
                <SelectItem value="overreached">Overreached — need deload</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label className="text-sm font-semibold">Training Phase</Label>
            <p className="text-[11px] text-muted-foreground">Where are you in your training cycle?</p>
            <Select
              value={constraints.training_phase ?? 'base'}
              onValueChange={(v) => update({ training_phase: v as TrainingPhase })}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="base">Base</SelectItem>
                <SelectItem value="build">Build</SelectItem>
                <SelectItem value="peak">Peak</SelectItem>
                <SelectItem value="taper">Taper</SelectItem>
                <SelectItem value="deload">Deload</SelectItem>
                <SelectItem value="maintenance">Maintenance</SelectItem>
                <SelectItem value="rehab">Rehab</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <div className="pt-2">
          <Label className="text-sm font-semibold">Injury Flags</Label>
          <p className="text-xs text-muted-foreground mt-0.5 mb-3">Check any current injuries — contraindicated exercises will be excluded</p>
          <InjuryPicker
            selected={(constraints.injury_flags ?? []) as InjuryFlagId[]}
            onChange={(flags) => update({ injury_flags: flags })}
            customInjuries={customInjuryFlags}
            onCustomInjuriesChange={(injuries: CustomInjuryFlag[]) => {
              const added = injuries.find((i) => !customInjuryFlags.some((c) => c.id === i.id))
              const removed = customInjuryFlags.find((c) => !injuries.some((i) => i.id === c.id))
              if (added) addCustomInjuryFlag(added)
              if (removed) removeCustomInjuryFlag(removed.id)
            }}
          />
        </div>
      </TabsContent>
    </Tabs>
  )
}
