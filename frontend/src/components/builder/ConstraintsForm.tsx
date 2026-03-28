import { useEffect, useRef } from 'react'
import { Label } from '@/components/ui/label'
import { Slider } from '@/components/ui/slider'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { EquipmentPicker } from './EquipmentPicker'
import { InjuryPicker } from './InjuryPicker'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import type { CustomInjuryFlag, EquipmentId, InjuryFlagId, TrainingLevel, FatigueState, TrainingPhase } from '@/api/types'

export function ConstraintsForm() {
  const constraints = useBuilderStore((s) => s.constraints)
  const update = useBuilderStore((s) => s.updateConstraints)
  const eventDate = useBuilderStore((s) => s.eventDate)
  const setEventDate = useBuilderStore((s) => s.setEventDate)
  const { equipment: profileEquipment, injuryFlags: profileInjuryFlags, trainingLevel: profileTrainingLevel, customInjuryFlags, addCustomInjuryFlag, removeCustomInjuryFlag } = useProfileStore()

  // Seed constraints from saved profile on every mount — constraints aren't persisted
  const profileSnapshot = useRef({ equipment: profileEquipment, injury_flags: profileInjuryFlags, training_level: profileTrainingLevel })
  useEffect(() => {
    update(profileSnapshot.current)
  }, [update])

  const DAYS = constraints.days_per_week ?? 4
  const TIME = constraints.session_time_minutes ?? 60

  return (
    <div className="space-y-8 max-w-2xl">
      {/* Equipment */}
      <section>
        <Label className="text-sm font-semibold">Equipment Available</Label>
        <p className="text-xs text-muted-foreground mb-3">Select a preset or use custom</p>
        <EquipmentPicker
          selected={(constraints.equipment ?? []) as EquipmentId[]}
          onChange={(eq) => update({ equipment: eq })}
        />
      </section>

      <Separator />

      {/* Schedule */}
      <section className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="space-y-3">
          <Label className="text-sm font-semibold">
            Days per Week — <span className="text-primary font-bold">{DAYS}</span>
          </Label>
          <Slider
            min={2} max={7} step={1}
            value={[DAYS]}
            onValueChange={([v]) => {
              update({ days_per_week: v, preferred_days: [] })
            }}
          />
          <div className="flex justify-between text-[10px] text-muted-foreground">
            <span>2</span><span>7</span>
          </div>

          {/* Day picker */}
          <div className="space-y-1.5 pt-1">
            <p className="text-[11px] text-muted-foreground">
              Pin days <span className="opacity-60">— click: workout · click again: rest · click again: auto</span>
            </p>
            <div className="flex gap-1.5">
              {([
                { label: 'M', day: 1 }, { label: 'T', day: 2 }, { label: 'W', day: 3 },
                { label: 'T', day: 4 }, { label: 'F', day: 5 }, { label: 'S', day: 6 },
                { label: 'S', day: 7 },
              ] as { label: string; day: number }[]).map(({ label, day }) => {
                const workout = (constraints.preferred_days ?? []).includes(day)
                const rest = (constraints.forced_rest_days ?? []).includes(day)
                const state = workout ? 'workout' : rest ? 'rest' : 'auto'
                return (
                  <button
                    key={day}
                    type="button"
                    title={state === 'auto' ? 'Auto' : state === 'workout' ? 'Workout (pinned)' : 'Rest (blocked)'}
                    onClick={() => {
                      const pinned = [...(constraints.preferred_days ?? [])]
                      const blocked = [...(constraints.forced_rest_days ?? [])]
                      if (state === 'auto') {
                        // auto → workout
                        update({ preferred_days: [...pinned, day].sort((a, b) => a - b) })
                      } else if (state === 'workout') {
                        // workout → rest
                        update({
                          preferred_days: pinned.filter((d) => d !== day),
                          forced_rest_days: [...blocked, day].sort((a, b) => a - b),
                        })
                      } else {
                        // rest → auto
                        update({ forced_rest_days: blocked.filter((d) => d !== day) })
                      }
                    }}
                    className={`h-7 w-7 rounded-md text-[11px] font-semibold transition-colors ${
                      state === 'workout'
                        ? 'bg-primary text-primary-foreground'
                        : state === 'rest'
                          ? 'bg-destructive/15 text-destructive border border-destructive/30 line-through'
                          : 'border border-border text-muted-foreground hover:border-primary/50 hover:text-foreground'
                    }`}
                  >
                    {label}
                  </button>
                )
              })}
            </div>
          </div>
        </div>

        <div className="space-y-3">
          <Label className="text-sm font-semibold">
            Session Time — <span className="text-primary font-bold">{TIME} min</span>
          </Label>
          <Slider
            min={30} max={120} step={15}
            value={[TIME]}
            onValueChange={([v]) => update({ session_time_minutes: v })}
          />
          <div className="flex justify-between text-[10px] text-muted-foreground">
            <span>30m</span><span>2h</span>
          </div>
        </div>
      </section>

      <Separator />

      {/* Level & Fatigue */}
      <section className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="space-y-2">
          <Label className="text-sm font-semibold">Training Level</Label>
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
          <Label className="text-sm font-semibold">Current Fatigue State</Label>
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
      </section>

      <Separator />

      {/* Event date */}
      <section className="space-y-2 max-w-xs">
        <Label className="text-sm font-semibold">
          Event / Target Date <span className="text-muted-foreground font-normal">(optional)</span>
        </Label>
        <p className="text-xs text-muted-foreground">Auto-computes training phase and week from today</p>

        {/* Quick shortcuts */}
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
          className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          value={eventDate ?? ''}
          min={new Date().toISOString().split('T')[0]}
          onChange={(e) => setEventDate(e.target.value || null)}
        />
      </section>

      <Separator />

      {/* Injuries */}
      <section>
        <Label className="text-sm font-semibold">Injury Flags</Label>
        <p className="text-xs text-muted-foreground mb-3">Check any current injuries — contraindicated exercises will be excluded</p>
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
      </section>
    </div>
  )
}
