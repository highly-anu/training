import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronLeft, ExternalLink, Loader2, Wand2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useAnalyticsSpecs } from '@/api/analyticsSpecs'
import { usePhilosophyDescription } from '@/api/philosophyDescription'
import { useBuilderStore } from '@/store/builderStore'
import { PhilosophyMeasuresCard } from '@/components/explore/PhilosophyMeasuresCard'
import { LineageSection } from '@/components/explore/LineageSection'
import { useLinkIndex } from '@/components/explore/useLineage'
import { StatCell } from '@/components/explore/ExploreSection'
import { SimilarItems } from '@/components/shared/SimilarItems'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { lineageOf } from '@/lib/exploreLinks'
import type { GoalExpectations, PhilosophyDescription } from '@/api/types'
import { ModalityMix } from './ModalityMix'
import { modalityHex } from '@/lib/modalityColors'
import { PhilosophyTracks } from './PhilosophyTracks'
import { PhilosophyRules } from './PhilosophyRules'
import { PhilosophySessions } from './PhilosophySessions'

function PageSection({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold">{title}</h3>
        {hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}
      </div>
      {children}
    </section>
  )
}

const range = (lo: number, hi: number, unit = '') => (lo === hi ? `${hi}${unit}` : `${lo}–${hi}${unit}`)

function Asks({ doc, expectations }: { doc: PhilosophyDescription; expectations: GoalExpectations | null }) {
  return (
    <div className="space-y-3">
      {expectations && (
        <div className="grid grid-cols-2 gap-2">
          <StatCell label="Weeks" value={range(expectations.min_weeks, expectations.ideal_weeks)} />
          <StatCell label="Days / week" value={range(expectations.min_days_per_week, expectations.ideal_days_per_week)} />
          <StatCell label="Session" value={`${expectations.ideal_session_minutes} min`} />
          {expectations.ideal_long_session_minutes != null
            ? <StatCell label="Long session" value={`${expectations.ideal_long_session_minutes} min`} />
            : <StatCell label="Split days" value={expectations.supports_split_days ? 'Supported' : 'No'} />}
        </div>
      )}
      {doc.equipment.length > 0 && (
        <div className="space-y-1">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">Equipment</p>
          <div className="flex flex-wrap gap-1">
            {doc.equipment.map((e) => (
              <span key={e.id} className="rounded border border-border/50 px-1.5 py-0.5 text-[10px] text-muted-foreground">{e.name}</span>
            ))}
          </div>
        </div>
      )}
      {doc.borrows.map((b) => (
        <p key={b.package} className="text-[11px] text-muted-foreground leading-relaxed">
          <span className="text-foreground/90">Borrows from {b.label}.</span> {b.reason}
        </p>
      ))}
      {expectations?.notes && <p className="text-[10px] italic text-muted-foreground/80">{expectations.notes}</p>}
    </div>
  )
}

/**
 * Explore ▸ Philosophies' detail: the philosophy as its package writes it
 * (GET /philosophies/<id>/describe). In the order a reader asks: what it is
 * and what its week is made of, how it runs over time, what it holds true,
 * what it asks of you, its sessions, what it measures, where it comes from.
 * Colour is the established systems only — modality for what kind of
 * training, phase kind for where in the program, heart-rate zones for
 * intensity — on neutral surfaces.
 */
export function PhilosophyPage({ id, onSelect, onBack }: {
  id: string; onSelect: (id: string) => void; onBack?: () => void
}) {
  const { data: doc, isLoading, error } = usePhilosophyDescription(id)
  const { data: philosophies = [] } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: specs } = useAnalyticsSpecs()
  const { index, names, colors } = useLinkIndex()
  const lineage = useMemo(() => (index ? lineageOf(index, 'philosophies', id, names, colors) : null),
    [index, id, names, colors])
  const navigate = useNavigate()
  const prefill = useBuilderStore((s) => s.prefillFromPhilosophy)
  const phil = philosophies.find((p) => p.id === id)
  const ownFrameworks = useMemo(() => frameworks.filter((f) => f.source_philosophy === id), [frameworks, id])

  const back = onBack && (
    <button type="button" onClick={onBack}
      className="flex items-center gap-1 text-[11px] text-muted-foreground/70 hover:text-foreground">
      <ChevronLeft className="size-3" /> All philosophies
    </button>
  )

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="size-4 animate-spin" /> Reading the package…
      </div>
    )
  }
  if (error || !doc) {
    return <div className="space-y-3 p-4">{back}<ErrorBanner error={(error as Error) ?? new Error('Not found')} /></div>
  }

  const spec = specs?.philosophies[doc.id]
  const sessionCount = Object.keys(doc.sessions).length

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-5xl space-y-8 px-4 py-4">
        {back}

        {/* What it is, and what its week is made of. */}
        <header className="space-y-3 rounded-lg border border-border/60 bg-card p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0 space-y-1">
              <h2 className="text-lg font-semibold leading-tight">{doc.name}</h2>
              <p className="text-[11px] text-muted-foreground">
                {doc.tracks.length > 1 ? `${doc.tracks.length} tracks` : doc.tracks[0]?.name}
                {doc.levels.length > 0 && ` · ${doc.levels.join(', ')}`}
                {doc.models.intensity && ` · ${doc.models.intensity.toLowerCase()}`}
                {doc.models.progression && ` · ${doc.models.progression.toLowerCase()}`}
              </p>
            </div>
            {phil && (
              <Button size="sm" onClick={() => { prefill(phil, ownFrameworks); navigate('/program/new') }}>
                <Wand2 className="mr-1.5 size-3.5" /> Build a program with this
              </Button>
            )}
          </div>
          {doc.summary && <p className="max-w-3xl text-[13px] leading-relaxed text-foreground/85">{doc.summary}</p>}
          <div className="space-y-1">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">
              A week of it{doc.tracks.length > 1 ? ', main track' : ''}
            </p>
            <ModalityMix mix={doc.mix} />
          </div>
        </header>

        <PageSection title="How it runs" hint="Each phase's week, from the days and sessions the package writes.">
          <PhilosophyTracks tracks={doc.tracks} />
        </PageSection>

        <div className="grid gap-8 lg:grid-cols-[3fr_2fr]">
          <PageSection title="What it holds true"
            hint={doc.rules.length ? 'The method’s rules, each with the passage it rests on.' : undefined}>
            <PhilosophyRules doc={doc} />
          </PageSection>
          <PageSection title="What it asks of you">
            <Asks doc={doc} expectations={doc.expectations} />
          </PageSection>
        </div>

        <PageSection title={`Its sessions (${sessionCount})`}
          hint="Grouped as the method groups them; each slot lists the exercises it can take.">
          <PhilosophySessions doc={doc} />
        </PageSection>

        {spec && specs && (
          <PhilosophyMeasuresCard spec={spec} vocabulary={specs.vocabulary} accentHex={modalityHex(doc.accent)} />
        )}

        <LineageSection lineage={lineage} emptyUp="Nothing: a philosophy is where a program starts."
          emptyDown="It runs no framework." />

        <div className="grid gap-6 border-t border-border/40 pt-4 sm:grid-cols-[3fr_2fr]">
          {doc.sources.length > 0 && (
            <div className="space-y-1">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">Sources</p>
              <ul className="space-y-0.5">
                {doc.sources.map((s) => (
                  <li key={s.id ?? s.title} className="text-[10px] text-muted-foreground">
                    {s.where?.startsWith('http')
                      ? <a href={s.where} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 hover:text-foreground hover:underline">
                          {s.title} <ExternalLink className="size-2.5" />
                        </a>
                      : s.title}
                    {s.published && <span className="text-muted-foreground/60"> ({s.published.slice(0, 4)})</span>}
                  </li>
                ))}
              </ul>
            </div>
          )}
          <SimilarItems category="philosophies" id={doc.id}
            getLabel={(pid) => philosophies.find((p) => p.id === pid)?.name ?? pid}
            onSelect={onSelect} count={4} />
        </div>
      </div>
    </div>
  )
}
