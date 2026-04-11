import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { BookOpen, Compass, Zap } from 'lucide-react'
import { RadarChart, PolarGrid, PolarAngleAxis, PolarRadiusAxis, Radar, ResponsiveContainer } from 'recharts'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useModalities } from '@/api/modalities'
import { useArchetypes } from '@/api/archetypes'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import { PhilosophyExplorerPanel } from '@/components/devlab/PhilosophyExplorerPanel'
import type { Philosophy, Modality, Archetype, ModalityId } from '@/api/types'

// ─── Archetype category colours ───────────────────────────────────────────────

const CATEGORY_META: Record<string, { label: string; hex: string }> = {
  strength:       { label: 'Strength',       hex: '#ef4444' },
  conditioning:   { label: 'Conditioning',   hex: '#0ea5e9' },
  kettlebell:     { label: 'Kettlebell',     hex: '#f97316' },
  gpp_durability: { label: 'GPP / Durability', hex: '#10b981' },
  movement_skill: { label: 'Movement / Skill', hex: '#14b8a6' },
}

const ALL_CATEGORIES = Object.keys(CATEGORY_META)

// ─── Helpers ─────────────────────────────────────────────────────────────────

function prettify(id: string) {
  return id.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function BiasChip({ id }: { id: string }) {
  const color = MODALITY_COLORS[id as ModalityId]
  return (
    <span className={cn(
      'inline-block px-1.5 py-0.5 rounded text-[10px] font-medium',
      color ? `${color.bg} ${color.text}` : 'bg-muted/50 text-muted-foreground'
    )}>
      {color?.label ?? prettify(id)}
    </span>
  )
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

type Topic = 'philosophies' | 'modalities'

interface TopicTab {
  id: Topic
  label: string
  Icon: React.ElementType
}

const TOPICS: TopicTab[] = [
  { id: 'philosophies', label: 'Philosophies', Icon: BookOpen },
  { id: 'modalities',   label: 'Modalities',   Icon: Zap },
]

function TopicSelector({
  active,
  onChange,
}: {
  active: Topic
  onChange: (t: Topic) => void
}) {
  return (
    <div className="flex shrink-0 px-2 pt-2">
      {TOPICS.map((tab, i) => {
        const isActive = tab.id === active
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-medium rounded-t-md border border-b-0',
              'transition-colors focus-visible:outline-none',
              isActive
                ? 'bg-card text-foreground border-border/60 z-10 shadow-sm'
                : 'bg-muted/30 text-muted-foreground border-border/30 hover:text-foreground hover:bg-muted/50',
            )}
            style={{ marginLeft: i === 0 ? 0 : -1, position: 'relative', zIndex: isActive ? 10 : 1 }}
          >
            <tab.Icon className="size-3 shrink-0" />
            {tab.label}
          </button>
        )
      })}
      {/* Bottom border line that sits under inactive tabs */}
      <div className="flex-1 border-b border-border/60" />
    </div>
  )
}

// ─── Philosophy card ──────────────────────────────────────────────────────────

function PhilCard({
  phil,
  isSelected,
  onSelect,
}: {
  phil: Philosophy
  isSelected: boolean
  onSelect: (p: Philosophy | null) => void
}) {
  const accentColor = MODALITY_COLORS[phil.bias[0] as ModalityId]?.hex ?? '#6366f1'

  return (
    <button
      type="button"
      onClick={() => onSelect(isSelected ? null : phil)}
      className={cn(
        'w-full text-left rounded-xl border bg-card transition-colors',
        !isSelected && 'hover:border-primary/40',
        'px-3 py-2.5 space-y-1',
      )}
      style={isSelected
        ? { borderColor: accentColor, borderLeftWidth: 3, borderWidth: 2, backgroundColor: `${accentColor}12` }
        : { borderLeftColor: accentColor, borderLeftWidth: 3 }
      }
    >
      <p className="text-xs font-semibold leading-snug">{phil.name}</p>
      <div className="flex flex-wrap gap-1 mt-1">
        {phil.bias.slice(0, 3).map((b) => <BiasChip key={b} id={b} />)}
      </div>
    </button>
  )
}

// ─── Modality card (in left list) ────────────────────────────────────────────

function ModalityCard({
  mod,
  isSelected,
  onSelect,
}: {
  mod: Modality
  isSelected: boolean
  onSelect: (m: Modality | null) => void
}) {
  const color = MODALITY_COLORS[mod.id]
  const accentHex = color?.hex ?? '#6366f1'

  return (
    <button
      type="button"
      onClick={() => onSelect(isSelected ? null : mod)}
      className={cn(
        'w-full text-left rounded-xl border bg-card transition-colors',
        !isSelected && 'hover:border-primary/40',
        'px-3 py-2.5 space-y-1',
      )}
      style={isSelected
        ? { borderColor: accentHex, borderLeftWidth: 3, borderWidth: 2, backgroundColor: `${accentHex}12` }
        : { borderLeftColor: accentHex, borderLeftWidth: 3 }
      }
    >
      <p className="text-xs font-semibold leading-snug">{mod.name}</p>
      <div className="flex items-center gap-1.5 mt-1">
        <RecoveryCostBadge cost={mod.recovery_cost} />
      </div>
    </button>
  )
}

// ─── Philosophy overview (nothing selected) ───────────────────────────────────

function PhilosophyOverview({ philosophies, frameworks }: {
  philosophies: Philosophy[]
  frameworks: { source_philosophy?: string; sessions_per_week?: Record<string, number> }[]
}) {
  const modalityStats = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const fw of frameworks) {
      for (const [mod, n] of Object.entries(fw.sessions_per_week ?? {})) {
        counts[mod] = (counts[mod] ?? 0) + (n as number)
      }
    }
    const max = Math.max(...Object.values(counts), 1)
    return (Object.keys(MODALITY_COLORS) as ModalityId[])
      .map(id => ({ id, pct: Math.round(((counts[id] ?? 0) / max) * 100) }))
      .sort((a, b) => b.pct - a.pct)
  }, [frameworks])

  const philSummaries = useMemo(() =>
    philosophies.map(p => ({
      p,
      fwCount: frameworks.filter(fw => fw.source_philosophy === p.id).length,
      color: MODALITY_COLORS[p.bias[0] as ModalityId]?.hex ?? '#6366f1',
    })),
    [philosophies, frameworks]
  )

  const uniqueModalities = modalityStats.filter(m => m.pct > 0).length

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {philosophies.length} source philosophies.<br />
            <span className="text-muted-foreground font-normal">
              {uniqueModalities} modalities. One system.
            </span>
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Each philosophy encodes a distinct theory of adaptation — how to stress, recover, and progress.
            Select one to explore its frameworks, modality profile, archetypes, and exercise vocabulary.
          </p>
        </div>

        <div className="space-y-2">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/40 font-medium">
            Modality coverage across all philosophies
          </p>
          <div className="flex rounded-lg overflow-hidden h-3 gap-px">
            {modalityStats.filter(m => m.pct > 0).map(m => (
              <div
                key={m.id}
                title={MODALITY_COLORS[m.id].label}
                style={{ flex: m.pct, backgroundColor: MODALITY_COLORS[m.id].hex, opacity: 0.75 }}
              />
            ))}
          </div>
          <div className="flex flex-wrap gap-x-3 gap-y-1 pt-1">
            {modalityStats.filter(m => m.pct > 0).map(m => (
              <div key={m.id} className="flex items-center gap-1">
                <div className="size-1.5 rounded-full" style={{ backgroundColor: MODALITY_COLORS[m.id].hex }} />
                <span className="text-[9px] text-muted-foreground/60">{MODALITY_COLORS[m.id].label}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/40 font-medium">
            Sources
          </p>
          <div className="grid grid-cols-2 gap-2">
            {philSummaries.map(({ p, fwCount, color }) => (
              <div
                key={p.id}
                className="flex items-start gap-2.5 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5"
                style={{ borderLeftColor: color, borderLeftWidth: 2 }}
              >
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-medium leading-snug truncate">{p.name}</p>
                  <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                    {fwCount} framework{fwCount !== 1 ? 's' : ''} · {p.bias.length} bias{p.bias.length !== 1 ? 'es' : ''}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select a philosophy from the list to explore its full structure
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
                className="text-left rounded-lg border border-border/40 bg-card/40 overflow-hidden hover:border-primary/40 transition-colors"
              >
                <div className="h-1 w-full" style={{ backgroundColor: hex, opacity: 0.7 }} />
                <div className="px-3 py-2.5 space-y-1.5">
                  <p className="text-[11px] font-semibold leading-snug" style={{ color: hex }}>{mod.name}</p>
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

// ─── Modality radar chart — archetype category profile ────────────────────────

type ModalityChartMode = 'chart' | 'vs-all' | 'used' | 'all'

function CategoryAxisTick({ x, y, payload }: { x?: number; y?: number; payload?: { value: string } }) {
  if (x === undefined || y === undefined || !payload) return null
  const meta = Object.values(CATEGORY_META).find(m => m.label === payload.value)
  const color = meta?.hex ?? '#64748b'
  const words = payload.value.split(' / ').join('\n').split(' ')
  // wrap to two lines at ~12 chars
  const lines: string[] = []
  let cur = ''
  for (const w of words) {
    if (cur.length + w.length > 12 && cur) { lines.push(cur.trim()); cur = '' }
    cur += w + ' '
  }
  if (cur.trim()) lines.push(cur.trim())
  return (
    <g>
      {lines.map((line, i) => (
        <text key={i} x={x} y={y + i * 11 - (lines.length - 1) * 5.5}
          textAnchor="middle" dominantBaseline="central"
          fontSize={9} fontFamily="ui-monospace, monospace" fill={color}>
          {line}
        </text>
      ))}
    </g>
  )
}

function ModalityRadarChart({ mod, allArchetypes }: { mod: Modality; allArchetypes: Archetype[] }) {
  const [viewMode, setViewMode] = useState<ModalityChartMode>('chart')
  const primaryColor = MODALITY_COLORS[mod.id]?.hex ?? '#6366f1'

  const { chartData, vsAllData, usedData, allData } = useMemo(() => {
    // Counts for this modality
    const modArchetypes = allArchetypes.filter(a => a.modality === mod.id)
    const counts: Record<string, number> = {}
    for (const a of modArchetypes) counts[a.category] = (counts[a.category] ?? 0) + 1
    const maxCount = Math.max(...Object.values(counts), 1)

    // Global counts across all archetypes
    const globalCounts: Record<string, number> = {}
    for (const a of allArchetypes) globalCounts[a.category] = (globalCounts[a.category] ?? 0) + 1
    const globalMax = Math.max(...Object.values(globalCounts), 1)

    const usedCategories = ALL_CATEGORIES.filter(c => (counts[c] ?? 0) > 0)

    const usedData = usedCategories
      .map(c => ({ cat: c, label: CATEGORY_META[c]?.label ?? c, hex: CATEGORY_META[c]?.hex ?? '#94a3b8', pct: Math.round(((counts[c] ?? 0) / maxCount) * 100) }))
      .sort((a, b) => b.pct - a.pct)

    const allData = ALL_CATEGORIES
      .map(c => ({ cat: c, label: CATEGORY_META[c]?.label ?? c, hex: CATEGORY_META[c]?.hex ?? '#94a3b8', pct: Math.round(((counts[c] ?? 0) / maxCount) * 100) }))
      .sort((a, b) => b.pct - a.pct)

    const chartData = usedData.map(({ label, pct }) => ({ subject: label, value: +(pct / 100).toFixed(2) }))

    const vsAllData = ALL_CATEGORIES.map(c => ({
      subject: CATEGORY_META[c]?.label ?? c,
      selected: +((counts[c] ?? 0) / maxCount).toFixed(2),
      all: +((globalCounts[c] ?? 0) / globalMax).toFixed(2),
    }))

    return { chartData, vsAllData, usedData, allData }
  }, [mod.id, allArchetypes])

  if (chartData.length === 0) return (
    <div className="flex flex-col gap-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Archetype Profile</p>
      <p className="text-[10px] text-muted-foreground/40">No archetypes linked to this modality</p>
    </div>
  )

  const MODES: { key: ModalityChartMode; label: string }[] = [
    { key: 'chart',  label: 'chart'  },
    { key: 'vs-all', label: 'vs·all' },
    { key: 'used',   label: 'used'   },
    { key: 'all',    label: 'all'    },
  ]
  const barList = viewMode === 'all' ? allData : usedData

  return (
    <div className="flex flex-col gap-3">
      {/* Header + toggle */}
      <div className="flex items-center justify-between gap-2">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Archetype Profile</p>
        <div className="flex rounded-md overflow-hidden border border-border/40 shrink-0">
          {MODES.map(({ key, label }) => (
            <button key={key} onClick={() => setViewMode(key)}
              className={[
                'px-2 py-0.5 text-[9px] font-mono uppercase tracking-wider transition-colors',
                viewMode === key
                  ? 'bg-primary/20 text-primary'
                  : 'text-muted-foreground/50 hover:text-muted-foreground hover:bg-muted/20',
              ].join(' ')}
            >{label}</button>
          ))}
        </div>
      </div>

      {/* Radar — this modality only */}
      {viewMode === 'chart' && (
        <div style={{ width: '100%', height: 240 }}>
          <ResponsiveContainer width="100%" height="100%">
            <RadarChart data={chartData} margin={{ top: 24, right: 48, bottom: 24, left: 48 }}>
              <PolarGrid stroke={primaryColor} strokeOpacity={0.18} />
              <PolarRadiusAxis domain={[0, 1]} tick={false} axisLine={false} />
              <PolarAngleAxis dataKey="subject" tick={(props) => <CategoryAxisTick {...props} />} />
              <Radar dataKey="value" stroke={primaryColor} fill={primaryColor} fillOpacity={0.22} strokeWidth={2} />
            </RadarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Radar — vs all modalities combined */}
      {viewMode === 'vs-all' && (
        <>
          <div style={{ width: '100%', height: 240 }}>
            <ResponsiveContainer width="100%" height="100%">
              <RadarChart data={vsAllData} margin={{ top: 24, right: 48, bottom: 24, left: 48 }}>
                <PolarGrid stroke={primaryColor} strokeOpacity={0.15} />
                <PolarRadiusAxis domain={[0, 1]} tick={false} axisLine={false} />
                <PolarAngleAxis dataKey="subject" tick={(props) => <CategoryAxisTick {...props} />} />
                <Radar dataKey="all" stroke="#64748b" fill="#64748b" fillOpacity={0.08} strokeWidth={1} strokeDasharray="3 2" />
                <Radar dataKey="selected" stroke={primaryColor} fill={primaryColor} fillOpacity={0.22} strokeWidth={2} />
              </RadarChart>
            </ResponsiveContainer>
          </div>
          <div className="flex gap-4 justify-end">
            <div className="flex items-center gap-1.5">
              <svg width={16} height={8}><line x1={0} y1={4} x2={16} y2={4} stroke={primaryColor} strokeWidth={2} /></svg>
              <span className="text-[9px] font-mono text-muted-foreground/70">{mod.name.split(' ')[0]}</span>
            </div>
            <div className="flex items-center gap-1.5">
              <svg width={16} height={8}><line x1={0} y1={4} x2={16} y2={4} stroke="#64748b" strokeWidth={1} strokeDasharray="3 2" /></svg>
              <span className="text-[9px] font-mono text-muted-foreground/70">all</span>
            </div>
          </div>
        </>
      )}

      {/* Bar list */}
      {(viewMode === 'used' || viewMode === 'all') && (
        <div className="space-y-2">
          {barList.map(item => (
            <div key={item.cat} className="flex items-center gap-2">
              <div className="size-2 rounded-full shrink-0" style={{ backgroundColor: item.hex, opacity: item.pct > 0 ? 1 : 0.25 }} />
              <span className={cn('text-[10px] flex-1 leading-tight', item.pct > 0 ? 'text-muted-foreground' : 'text-muted-foreground/30')}>
                {item.label}
              </span>
              <div className="flex items-center gap-1.5 shrink-0">
                <div className="w-12 h-1.5 rounded-full bg-muted/40 overflow-hidden">
                  <div className="h-full rounded-full" style={{ width: `${item.pct}%`, backgroundColor: item.hex }} />
                </div>
                <span className="text-[10px] font-mono w-7 text-right tabular-nums"
                  style={{ color: item.pct > 0 ? item.hex : undefined, opacity: item.pct > 0 ? 1 : 0.3 }}>
                  {item.pct}%
                </span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Legend for chart views */}
      {(viewMode === 'chart' || viewMode === 'vs-all') && usedData.length > 0 && (
        <div className="space-y-2">
          {usedData.map(item => (
            <div key={item.cat} className="flex items-center gap-2">
              <div className="size-2 rounded-full shrink-0" style={{ backgroundColor: item.hex }} />
              <span className="text-[10px] text-muted-foreground flex-1 leading-tight">{item.label}</span>
              <div className="flex items-center gap-1.5 shrink-0">
                <div className="w-12 h-1.5 rounded-full bg-muted/40 overflow-hidden">
                  <div className="h-full rounded-full" style={{ width: `${item.pct}%`, backgroundColor: item.hex }} />
                </div>
                <span className="text-[10px] font-mono w-7 text-right tabular-nums" style={{ color: item.hex }}>
                  {item.pct}%
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Modality detail ──────────────────────────────────────────────────────────

function ModalityDetail({
  mod,
  philosophies,
  allArchetypes,
}: {
  mod: Modality
  philosophies: Philosophy[]
  allArchetypes: Archetype[]
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

            {/* Right: archetype radar */}
            <div className="shrink-0 pl-5 border-l" style={{ borderColor: `${hex}20`, width: '36%', minWidth: 240 }}>
              <ModalityRadarChart mod={mod} allArchetypes={allArchetypes} />
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

// ─── Page ─────────────────────────────────────────────────────────────────────

export function Explore() {
  const [topic, setTopic] = useState<Topic>('philosophies')
  const [selectedPhil, setSelectedPhil] = useState<Philosophy | null>(null)
  const [selectedMod, setSelectedMod] = useState<Modality | null>(null)

  const { data: philosophies = [], isLoading: philLoading, error: philError } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: modalities = [], isLoading: modLoading, error: modError } = useModalities()
  const { data: allArchetypes = [] } = useArchetypes()

  function handleTopicChange(t: Topic) {
    setTopic(t)
    setSelectedPhil(null)
    setSelectedMod(null)
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
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <Compass className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Explore</h1>
      </div>

      {/* Body */}
      {isLoading ? (
        <div className="flex-1 p-6"><LoadingCard /></div>
      ) : error ? (
        <div className="flex-1 p-6"><ErrorBanner error={error as Error} /></div>
      ) : (
        <div className="flex flex-1 min-h-0">
          {/* Left column */}
          <div className="shrink-0 flex flex-col border-r" style={{ width: 272 }}>
            <TopicSelector active={topic} onChange={handleTopicChange} />

            <div className="flex-1 overflow-y-auto p-3 space-y-1.5">
              {topic === 'philosophies'
                ? philosophies.map((phil) => (
                    <PhilCard
                      key={phil.id}
                      phil={phil}
                      isSelected={selectedPhil?.id === phil.id}
                      onSelect={setSelectedPhil}
                    />
                  ))
                : modalities.map((mod) => (
                    <ModalityCard
                      key={mod.id}
                      mod={mod}
                      isSelected={selectedMod?.id === mod.id}
                      onSelect={setSelectedMod}
                    />
                  ))
              }
            </div>
          </div>

          {/* Right column */}
          <div className="flex-1 min-h-0 overflow-hidden">
            {topic === 'philosophies'
              ? selectedPhil
                ? <PhilosophyExplorerPanel controlledId={selectedPhil.id} />
                : <PhilosophyOverview philosophies={philosophies} frameworks={frameworks} />
              : selectedMod
                ? <ModalityDetail mod={selectedMod} philosophies={philosophies} allArchetypes={allArchetypes} />
                : <ModalityOverview modalities={modalities} onSelect={setSelectedMod} />
            }
          </div>
        </div>
      )}
    </motion.div>
  )
}
