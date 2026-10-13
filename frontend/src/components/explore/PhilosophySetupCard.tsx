import type { Framework, ModalityId, Philosophy } from '@/api/types'
import { PhaseSpine } from '@/components/shared/PhaseSpine'
import { mainFramework, primaryTrack, tracksOf, trackWeeks } from '@/lib/tracks'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { Section, StatCell } from './ExploreSection'
import { SessionsPerWeekRows } from './SessionsPerWeekRows'

const TIER_COLORS = { committed: '#ef4444', core: '#f97316', supplementary: '#64748b' } as const

/**
 * How a philosophy is set up, before any program exists: each of its tracks
 * with its own phases, the weekly shape of the framework that leads the
 * primary track, and what it asks of the athlete. Everything here is authored
 * in the package.
 */
export function PhilosophySetupCard({ phil, frameworks, accentHex }: {
  phil: Philosophy; frameworks: Framework[]; accentHex: string
}) {
  const tracks = tracksOf(phil)
  const lead = primaryTrack(phil)
  const primary = mainFramework(lead, frameworks) ?? frameworks[0]
  const expectations = phil.expectations ?? primary?.expectations
  const intensity = primary?.intensity_distribution
    ? INTENSITY_BUCKETS.map((b) => ({ ...b, pct: primary.intensity_distribution![b.key] ?? 0 })).filter((b) => b.pct > 0)
    : []

  return (
    <div className="rounded-lg border border-border/40 bg-card/40 p-4 space-y-4">
      <div>
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">How it's set up</p>
        <p className="text-[11px] text-muted-foreground mt-0.5">
          {tracks.length > 1
            ? `${tracks.length} tracks to pick from`
            : lead
              ? `${lead.phases.length} phase${lead.phases.length === 1 ? '' : 's'} over ${trackWeeks(lead)} weeks`
              : 'No phases declared'}
        </p>
      </div>

      {tracks.map((t) => (
        <Section key={t.id} label={tracks.length > 1 ? `Track — ${t.name}` : `Phases — ${t.name}`}>
          {t.description && (
            <p className="text-[10px] text-muted-foreground leading-relaxed">{t.description}</p>
          )}
          <PhaseSpine phases={t.phases} frameworks={frameworks} showFrameworks />
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
