import { useMemo } from 'react'
import type { Framework, FrameworkPhaseEntry, ModalityId, Philosophy, TrainingPhase } from '@/api/types'
import type { PhaseSegment } from '@/hooks/usePhaseCalendar'
import { PhaseBar } from '@/components/program/PhaseBar'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { Section, StatCell } from './ExploreSection'
import { SessionsPerWeekRows } from './SessionsPerWeekRows'

const TIER_COLORS = { committed: '#ef4444', core: '#f97316', supplementary: '#64748b' } as const

function toSegments(phases: FrameworkPhaseEntry[]): PhaseSegment[] {
  const segments: PhaseSegment[] = []
  let cursor = 1
  for (const p of phases) {
    segments.push({ phase: p.phase as TrainingPhase, weeks: p.weeks, focus: p.focus, startWeek: cursor, endWeek: cursor + p.weeks - 1 })
    cursor += p.weeks
  }
  return segments
}

/**
 * How a philosophy is set up, before any program exists: its phase spine (or
 * the styles it offers), the weekly shape of the framework that leads it, and
 * what it asks of the athlete. Everything here is authored in the package.
 */
export function PhilosophySetupCard({ phil, frameworks, accentHex }: {
  phil: Philosophy; frameworks: Framework[]; accentHex: string
}) {
  const fwById = useMemo(() => Object.fromEntries(frameworks.map((f) => [f.id, f])), [frameworks])
  const sequential = phil.framework_groups?.find((g) => g.type === 'sequential')
  const phases = useMemo(
    () => sequential?.canonical_phase_sequence ?? phil.canonical_phase_sequence ?? [],
    [sequential, phil.canonical_phase_sequence],
  )
  const alternatives = (phil.framework_groups ?? []).filter((g) => g.type === 'alternatives')
  const segments = useMemo(() => toSegments(phases), [phases])
  const totalWeeks = segments.reduce((s, seg) => s + seg.weeks, 0)

  const primary = fwById[phil.primary_framework_id ?? ''] ?? frameworks[0]
  const expectations = phil.expectations ?? primary?.expectations
  const intensity = primary?.intensity_distribution
    ? INTENSITY_BUCKETS.map((b) => ({ ...b, pct: primary.intensity_distribution![b.key] ?? 0 })).filter((b) => b.pct > 0)
    : []

  return (
    <div className="rounded-lg border border-border/40 bg-card/40 p-4 space-y-4">
      <div>
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">How it's set up</p>
        <p className="text-[11px] text-muted-foreground mt-0.5">
          {phases.length
            ? `${phases.length} phases over ${totalWeeks} weeks`
            : alternatives.length
              ? `${frameworks.length} style${frameworks.length === 1 ? '' : 's'} to pick from`
              : `${frameworks.length} framework${frameworks.length === 1 ? '' : 's'}`}
        </p>
      </div>

      {segments.length > 0 && (
        <Section label={sequential ? `Phases — ${sequential.name}` : 'Phases'}>
          <PhaseBar segments={segments} totalWeeks={totalWeeks} currentWeek={0} />
          <ul className="space-y-1 pt-1">
            {phases.map((p, i) => {
              const c = PHASE_COLORS[p.phase as TrainingPhase]
              const fw = p.framework_id ? fwById[p.framework_id] : undefined
              return (
                <li key={`${p.phase}-${i}`} className="flex items-baseline gap-2 text-[10px]">
                  <span className="w-16 shrink-0 font-medium" style={{ color: c?.hex }}>{c?.label ?? p.phase}</span>
                  <span className="w-8 shrink-0 font-mono text-muted-foreground">{p.weeks}wk</span>
                  <span className="min-w-0 text-muted-foreground">
                    {fw && <span className="text-foreground/80">{fw.name}</span>}
                    {fw && p.focus && ' — '}
                    {p.focus}
                  </span>
                </li>
              )
            })}
          </ul>
        </Section>
      )}

      {alternatives.map((g) => (
        <Section key={g.id} label={`Pick one style — ${g.name}`}>
          <div className="flex flex-wrap gap-1">
            {g.frameworks.map((id) => (
              <span key={id} className="text-[10px] px-1.5 py-0.5 rounded font-mono border"
                style={{ color: accentHex, backgroundColor: `${accentHex}15`, borderColor: `${accentHex}30` }}>
                {fwById[id]?.name ?? id.replace(/_/g, ' ')}
              </span>
            ))}
          </div>
        </Section>
      ))}

      {primary && (
        <Section label={`Weekly shape — ${primary.name}`}>
          <SessionsPerWeekRows sessionsPerWeek={primary.sessions_per_week} accentHex={accentHex} />
          {primary.modality_priority && (
            <div className="flex flex-wrap gap-x-3 gap-y-1 pt-1">
              {(['committed', 'core', 'supplementary'] as const).map((tier) => {
                const mods = primary.modality_priority?.[tier] ?? []
                if (!mods.length) return null
                return (
                  <div key={tier} className="flex items-center gap-1">
                    <span className="text-[9px] uppercase tracking-wider font-medium" style={{ color: TIER_COLORS[tier] }}>{tier}</span>
                    {mods.map((m) => {
                      const mc = MODALITY_COLORS[m as ModalityId]
                      return (
                        <span key={m} className="text-[9px] px-1 py-0.5 rounded font-mono"
                          style={{ color: mc?.hex ?? TIER_COLORS[tier], backgroundColor: `${mc?.hex ?? TIER_COLORS[tier]}15` }}>
                          {mc?.label ?? m.replace(/_/g, ' ')}
                        </span>
                      )
                    })}
                  </div>
                )
              })}
            </div>
          )}
          {intensity.length > 0 && (
            <div className="space-y-1 pt-1">
              <div className="flex h-2 w-full overflow-hidden rounded-full bg-muted gap-px">
                {intensity.map((b) => (
                  <div key={b.key} style={{ width: `${b.pct * 100}%`, backgroundColor: b.color }} title={`${b.label}: ${Math.round(b.pct * 100)}%`} />
                ))}
              </div>
              <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                {intensity.map((b) => (
                  <span key={b.key} className="flex items-center gap-1 text-[9px] text-muted-foreground">
                    <span className="size-1.5 rounded-full" style={{ backgroundColor: b.color }} />
                    {b.label} {Math.round(b.pct * 100)}%
                  </span>
                ))}
              </div>
            </div>
          )}
          {primary.deload_protocol && (
            <p className="text-[10px] text-muted-foreground pt-1">
              Deload every {primary.deload_protocol.frequency_weeks} weeks — volume −{Math.round(primary.deload_protocol.volume_reduction_pct * 100)}%, intensity {primary.deload_protocol.intensity_change}.
            </p>
          )}
        </Section>
      )}

      {expectations && (
        <Section label="What it asks of you">
          <div className="grid grid-cols-2 gap-2">
            <StatCell label="Weeks" value={expectations.min_weeks === expectations.ideal_weeks ? `${expectations.ideal_weeks}` : `${expectations.min_weeks}–${expectations.ideal_weeks}`} />
            <StatCell label="Days / week" value={expectations.min_days_per_week === expectations.ideal_days_per_week ? `${expectations.ideal_days_per_week}` : `${expectations.min_days_per_week}–${expectations.ideal_days_per_week}`} />
            <StatCell label="Session" value={`${expectations.ideal_session_minutes} min`} />
            {expectations.ideal_long_session_minutes != null
              ? <StatCell label="Long session" value={`${expectations.ideal_long_session_minutes} min`} />
              : <StatCell label="Split days" value={expectations.supports_split_days ? 'Supported' : 'No'} />}
          </div>
          {expectations.notes && <p className="text-[10px] text-muted-foreground/70 italic leading-relaxed">{expectations.notes}</p>}
        </Section>
      )}
    </div>
  )
}
