import { Link } from 'react-router-dom'
import { ArrowRight } from 'lucide-react'
import type { AnalyticsSpecs, PhilosophySpec } from '@/api/types'
import { useProgramAnalytics } from '@/api/analytics'
import { Section } from './ExploreSection'
import { SpecSourceBadge } from './SpecSourceBadge'
import { ProgressSpecRow } from './ProgressSpecRow'

const WHY_LABEL = { declared: 'declared', entry: 'from a signal', source: 'cites this philosophy' } as const

/**
 * What a philosophy tracks and measures — its analytics spec, in words:
 * the signals it counts as progress, the standards it is measured by, the
 * movement balance it polices, and what has to be logged for any of it to
 * measure. The static twin of the Program tab's methodology section.
 */
export function PhilosophyMeasuresCard({ spec, vocabulary, accentHex }: {
  spec: PhilosophySpec; vocabulary: AnalyticsSpecs['vocabulary']; accentHex: string
}) {
  const { data: program } = useProgramAnalytics()
  const onActiveProgram = program?.status === 'ok'
    && program.frame.philosophies.some((p) => p.id === spec.philosophy)
  const ordered = [...spec.progress].sort((a, b) => Number(b.headline) - Number(a.headline))

  return (
    <div className="rounded-lg border border-border/40 bg-card/40 p-4 space-y-4">
      <div className="flex items-start justify-between gap-2 flex-wrap">
        <div>
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">What it tracks &amp; measures</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            {spec.progress.length} signal{spec.progress.length === 1 ? '' : 's'}
            {spec.progressionPhilosophy && <> · progresses by {spec.progressionPhilosophy.replace(/_based$/, '').replace(/_/g, ' ')}</>}
          </p>
        </div>
        <SpecSourceBadge source={spec.source} file={spec.file} />
      </div>

      <Section label="Progress signals">
        <div className="space-y-1.5">
          {ordered.map((entry) => (
            <ProgressSpecRow key={entry.id} entry={entry} vocab={vocabulary.primitives[entry.primitive]} accentHex={accentHex} defaultOpen={entry.headline} />
          ))}
          {ordered.length === 0 && (
            <p className="text-[10px] text-muted-foreground/60">No frameworks govern a modality, so nothing is measured.</p>
          )}
        </div>
      </Section>

      {spec.benchmarks.length > 0 && (
        <Section label="Standards it's measured by">
          <ul className="space-y-0.5">
            {spec.benchmarks.map((b) => (
              <li key={b.id} className="flex items-baseline gap-2 text-[10px]">
                <span className="text-foreground/80">{b.name}</span>
                <span className="font-mono text-muted-foreground/60">{WHY_LABEL[b.why]}</span>
              </li>
            ))}
          </ul>
        </Section>
      )}

      <Section label="Movement balance">
        <ul className="space-y-0.5">
          {spec.movement.balance.map((r) => (
            <li key={`${r.a}-${r.b}`} className="text-[10px] text-muted-foreground">
              <span className="text-foreground/80">{r.a} : {r.b}</span> kept between {r.min} and {r.max}
            </li>
          ))}
        </ul>
        {!spec.movement.declared && (
          <p className="text-[10px] text-muted-foreground/60 italic">
            Shown for information only — this philosophy declares no balance rule, so nothing warns.
          </p>
        )}
      </Section>

      {spec.needs.length > 0 && (
        <Section label="What you need to log">
          <ul className="space-y-1">
            {spec.needs.map((n) => (
              <li key={n.field} className="text-[10px] leading-relaxed">
                <span className="text-foreground/80">{n.label}</span>
                <span className="text-muted-foreground"> — {n.where}</span>
                <span className="text-muted-foreground/60"> · feeds {n.entries.map((id) => spec.progress.find((e) => e.id === id)?.label ?? id).join(', ')}</span>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {onActiveProgram && (
        <Link to="/analytics" className="inline-flex items-center gap-1 text-[11px] font-medium hover:underline" style={{ color: accentHex }}>
          See it on your program <ArrowRight className="size-3" />
        </Link>
      )}
    </div>
  )
}
