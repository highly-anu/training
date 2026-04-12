import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { ArrowLeft, BookOpen, Compass, Dumbbell, Layers, Search, X, Zap } from 'lucide-react'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PrereqChain } from '@/components/exercises/PrereqChain'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useModalities } from '@/api/modalities'
import { useArchetypes } from '@/api/archetypes'
import { useExercises } from '@/api/exercises'
import { useDebounce } from '@/hooks/useDebounce'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import { PhilosophyExplorerPanel, ArchetypeCard } from '@/components/devlab/PhilosophyExplorerPanel'
import { HeatmapPanel } from '@/components/devlab/heatmap/HeatmapPanel'
import { SimilarItems } from '@/components/shared/SimilarItems'
import { useSimilarity } from '@/api/similarity'
import type { Philosophy, Modality, Archetype, ModalityId, Exercise } from '@/api/types'

// ─── Intensity zone definitions (HR % thresholds) ────────────────────────────

const HR_ZONES = [
  { id: 'z1', label: 'Z1', min: 55, max: 65 },
  { id: 'z2', label: 'Z2', min: 65, max: 75 },
  { id: 'z3', label: 'Z3', min: 75, max: 85 },
  { id: 'z4', label: 'Z4', min: 85, max: 92 },
  { id: 'z5', label: 'Z5', min: 92, max: 100 },
]

// ─── Helpers ─────────────────────────────────────────────────────────────────

function prettify(id: string) {
  return id.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function RecoveryCostBadge({ cost }: { cost: 'low' | 'medium' | 'high' }) {
  const styles = {
    low: 'bg-emerald-500/15 text-emerald-400',
    medium: 'bg-amber-500/15 text-amber-400',
    high: 'bg-red-500/15 text-red-400',
  }
  return (
    <span className={cn('inline-block px-1.5 py-0.5 rounded text-[10px] font-medium', styles[cost])}>
      {cost} recovery
    </span>
  )
}

// ─── Topic Selector ───────────────────────────────────────────────────────────

type Topic = 'philosophies' | 'modalities' | 'exercises' | 'archetypes'

interface TopicTab {
  id: Topic
  label: string
  Icon: React.ElementType
}

const TOPICS: TopicTab[] = [
  { id: 'philosophies', label: 'Philosophies', Icon: BookOpen },
  { id: 'modalities',   label: 'Modalities',   Icon: Zap },
  { id: 'archetypes',   label: 'Archetypes',   Icon: Layers },
  { id: 'exercises',    label: 'Exercises',     Icon: Dumbbell },
]

// ─── Archetype category colors ────────────────────────────────────────────────

const ARCH_CAT_COLORS: Record<string, string> = {
  strength:       '#ef4444',
  conditioning:   '#f97316',
  kettlebell:     '#eab308',
  gpp_durability: '#22c55e',
  movement_skill: '#3b82f6',
}

function TopicSelector({
  active,
  onChange,
}: {
  active: Topic
  onChange: (t: Topic) => void
}) {
  return (
    <div className="flex items-center gap-1">
      {TOPICS.map((tab) => {
        const isActive = tab.id === active
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1 text-xs rounded border transition-colors',
              isActive
                ? 'bg-primary/15 border-primary/40 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted',
            )}
          >
            <tab.Icon className="size-3 shrink-0" />
            {tab.label}
          </button>
        )
      })}
    </div>
  )
}

// ─── Philosophy card ──────────────────────────────────────────────────────────

// ─── Philosophy overview (landing) ───────────────────────────────────────────

function PhilosophyOverview({ philosophies, frameworks, onSelect }: {
  philosophies: Philosophy[]
  frameworks: { source_philosophy?: string; sessions_per_week?: Record<string, number> }[]
  onSelect: (p: Philosophy) => void
}) {
  const philSummaries = useMemo(() =>
    philosophies.map(p => ({
      p,
      fwCount: frameworks.filter(fw => fw.source_philosophy === p.id).length,
      color: MODALITY_COLORS[p.bias[0] as ModalityId]?.hex ?? '#6366f1',
    })),
    [philosophies, frameworks]
  )

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {philosophies.length} training philosophies.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            From barbell minimalism to movement generalism — each philosophy encodes a distinct theory of how to stress, recover, and progress.
            Select one to explore its frameworks, archetypes, and exercise vocabulary.
          </p>
        </div>

        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            {philSummaries.map(({ p, fwCount, color }) => (
              <button
                key={p.id}
                type="button"
                onClick={() => onSelect(p)}
                className="flex items-start gap-2.5 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 text-left
                           transition-all hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20 group cursor-pointer"
                style={{ borderLeftColor: color, borderLeftWidth: 2 }}
              >
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-medium leading-snug truncate group-hover:text-primary transition-colors">{p.name}</p>
                  <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                    {fwCount} framework{fwCount !== 1 ? 's' : ''} · {p.bias.length} bias{p.bias.length !== 1 ? 'es' : ''}
                  </p>
                </div>
              </button>
            ))}
          </div>
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select a philosophy to explore its full structure
        </p>
      </div>
    </div>
  )
}

// ─── Modality overview (nothing selected) ────────────────────────────────────

function ModalityOverview({
  modalities,
  onSelect,
}: {
  modalities: Modality[]
  onSelect: (m: Modality) => void
}) {
  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-8">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {modalities.length} training modalities.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Modalities define how the body is loaded — the what of each training session. Select any tile to explore its structure, intensity zones, compatibility, and featured philosophies.
          </p>
        </div>

        <div className="grid grid-cols-3 gap-2">
          {modalities.map((mod) => {
            const color = MODALITY_COLORS[mod.id]
            const hex = color?.hex ?? '#6366f1'
            return (
              <button
                key={mod.id}
                type="button"
                onClick={() => onSelect(mod)}
                className="text-left rounded-lg border border-border/40 bg-card/40 overflow-hidden
                           transition-all hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20 group cursor-pointer"
              >
                <div className="h-1 w-full" style={{ backgroundColor: hex, opacity: 0.7 }} />
                <div className="px-3 py-2.5 space-y-1.5">
                  <p className="text-[11px] font-semibold leading-snug transition-colors group-hover:text-primary" style={{ color: hex }}>{mod.name}</p>
                  <RecoveryCostBadge cost={mod.recovery_cost} />
                  <p className="text-[10px] text-muted-foreground leading-relaxed line-clamp-2">
                    {mod.description}
                  </p>
                </div>
              </button>
            )
          })}
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select a modality to explore its full structure
        </p>
      </div>
    </div>
  )
}

// ─── Modality signature — intensity strip + volume / session range bars ────────

function ModalitySignature({ mod, allArchetypes }: { mod: Modality; allArchetypes: Archetype[] }) {
  const hex = MODALITY_COLORS[mod.id]?.hex ?? '#6366f1'

  // Which HR zones are active for this modality
  const activeZones = useMemo(() => {
    const zones = mod.intensity_zones ?? []
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hasHrData = zones.some((z: any) => z.hr_pct_min != null)
    const active = new Set<string>()
    if (hasHrData) {
      for (const z of zones) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const zz = z as any
        if (zz.hr_pct_min == null) continue
        for (const def of HR_ZONES) {
          if (zz.hr_pct_min < def.max && zz.hr_pct_max > def.min) active.add(def.id)
        }
      }
    } else {
      // Infer from recovery cost when no HR data available
      if (mod.recovery_cost === 'low')    { active.add('z1'); active.add('z2') }
      else if (mod.recovery_cost === 'medium') { active.add('z2'); active.add('z3') }
      else                                { active.add('z4'); active.add('z5') }
    }
    return active
  }, [mod])

  const recoveryLevel = { low: 1, medium: 2, high: 3 }[mod.recovery_cost] ?? 1
  const recoveryColor = { low: '#10b981', medium: '#f59e0b', high: '#ef4444' }[mod.recovery_cost]

  const VOL_MAX = 600
  const volMinPct = (mod.min_weekly_minutes / VOL_MAX) * 100
  const volRangePct = ((mod.max_weekly_minutes - mod.min_weekly_minutes) / VOL_MAX) * 100

  const SESS_MAX = 180
  const session = mod.typical_session_minutes
  const sessMinPct = session ? (session.min / SESS_MAX) * 100 : 0
  const sessRangePct = session ? Math.min(((session.max - session.min) / SESS_MAX) * 100, 100 - sessMinPct) : 0

  const archetypeCount = allArchetypes.filter(a => a.modality === mod.id).length

  return (
    <div className="flex flex-col gap-4">

      {/* Header: label + recovery meter */}
      <div className="flex items-center justify-between">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Profile</p>
        <div className="flex items-center gap-1.5">
          <span className="text-[9px] font-mono text-muted-foreground/35 uppercase tracking-wider">recovery</span>
          <div className="flex gap-0.5">
            {[1, 2, 3].map(n => (
              <div key={n} className="size-2.5 rounded-full transition-all"
                style={{
                  backgroundColor: n <= recoveryLevel ? recoveryColor : 'transparent',
                  border: `1px solid ${n <= recoveryLevel ? recoveryColor : '#334155'}`,
                  opacity: n <= recoveryLevel ? (n === recoveryLevel ? 1 : 0.6) : 0.25,
                }} />
            ))}
          </div>
        </div>
      </div>

      {/* Intensity zone strip */}
      <div className="space-y-1.5">
        <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Intensity</p>
        <div className="flex gap-0.5">
          {HR_ZONES.map(def => {
            const active = activeZones.has(def.id)
            return (
              <div key={def.id} className="flex-1 flex items-center justify-center rounded py-1.5 transition-all"
                style={{
                  backgroundColor: active ? `${hex}cc` : 'transparent',
                  border: `1px solid ${active ? hex : '#1e293b'}`,
                }}>
                <span className="text-[9px] font-mono font-medium"
                  style={{ color: active ? '#fff' : '#334155' }}>
                  {def.label}
                </span>
              </div>
            )
          })}
        </div>
        <div className="flex justify-between px-0.5">
          <span className="text-[8px] font-mono text-muted-foreground/25">low</span>
          <span className="text-[8px] font-mono text-muted-foreground/25">high</span>
        </div>
      </div>

      {/* Weekly volume range */}
      <div className="space-y-1.5">
        <div className="flex items-baseline justify-between">
          <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Volume / week</p>
          <span className="text-[9px] font-mono tabular-nums text-muted-foreground/50">
            {mod.min_weekly_minutes}–{mod.max_weekly_minutes} min
          </span>
        </div>
        <div className="relative h-2 rounded-full bg-muted/20 overflow-hidden">
          <div className="absolute h-full rounded-full"
            style={{ left: `${volMinPct}%`, width: `${Math.max(volRangePct, 4)}%`, backgroundColor: hex, opacity: 0.65 }} />
        </div>
        <div className="flex justify-between px-0.5">
          <span className="text-[8px] font-mono text-muted-foreground/25">0</span>
          <span className="text-[8px] font-mono text-muted-foreground/25">600 min/wk</span>
        </div>
      </div>

      {/* Session duration range */}
      {session && (
        <div className="space-y-1.5">
          <div className="flex items-baseline justify-between">
            <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Session</p>
            <span className="text-[9px] font-mono tabular-nums text-muted-foreground/50">
              {session.min}–{session.max} min
            </span>
          </div>
          <div className="relative h-2 rounded-full bg-muted/20 overflow-hidden">
            <div className="absolute h-full rounded-full"
              style={{ left: `${sessMinPct}%`, width: `${Math.max(sessRangePct, 4)}%`, backgroundColor: hex, opacity: 0.65 }} />
          </div>
          <div className="flex justify-between px-0.5">
            <span className="text-[8px] font-mono text-muted-foreground/25">0</span>
            <span className="text-[8px] font-mono text-muted-foreground/25">180 min</span>
          </div>
        </div>
      )}

      {/* Footer: session position + archetype count */}
      <div className="flex items-center justify-between pt-0.5">
        <div className="flex gap-1">
          {(['first', 'standalone', 'any'] as const).map(pos => (
            <span key={pos}
              className="px-1.5 py-0.5 rounded text-[9px] font-mono transition-colors"
              style={{
                backgroundColor: mod.session_position === pos ? `${hex}20` : 'transparent',
                color: mod.session_position === pos ? hex : '#334155',
                border: `1px solid ${mod.session_position === pos ? `${hex}50` : '#1e293b'}`,
              }}>
              {pos}
            </span>
          ))}
        </div>
        {archetypeCount > 0 && (
          <span className="text-[9px] font-mono text-muted-foreground/35">
            {archetypeCount} archetype{archetypeCount !== 1 ? 's' : ''}
          </span>
        )}
      </div>

    </div>
  )
}

// ─── Modality detail ──────────────────────────────────────────────────────────

function ModalityDetail({
  mod,
  modalities,
  philosophies,
  allArchetypes,
  onSelectMod,
  onBack,
}: {
  mod: Modality
  modalities: Modality[]
  philosophies: Philosophy[]
  allArchetypes: Archetype[]
  onSelectMod: (m: Modality) => void
  onBack: () => void
}) {
  const color = MODALITY_COLORS[mod.id]
  const hex = color?.hex ?? '#6366f1'

  const featuredIn = useMemo(
    () => philosophies.filter(p => p.bias.includes(mod.id)),
    [mod.id, philosophies]
  )

  return (
    <div className="h-full overflow-y-auto">
      <div className="px-4 py-4 space-y-4">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground/60 hover:text-foreground transition-colors"
        >
          <ArrowLeft className="size-3" />
          All modalities
        </button>

        {/* Header card — two-column layout matching philosophy explorer */}
        <div
          className="rounded-lg border p-4"
          style={{ borderColor: `${hex}40`, backgroundColor: `${hex}05` }}
        >
          <div className="flex gap-0 items-start">
            {/* Left: identity + stats */}
            <div className="flex-1 min-w-0 pr-5 space-y-3">
              <div className="space-y-1">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Modality</p>
                <h2 className="text-base font-semibold" style={{ color: hex }}>{mod.name}</h2>
              </div>

              <div className="flex flex-wrap gap-1.5">
                <RecoveryCostBadge cost={mod.recovery_cost} />
                <span className="inline-block px-1.5 py-0.5 rounded text-[10px] font-medium bg-muted/50 text-muted-foreground">
                  {prettify(mod.progression_model)}
                </span>
              </div>

              <p className="text-[11px] text-muted-foreground leading-relaxed">{mod.description}</p>

              <div className="grid grid-cols-2 gap-2 pt-1">
                <StatCell label="Session position" value={prettify(mod.session_position)} />
                {mod.typical_session_minutes && (
                  <StatCell label="Typical session" value={`${mod.typical_session_minutes.min}–${mod.typical_session_minutes.max} min`} />
                )}
                <StatCell label="Weekly volume" value={`${mod.min_weekly_minutes}–${mod.max_weekly_minutes} min`} />
                <StatCell label="Recovery minimum" value={`${mod.recovery_hours_min}h`} />
              </div>
            </div>

            {/* Right: modality signature */}
            <div className="shrink-0 pl-5 border-l" style={{ borderColor: `${hex}20`, width: '36%', minWidth: 240 }}>
              <ModalitySignature mod={mod} allArchetypes={allArchetypes} />
            </div>
          </div>
        </div>

        {/* Intensity zones */}
        {mod.intensity_zones && mod.intensity_zones.length > 0 && (
          <Section label="Intensity zones">
            <div className="space-y-1.5">
              {mod.intensity_zones.map((zone, i) => (
                <div key={i} className="flex items-start gap-3 rounded-md border border-border/30 bg-card/30 px-3 py-2">
                  <div className="mt-0.5 size-1.5 rounded-full shrink-0" style={{ backgroundColor: hex, opacity: 0.7 }} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-[11px] font-medium text-foreground">{zone.label}</span>
                      {zone.hr_pct_range && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted/50 text-muted-foreground font-mono">
                          {zone.hr_pct_range[0]}–{zone.hr_pct_range[1]}% HR
                        </span>
                      )}
                    </div>
                    {zone.description && (
                      <p className="text-[10px] text-muted-foreground mt-0.5 leading-relaxed">{zone.description}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </Section>
        )}

        {/* Compatibility */}
        {(mod.compatible_in_session_with.length > 0 || mod.incompatible_in_session_with.length > 0) && (
          <Section label="Compatibility">
            <div className="grid grid-cols-2 gap-3">
              {mod.compatible_in_session_with.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-[10px] text-emerald-400/70 font-medium">Pairs well with</p>
                  <div className="flex flex-wrap gap-1">
                    {mod.compatible_in_session_with.map((id) => {
                      const c = MODALITY_COLORS[id]
                      return (
                        <span key={id} className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] bg-emerald-500/10 text-emerald-300 border border-emerald-500/20">
                          <span className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: c?.hex ?? '#10b981' }} />
                          {c?.label ?? prettify(id)}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )}
              {mod.incompatible_in_session_with.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-[10px] text-red-400/70 font-medium">Avoid combining</p>
                  <div className="flex flex-wrap gap-1">
                    {mod.incompatible_in_session_with.map((id) => {
                      const c = MODALITY_COLORS[id]
                      return (
                        <span key={id} className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] bg-red-500/10 text-red-300 border border-red-500/20">
                          <span className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: c?.hex ?? '#ef4444' }} />
                          {c?.label ?? prettify(id)}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>
          </Section>
        )}

        {/* Featured in */}
        {featuredIn.length > 0 && (
          <Section label="Featured in">
            <div className="flex flex-wrap gap-1.5">
              {featuredIn.map((p) => {
                const phColor = MODALITY_COLORS[p.bias[0] as ModalityId]?.hex ?? '#6366f1'
                return (
                  <span key={p.id}
                    className="inline-block px-2 py-0.5 rounded-full text-[10px] border border-border/40 bg-card/40 text-muted-foreground"
                    style={{ borderLeftColor: phColor, borderLeftWidth: 2 }}>
                    {p.name}
                  </span>
                )
              })}
            </div>
          </Section>
        )}

        {/* Sources */}
        {mod.sources && mod.sources.length > 0 && (
          <Section label="Sources">
            <ul className="space-y-0.5">
              {mod.sources.map((s, i) => (
                <li key={i} className="text-[10px] text-muted-foreground/60 italic">{s}</li>
              ))}
            </ul>
          </Section>
        )}

        {/* Notes */}
        {mod.notes && (
          <Section label="Notes">
            <p className="text-[11px] text-muted-foreground leading-relaxed">{mod.notes}</p>
          </Section>
        )}

        {/* Similar modalities */}
        <SimilarItems
          category="modalities"
          id={mod.id}
          getLabel={(id) => modalities.find(m => m.id === id)?.name ?? prettify(id)}
          onSelect={(id) => {
            const m = modalities.find(m => m.id === id)
            if (m) onSelectMod(m)
          }}
          accentHex={hex}
        />
      </div>
    </div>
  )
}

// ─── Exercise components ──────────────────────────────────────────────────────

const EX_CATEGORY_COLORS: Record<string, string> = {
  barbell:     '#ef4444',
  kettlebell:  '#f97316',
  bodyweight:  '#10b981',
  aerobic:     '#0ea5e9',
  loaded_carry:'#f59e0b',
  sandbag:     '#ca8a04',
  mobility:    '#14b8a6',
  skill:       '#8b5cf6',
  rehab:       '#84cc16',
  gym_jones:   '#ec4899',
}

const EX_EFFORT_COLORS: Record<string, string> = {
  low: '#10b981', medium: '#f59e0b', high: '#f97316', max: '#ef4444',
}

const EX_CATEGORIES = [
  { id: '', label: 'All' },
  { id: 'barbell', label: 'Barbell' },
  { id: 'kettlebell', label: 'KB' },
  { id: 'bodyweight', label: 'BW' },
  { id: 'aerobic', label: 'Aerobic' },
  { id: 'loaded_carry', label: 'Carries' },
  { id: 'sandbag', label: 'Sandbag' },
  { id: 'mobility', label: 'Mobility' },
  { id: 'skill', label: 'Skill' },
  { id: 'rehab', label: 'Rehab' },
]

function ExerciseLanding({ allExercises, onSelect }: { allExercises: Exercise[]; onSelect: (e: Exercise) => void }) {
  const [search, setSearch] = useState('')
  const [activeCategories, setActiveCategories] = useState<Set<string>>(new Set())
  const debouncedSearch = useDebounce(search, 250)
  const { data: searched = [] } = useExercises(debouncedSearch ? { search: debouncedSearch } : undefined)
  const searchBase = debouncedSearch ? searched : allExercises
  const displayed = activeCategories.size > 0
    ? searchBase.filter(e => activeCategories.has(e.category))
    : searchBase

  const byCat = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const e of allExercises) counts[e.category] = (counts[e.category] ?? 0) + 1
    return Object.entries(counts).sort((a, b) => b[1] - a[1])
  }, [allExercises])

  function toggleCat(cat: string) {
    setActiveCategories(prev => {
      const next = new Set(prev)
      next.has(cat) ? next.delete(cat) : next.add(cat)
      return next
    })
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-3xl mx-auto px-8 py-12 space-y-8">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {allExercises.length} exercises.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            The full exercise vocabulary — barbell, kettlebell, bodyweight, aerobic, carries, mobility, skill, and more.
            Select any to explore its movement patterns, progressions, and similar alternatives.
          </p>
        </div>

        {/* Category chips — additive filter */}
        <div className="space-y-1.5">
          <div className="flex flex-wrap gap-2">
            {byCat.map(([cat, count]) => {
              const color = EX_CATEGORY_COLORS[cat] ?? '#6366f1'
              const active = activeCategories.has(cat)
              return (
                <button
                  key={cat}
                  onClick={() => toggleCat(cat)}
                  className="flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-mono transition-all"
                  style={active
                    ? { backgroundColor: `${color}30`, color, border: `1px solid ${color}60` }
                    : { backgroundColor: `${color}15`, color, border: `1px solid ${color}30`, opacity: 0.7 }
                  }
                >
                  <div className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
                  {cat.replace(/_/g, ' ')} · {count}
                </button>
              )
            })}
          </div>
          {activeCategories.size > 0 && (
            <button
              onClick={() => setActiveCategories(new Set())}
              className="text-[10px] text-muted-foreground/50 hover:text-foreground transition-colors"
            >
              Clear filter
            </button>
          )}
        </div>

        {/* Search */}
        <div className="relative max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3 text-muted-foreground" />
          <input
            placeholder="Search exercises…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-md border border-border bg-background pl-7 pr-7 h-8 text-xs focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
          {search && (
            <button onClick={() => setSearch('')}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
              <X className="size-3" />
            </button>
          )}
        </div>

        {/* Count */}
        {(debouncedSearch || activeCategories.size > 0) && (
          <p className="text-[10px] text-muted-foreground/50 font-mono -mt-4">{displayed.length} results</p>
        )}

        {/* Exercise list */}
        <div className="space-y-1">
          {displayed.map((ex) => {
            const color = EX_CATEGORY_COLORS[ex.category] ?? '#6366f1'
            return (
              <button
                key={ex.id}
                type="button"
                onClick={() => onSelect(ex)}
                className="w-full text-left rounded-lg border border-border/30 bg-card/40 px-3 py-2.5
                           transition-all hover:border-primary/40 hover:shadow-sm hover:-translate-y-px hover:bg-muted/20 group cursor-pointer"
                style={{ borderLeftColor: color, borderLeftWidth: 2 }}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="text-[11px] font-medium flex-1 truncate group-hover:text-primary transition-colors">
                    {ex.name}
                  </span>
                  <div className="flex items-center gap-2 shrink-0 text-[10px] text-muted-foreground/60 font-mono">
                    {ex.movement_patterns.slice(0, 2).map(p => (
                      <span key={p}>{p.replace(/_/g, ' ')}</span>
                    ))}
                    <span className={cn(EX_EFFORT_COLORS[ex.effort])}>{ex.effort}</span>
                  </div>
                </div>
              </button>
            )
          })}
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select an exercise to explore its structure
        </p>
      </div>
    </div>
  )
}

function ExercisePanel({
  exercise,
  allExercises,
  onNavigate,
  onBack,
}: {
  exercise: Exercise
  allExercises: Exercise[]
  onNavigate: (id: string) => void
  onBack: () => void
}) {
  return (
    <div className="h-full overflow-y-auto">
      <div className="px-6 py-5 space-y-5">

        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground/60 hover:text-foreground transition-colors"
        >
          <ArrowLeft className="size-3" />
          All exercises
        </button>

        {/* Header */}
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-1">Exercise</p>
          <h2 className="text-base font-semibold"
            style={{ color: EX_CATEGORY_COLORS[exercise.category] ?? undefined }}>
            {exercise.name}
          </h2>
          <div className="flex flex-wrap gap-1 mt-2">
            {exercise.modality.map((m) => <ModalityBadge key={m} modality={m} />)}
          </div>
        </div>

        {/* Meta grid */}
        <div className="grid grid-cols-2 gap-2">
          {[
            { label: 'Category', value: exercise.category.replace(/_/g, ' ') },
            { label: 'Effort',   value: exercise.effort },
            { label: 'Bilateral', value: exercise.bilateral ? 'Yes' : 'No' },
            ...(exercise.typical_volume
              ? [{ label: 'Typical', value: `${exercise.typical_volume.sets}×${exercise.typical_volume.reps}` }]
              : []),
          ].map(({ label, value }) => (
            <div key={label} className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
              <p className="text-[11px] font-medium capitalize">{value}</p>
            </div>
          ))}
        </div>

        {/* Movement patterns */}
        {exercise.movement_patterns.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Patterns</p>
            <div className="flex flex-wrap gap-1">
              {exercise.movement_patterns.map((p) => (
                <span key={p} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground capitalize">
                  {p.replace(/_/g, ' ')}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Progressions */}
        {Object.keys(exercise.progressions).length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Progressions</p>
            <div className="space-y-1 text-xs text-muted-foreground">
              {exercise.progressions.load && <p><span className="text-foreground font-medium">Load:</span> {exercise.progressions.load}</p>}
              {exercise.progressions.volume && <p><span className="text-foreground font-medium">Volume:</span> {exercise.progressions.volume}</p>}
              {exercise.progressions.complexity && <p><span className="text-foreground font-medium">Complexity:</span> {exercise.progressions.complexity}</p>}
            </div>
          </div>
        )}

        {/* Scale down */}
        {exercise.scaling_down && exercise.scaling_down.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Scale Down To</p>
            <div className="flex flex-wrap gap-1">
              {exercise.scaling_down.map((s) => (
                <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">
                  {s.replace(/_/g, ' ')}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Notes */}
        {exercise.notes && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Coaching Notes</p>
            <p className="text-xs text-muted-foreground leading-relaxed">{exercise.notes}</p>
          </div>
        )}

        {/* Prereq chain */}
        <div className="space-y-2 border-t border-border/30 pt-4">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Progression Chain</p>
          <PrereqChain
            exercise={exercise}
            allExercises={allExercises}
            onSelect={(id) => onNavigate(id)}
          />
        </div>

        {/* Sources */}
        {exercise.sources.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Sources</p>
            <div className="flex flex-wrap gap-1">
              {exercise.sources.map((s) => (
                <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">{s}</span>
              ))}
            </div>
          </div>
        )}

        {/* Similar exercises */}
        <SimilarItems
          category="exercises"
          id={exercise.id}
          getLabel={(id) => allExercises.find(e => e.id === id)?.name ?? id.replace(/_/g, ' ')}
          onSelect={(id) => onNavigate(id)}
          accentHex={EX_CATEGORY_COLORS[exercise.category]}
        />

      </div>
    </div>
  )
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">{label}</p>
      {children}
    </div>
  )
}

function StatCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
      <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
      <p className="text-[11px] font-medium text-foreground">{value}</p>
    </div>
  )
}

// ─── Archetype landing card ───────────────────────────────────────────────────

function ArchetypeLandingCard({ archetype, onSelect }: { archetype: Archetype; onSelect: () => void }) {
  const catColor = ARCH_CAT_COLORS[archetype.category] ?? '#94a3b8'
  const modColor = MODALITY_COLORS[archetype.modality as ModalityId]

  return (
    <button
      type="button"
      onClick={onSelect}
      className="w-full text-left rounded-xl border bg-card overflow-hidden transition-all cursor-pointer group
                 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20"
      style={{ borderLeftColor: catColor, borderLeftWidth: 3 }}
    >
      <div className="px-3 py-2.5 space-y-1.5">
        <p className="text-xs font-semibold leading-snug group-hover:text-primary transition-colors">
          {archetype.name}
        </p>
        <div className="flex flex-wrap gap-1">
          <span
            className="text-[9px] px-1.5 py-0.5 rounded font-mono"
            style={{ color: catColor, backgroundColor: `${catColor}15`, border: `1px solid ${catColor}30` }}
          >
            {archetype.category.replace(/_/g, ' ')}
          </span>
          {modColor && (
            <span
              className="text-[9px] px-1.5 py-0.5 rounded font-mono"
              style={{ color: modColor.hex, backgroundColor: `${modColor.hex}15`, border: `1px solid ${modColor.hex}30` }}
            >
              {modColor.label}
            </span>
          )}
        </div>
        <div className="flex items-center gap-3 text-[10px] text-muted-foreground/70">
          <span className="font-mono">{archetype.duration_estimate_minutes}min</span>
          <span>{(archetype.slots ?? []).length} slots</span>
          {(archetype.required_equipment ?? []).filter(e => e !== 'open_space').slice(0, 2).map(e => (
            <span key={e} className="font-mono truncate">{e.replace(/_/g, ' ')}</span>
          ))}
        </div>
      </div>
    </button>
  )
}

// ─── Archetype landing page ───────────────────────────────────────────────────

function ArchetypeLanding({ archetypes, onSelect }: {
  archetypes: Archetype[]
  onSelect: (a: Archetype) => void
}) {
  const [sort, setSort] = useState<'alpha' | 'likeness'>('alpha')
  const [activeCategories, setActiveCategories] = useState<Set<string>>(new Set())
  const { data: matrix } = useSimilarity()

  const catCounts = useMemo(() => {
    const c: Record<string, number> = {}
    for (const a of archetypes) c[a.category] = (c[a.category] ?? 0) + 1
    return c
  }, [archetypes])

  function toggleCat(cat: string) {
    setActiveCategories(prev => {
      const next = new Set(prev)
      next.has(cat) ? next.delete(cat) : next.add(cat)
      return next
    })
  }

  const filtered = activeCategories.size > 0
    ? archetypes.filter(a => activeCategories.has(a.category))
    : archetypes

  const sorted = useMemo(() => {
    if (sort === 'alpha') return [...filtered].sort((a, b) => a.name.localeCompare(b.name))
    if (!matrix) return filtered
    const scores = matrix['archetypes'] ?? {}
    const getScore = (a: string, b: string) =>
      scores[a]?.[b]?.score ?? scores[b]?.[a]?.score ?? 0
    const remaining = new Set(filtered.map(a => a.id))
    const order: string[] = []
    let current = filtered[0]?.id ?? ''
    while (remaining.size > 0) {
      order.push(current)
      remaining.delete(current)
      if (remaining.size === 0) break
      let bestId = ''
      let bestScore = -1
      for (const id of remaining) {
        const s = getScore(current, id)
        if (s > bestScore) { bestScore = s; bestId = id }
      }
      current = bestId
    }
    const byId = Object.fromEntries(filtered.map(a => [a.id, a]))
    return order.map(id => byId[id]).filter(Boolean)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtered, sort, matrix])

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-3xl mx-auto px-8 py-12 space-y-8">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {archetypes.length} workout archetypes.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Archetypes define the structure of a session — movement patterns, slot sequences, and loading schemes.
            Select one to explore its slots, equipment, scaling, and similar sessions.
          </p>
        </div>

        {/* Category chips — additive filter */}
        <div className="space-y-1.5">
          <div className="flex flex-wrap gap-2">
            {Object.entries(catCounts).map(([cat, count]) => {
              const color = ARCH_CAT_COLORS[cat] ?? '#94a3b8'
              const active = activeCategories.has(cat)
              return (
                <button
                  key={cat}
                  onClick={() => toggleCat(cat)}
                  className="flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-mono transition-all"
                  style={active
                    ? { backgroundColor: `${color}30`, color, border: `1px solid ${color}60` }
                    : { backgroundColor: `${color}15`, color, border: `1px solid ${color}30`, opacity: 0.7 }
                  }
                >
                  <div className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
                  {cat.replace(/_/g, ' ')} · {count}
                </button>
              )
            })}
          </div>
          {activeCategories.size > 0 && (
            <button
              onClick={() => setActiveCategories(new Set())}
              className="text-[10px] text-muted-foreground/50 hover:text-foreground transition-colors"
            >
              Clear filter
            </button>
          )}
        </div>

        {/* Sort controls */}
        <div className="flex items-center gap-2">
          <span className="text-[10px] text-muted-foreground/50 uppercase tracking-wider font-medium">Sort</span>
          {(['alpha', 'likeness'] as const).map(s => (
            <button
              key={s}
              onClick={() => setSort(s)}
              className={cn(
                'px-2.5 py-1 rounded text-[11px] border transition-colors',
                sort === s
                  ? 'bg-primary/15 border-primary/40 text-primary'
                  : 'border-border/40 text-muted-foreground hover:bg-muted/40'
              )}
            >
              {s === 'alpha' ? 'A → Z' : 'By likeness'}
            </button>
          ))}
        </div>

        {/* Grid */}
        <div className="grid grid-cols-2 gap-2">
          {sorted.map(arch => (
            <ArchetypeLandingCard key={arch.id} archetype={arch} onSelect={() => onSelect(arch)} />
          ))}
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select an archetype to explore its full structure
        </p>
      </div>
    </div>
  )
}

// ─── Archetype detail page ────────────────────────────────────────────────────

function ArchetypeDetail({ archetype, allExercises, allArchetypes, onBack }: {
  archetype: Archetype
  allExercises: Exercise[]
  allArchetypes: Archetype[]
  onBack: () => void
}) {
  const catColor = ARCH_CAT_COLORS[archetype.category] ?? '#94a3b8'

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-8 space-y-6">

        {/* Back link */}
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground/60 hover:text-foreground transition-colors"
        >
          <ArrowLeft className="size-3" />
          All archetypes
        </button>

        {/* Name header */}
        <div className="flex items-start gap-3 flex-wrap">
          <div className="flex-1 space-y-1.5">
            <div className="flex items-center gap-2">
              <div className="size-2.5 rounded-full shrink-0" style={{ backgroundColor: catColor }} />
              <span
                className="text-[10px] font-mono uppercase tracking-wider"
                style={{ color: catColor }}
              >
                {archetype.category.replace(/_/g, ' ')}
              </span>
            </div>
            <h2 className="text-xl font-semibold">{archetype.name}</h2>
          </div>
          <div className="flex items-center gap-2 text-[11px] font-mono text-muted-foreground shrink-0 pt-1">
            <span>{archetype.duration_estimate_minutes}min</span>
            <span>·</span>
            <span>{(archetype.slots ?? []).length} slots</span>
          </div>
        </div>

        {/* Card content — always open, no accordion */}
        <ArchetypeCard
          archetype={archetype}
          allExercises={allExercises}
          allArchetypes={allArchetypes}
          isOpen={true}
          onToggle={() => {}}
          alwaysOpen
        />
      </div>
    </div>
  )
}

// ─── Similarity matrix view ───────────────────────────────────────────────────

interface MatrixItem {
  id: string
  label: string
  hex: string
}

function SimilarityMatrix({
  category,
  items,
  onSelect,
}: {
  category: string
  items: MatrixItem[]
  onSelect: (id: string) => void
}) {
  const { data: matrix, isLoading } = useSimilarity()
  const [hovered, setHovered] = useState<{ row: string; col: string } | null>(null)

  if (isLoading) return (
    <div className="flex items-center justify-center h-full text-xs text-muted-foreground">
      Loading similarity data…
    </div>
  )
  if (!matrix) return null

  const scores = matrix[category] ?? {}

  // Short names for column headers (first word or first 8 chars)
  function shortLabel(label: string) {
    const w = label.split(/\s+/)
    return w.length > 1 ? w[0] : label.slice(0, 8)
  }

  return (
    <div className="h-full overflow-auto p-4">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/40 font-medium mb-3">
        Pairwise similarity — {items.length} × {items.length}
      </p>
      <div className="inline-block">
        {/* Header row */}
        <div className="flex">
          <div style={{ width: 140, minWidth: 140 }} /> {/* row label spacer */}
          {items.map((col) => (
            <div
              key={col.id}
              style={{ width: 32, minWidth: 32 }}
              className="flex items-end justify-center pb-1"
            >
              <span
                className="text-[8px] font-mono text-muted-foreground/50 truncate"
                style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', maxHeight: 60 }}
                title={col.label}
              >
                {shortLabel(col.label)}
              </span>
            </div>
          ))}
        </div>
        {/* Data rows */}
        {items.map((row) => (
          <div key={row.id} className="flex items-center">
            {/* Row label */}
            <button
              style={{ width: 140, minWidth: 140 }}
              className="text-[10px] font-medium text-right pr-2 text-muted-foreground/70 hover:text-foreground truncate transition-colors"
              onClick={() => onSelect(row.id)}
              title={row.label}
            >
              {row.label}
            </button>
            {/* Cells */}
            {items.map((col) => {
              const isSelf = row.id === col.id
              const result = isSelf ? null : (scores[row.id]?.[col.id] ?? scores[col.id]?.[row.id])
              const score = result?.score ?? (isSelf ? 1 : 0)
              const isHovered = hovered?.row === row.id && hovered?.col === col.id
              const detail = result?.primary?.detail ?? ''

              return (
                <div
                  key={col.id}
                  style={{ width: 32, minWidth: 32, height: 32 }}
                  className="relative flex items-center justify-center cursor-pointer"
                  onMouseEnter={() => !isSelf && setHovered({ row: row.id, col: col.id })}
                  onMouseLeave={() => setHovered(null)}
                  onClick={() => !isSelf && onSelect(row.id)}
                >
                  <div
                    className="size-full transition-all"
                    style={{
                      backgroundColor: isSelf
                        ? `${row.hex}60`
                        : `${row.hex}${Math.round(score * 200).toString(16).padStart(2, '0')}`,
                      outline: isHovered ? `2px solid ${row.hex}` : undefined,
                      outlineOffset: -1,
                    }}
                  />
                  {isHovered && !isSelf && (
                    <div
                      className="absolute z-50 bottom-full left-1/2 -translate-x-1/2 mb-1.5 pointer-events-none
                                 rounded-md border border-border bg-popover px-2.5 py-1.5 shadow-lg text-left"
                      style={{ minWidth: 160 }}
                    >
                      <p className="text-[10px] font-semibold text-foreground mb-0.5">
                        {row.label} × {col.label}
                      </p>
                      <p className="text-[9px] font-mono text-primary">{Math.round(score * 100)}% similar</p>
                      {detail && <p className="text-[9px] text-muted-foreground/70 mt-0.5 leading-snug">{detail}</p>}
                    </div>
                  )}
                  {!isSelf && score > 0.6 && (
                    <span className="absolute inset-0 flex items-center justify-center text-[8px] font-mono text-white/60 pointer-events-none">
                      {Math.round(score * 100)}
                    </span>
                  )}
                </div>
              )
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

// ─── Page ─────────────────────────────────────────────────────────────────────

type ExploreSection = 'explorer' | 'ontology'

const EXPLORE_SECTIONS: { key: ExploreSection; label: string }[] = [
  { key: 'explorer', label: 'Explorer' },
  { key: 'ontology', label: 'Ontology' },
]

export function Explore() {
  const [section, setSection] = useState<ExploreSection>('explorer')
  const [topic, setTopic] = useState<Topic>('philosophies')
  const [selectedPhil, setSelectedPhil] = useState<Philosophy | null>(null)
  const [selectedMod, setSelectedMod] = useState<Modality | null>(null)
  const [selectedArchetype, setSelectedArchetype] = useState<Archetype | null>(null)
  const [selectedExercise, setSelectedExercise] = useState<Exercise | null>(null)

  const { data: philosophies = [], isLoading: philLoading, error: philError } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: modalities = [], isLoading: modLoading, error: modError } = useModalities()
  const { data: allArchetypes = [] } = useArchetypes()
  const { data: allExercises = [] } = useExercises()

  function handleTopicChange(t: Topic) {
    setTopic(t)
    setSelectedPhil(null)
    setSelectedMod(null)
    setSelectedArchetype(null)
    setSelectedExercise(null)
  }

  function handleNavigateExercise(id: string) {
    const ex = allExercises.find((e) => e.id === id)
    if (ex) setSelectedExercise(ex)
  }

  const isLoading = topic === 'philosophies' ? philLoading : modLoading
  const error = topic === 'philosophies' ? philError : modError

  return (
    <motion.div
      key="explore"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="flex items-center gap-3 border-b px-6 py-4 shrink-0 flex-wrap">
        <Compass className="size-5 text-primary shrink-0" />
        <h1 className="text-lg font-semibold shrink-0">Explore</h1>
        <div className="flex gap-1 shrink-0">
          {EXPLORE_SECTIONS.map(({ key, label }) => (
            <button
              key={key}
              onClick={() => setSection(key)}
              className={cn(
                'px-3 py-1 rounded text-xs border transition-colors',
                section === key
                  ? 'bg-primary/15 border-primary/40 text-primary'
                  : 'border-border text-muted-foreground hover:bg-muted'
              )}
            >
              {label}
            </button>
          ))}
        </div>
        {section === 'explorer' && (
          <>
            <div className="w-px h-4 bg-border/60 shrink-0" />
            <TopicSelector active={topic} onChange={handleTopicChange} />
          </>
        )}
      </div>

      {/* ── Explorer: unified landing ↔ detail pattern for all topics ── */}
      {section === 'explorer' && (
        (topic === 'philosophies' || topic === 'modalities') && isLoading
          ? <div className="flex-1 p-6"><LoadingCard /></div>
          : (topic === 'philosophies' || topic === 'modalities') && error
          ? <div className="flex-1 p-6"><ErrorBanner error={error as Error} /></div>
          : (
            <div className="flex-1 min-h-0 overflow-hidden">
                {topic === 'philosophies' && (
                  selectedPhil
                    ? <PhilosophyExplorerPanel
                        controlledId={selectedPhil.id}
                        onBack={() => setSelectedPhil(null)}
                      />
                    : <PhilosophyOverview
                        philosophies={philosophies}
                        frameworks={frameworks}
                        onSelect={setSelectedPhil}
                      />
                )}
                {topic === 'modalities' && (
                  selectedMod
                    ? <ModalityDetail
                        mod={selectedMod}
                        modalities={modalities}
                        philosophies={philosophies}
                        allArchetypes={allArchetypes}
                        onSelectMod={setSelectedMod}
                        onBack={() => setSelectedMod(null)}
                      />
                    : <ModalityOverview modalities={modalities} onSelect={setSelectedMod} />
                )}
                {topic === 'archetypes' && (
                  selectedArchetype
                    ? <ArchetypeDetail
                        archetype={selectedArchetype}
                        allExercises={allExercises}
                        allArchetypes={allArchetypes}
                        onBack={() => setSelectedArchetype(null)}
                      />
                    : <ArchetypeLanding archetypes={allArchetypes} onSelect={setSelectedArchetype} />
                )}
                {topic === 'exercises' && (
                  selectedExercise
                    ? <ExercisePanel
                        exercise={selectedExercise}
                        allExercises={allExercises}
                        onNavigate={handleNavigateExercise}
                        onBack={() => setSelectedExercise(null)}
                      />
                    : <ExerciseLanding allExercises={allExercises} onSelect={setSelectedExercise} />
                )}
            </div>
          )
      )}

      {/* ── Ontology ── */}
      {section === 'ontology' && (
        <div className="flex-1 overflow-y-auto px-6 py-4" style={{ scrollbarGutter: 'stable' }}>
          <HeatmapPanel program={null} />
        </div>
      )}
    </motion.div>
  )
}
