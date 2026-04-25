import { useEffect, useMemo, useRef, useState } from 'react'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { FeasibilityPanel } from './FeasibilityPanel'
import { GuidedScheduler } from './GuidedScheduler'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import { useInjuryFlags } from '@/api/constraints'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { EquipmentId, InjuryFlagId, TrainingLevel, FatigueState, TrainingPhase } from '@/api/types'

const SECTION_LABEL = 'text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium'

const EQUIPMENT_CATEGORIES = [
  {
    name: 'Strength',
    color: MODALITY_COLORS.max_strength.hex,
    items: ['barbell', 'rack', 'plates'] as EquipmentId[],
  },
  {
    name: 'Power & Kettlebell',
    color: MODALITY_COLORS.power.hex,
    items: ['kettlebell', 'dumbbell'] as EquipmentId[],
  },
  {
    name: 'Bodyweight & Gymnastics',
    color: MODALITY_COLORS.relative_strength.hex,
    items: ['pull_up_bar', 'rings', 'parallettes', 'dip_bar'] as EquipmentId[],
  },
  {
    name: 'Aerobic & Conditioning',
    color: MODALITY_COLORS.aerobic_base.hex,
    items: ['rower', 'assault_bike', 'ski_erg', 'jump_rope', 'pool'] as EquipmentId[],
  },
  {
    name: 'GPP & Durability',
    color: MODALITY_COLORS.durability.hex,
    items: ['ruck_pack', 'sandbag', 'sled', 'medicine_ball', 'box'] as EquipmentId[],
  },
  {
    name: 'Mobility & Prehab',
    color: MODALITY_COLORS.rehab.hex,
    items: ['resistance_band', 'foam_roller', 'ghd'] as EquipmentId[],
  },
  {
    name: 'General',
    color: '#6366f1',
    items: ['rope', 'open_space'] as EquipmentId[],
  },
]

type Tab = 'schedule' | 'equipment' | 'profile'

const TABS: { id: Tab; label: string }[] = [
  { id: 'schedule', label: 'Schedule' },
  { id: 'equipment', label: 'Equipment' },
  { id: 'profile', label: 'Profile' },
]

export function ConstraintsForm() {
  const [activeTab, setActiveTab] = useState<Tab>('schedule')

  const constraints = useBuilderStore((s) => s.constraints)
  const update = useBuilderStore((s) => s.updateConstraints)
  const eventDate = useBuilderStore((s) => s.eventDate)
  const setEventDate = useBuilderStore((s) => s.setEventDate)
  const startDate = useBuilderStore((s) => s.startDate)
  const setStartDate = useBuilderStore((s) => s.setStartDate)

  const currentMonday = useMemo(() => {
    const d = new Date()
    const day = d.getDay()
    d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day))
    return d.toISOString().split('T')[0]
  }, [])

  const twoWeeksAgoMonday = useMemo(() => {
    const d = new Date()
    const day = d.getDay()
    d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day) - 14)
    return d.toISOString().split('T')[0]
  }, [])

  const { equipment: profileEquipment, injuryFlags: profileInjuryFlags, trainingLevel: profileTrainingLevel } = useProfileStore()
  const { data: allInjuryFlags = [] } = useInjuryFlags()

  const profileSnapshot = useRef({ equipment: profileEquipment, injury_flags: profileInjuryFlags, training_level: profileTrainingLevel })
  useEffect(() => {
    update(profileSnapshot.current)
  }, [update])

  return (
    <div className="w-full max-w-3xl mx-auto px-8 space-y-6">

      {/* Header */}
      <div className="space-y-3">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
          Athlete configuration
        </p>
        <h2 className="text-2xl font-semibold leading-snug">
          Set your constraints.
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          Training level, equipment, and injuries pre-filled from your profile. Adjust as needed for this program.
        </p>
      </div>

      {/* Pill tabs */}
      <div className="flex gap-1.5 rounded-xl border border-border/50 bg-muted/20 p-1 w-fit">
        {TABS.map(({ id, label }) => (
          <button
            key={id}
            onClick={() => setActiveTab(id)}
            className={cn(
              'rounded-lg px-4 py-1.5 text-xs font-medium transition-all',
              activeTab === id
                ? 'bg-primary/15 border border-primary/40 text-primary shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {/* ── Tab 1: Schedule ─────────────────────────────────────────── */}
      {activeTab === 'schedule' && (
        <div className="space-y-5">
          <div className="space-y-3">
            <p className={SECTION_LABEL}>Weekly layout</p>
            <p className="text-xs text-muted-foreground">
              Configure your training schedule to match the program's recommendations. Set rest, short, long, or mobility sessions for each day.
            </p>
            <GuidedScheduler />
          </div>

          {/* Program start date */}
          <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-2">
            <div>
              <p className={SECTION_LABEL}>Start anchor</p>
              <h3 className="text-sm font-semibold text-foreground mt-0.5">
                Program start <span className="text-muted-foreground font-normal text-xs">(optional)</span>
              </h3>
              <p className="text-xs text-muted-foreground mt-0.5">
                Default is Monday of the current week. Set to an earlier date to include past sessions in week 1.
              </p>
            </div>
            <input
              type="date"
              className="flex h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              value={startDate ?? ''}
              min={twoWeeksAgoMonday}
              max={currentMonday}
              onChange={(e) => setStartDate(e.target.value || null)}
            />
          </div>

          <FeasibilityPanel mode="compact" />
        </div>
      )}

      {/* ── Tab 2: Equipment ────────────────────────────────────────── */}
      {activeTab === 'equipment' && (
        <div className="space-y-6">
          <p className="text-xs text-muted-foreground">
            Select equipment you have access to. Pre-filled from your profile — adjust as needed for this program.
          </p>

          {EQUIPMENT_CATEGORIES.map((category) => {
            const selectedSet = new Set(constraints.equipment ?? [])

            return (
              <div key={category.name} className="space-y-3">
                <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
                  {category.name}
                </h3>
                <div className="grid grid-cols-2 gap-2">
                  {category.items.map((eq) => {
                    const isSelected = selectedSet.has(eq)
                    return (
                      <button
                        key={eq}
                        onClick={() => {
                          const newEquip = isSelected
                            ? (constraints.equipment ?? []).filter((e) => e !== eq)
                            : [...(constraints.equipment ?? []), eq]
                          update({ equipment: newEquip })
                        }}
                        className={cn(
                          'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-left transition-all cursor-pointer',
                          isSelected
                            ? 'border-primary/40 bg-primary/10 shadow-sm'
                            : 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20'
                        )}
                        style={{
                          borderLeftColor: isSelected ? category.color : undefined,
                          borderLeftWidth: isSelected ? 2 : 1
                        }}
                      >
                        <div className="min-w-0 flex-1">
                          <p className="text-xs font-medium leading-snug truncate">
                            {eq.replace(/_/g, ' ')}
                          </p>
                          <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                            {isSelected ? 'Available' : 'Not selected'}
                          </p>
                        </div>
                      </button>
                    )
                  })}
                </div>
              </div>
            )
          })}

          <p className="text-[10px] text-muted-foreground/30 text-center">
            {(constraints.equipment ?? []).length} items selected
          </p>
        </div>
      )}

      {/* ── Tab 3: Profile ──────────────────────────────────────────── */}
      {activeTab === 'profile' && (
        <div className="space-y-5">
          <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-4">
            <p className={SECTION_LABEL}>Athlete profile</p>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
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

              <div className={cn('space-y-2', eventDate && 'opacity-50 pointer-events-none')}>
                <Label className="text-sm font-semibold">
                  Training Phase
                  {eventDate && (
                    <span className="ml-2 text-[10px] font-normal text-muted-foreground">(auto from event date)</span>
                  )}
                </Label>
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
          </div>

          <div className="space-y-6">
            <div>
              <p className={SECTION_LABEL}>Injury flags</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Pre-filled from your profile — contraindicated exercises will be excluded.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-2">
              {allInjuryFlags.map((flag) => {
                const selectedSet = new Set(constraints.injury_flags ?? [])
                const isSelected = selectedSet.has(flag.id as InjuryFlagId)

                return (
                  <button
                    key={flag.id}
                    onClick={() => {
                      const newFlags = isSelected
                        ? (constraints.injury_flags ?? []).filter((f) => f !== flag.id)
                        : [...(constraints.injury_flags ?? []), flag.id as InjuryFlagId]
                      update({ injury_flags: newFlags })
                    }}
                    className={cn(
                      'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-left transition-all cursor-pointer',
                      isSelected
                        ? 'border-destructive/40 bg-destructive/10 shadow-sm'
                        : 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20'
                    )}
                    style={{
                      borderLeftColor: isSelected ? '#ef4444' : undefined,
                      borderLeftWidth: isSelected ? 2 : 1
                    }}
                  >
                    <div className="min-w-0 flex-1">
                      <p className="text-xs font-medium leading-snug truncate">
                        {flag.name}
                      </p>
                      <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                        {flag.excluded_movement_patterns?.length || 0} patterns excluded
                      </p>
                    </div>
                  </button>
                )
              })}
            </div>

            <p className="text-[10px] text-muted-foreground/30 text-center">
              {(constraints.injury_flags ?? []).length} active {(constraints.injury_flags ?? []).length === 1 ? 'injury' : 'injuries'}
            </p>
          </div>
        </div>
      )}
    </div>
  )
}
