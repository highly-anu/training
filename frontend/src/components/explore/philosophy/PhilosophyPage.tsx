import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  BookOpen, CalendarDays, CalendarRange, ChevronLeft, CircleHelp, ExternalLink, FlaskConical, GitBranch, Info,
  Library, Loader2, Package, Sparkles, Target, Timer, Wand2,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useAnalyticsSpecs } from '@/api/analyticsSpecs'
import { usePhilosophyDescription } from '@/api/philosophyDescription'
import { useBuilderStore } from '@/store/builderStore'
import { PhilosophyMeasuresCard } from '@/components/explore/PhilosophyMeasuresCard'
import { LineageSection } from '@/components/explore/LineageSection'
import { useLinkIndex } from '@/components/explore/useLineage'
import { SimilarItems } from '@/components/shared/SimilarItems'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { lineageOf } from '@/lib/exploreLinks'
import { modalityHex } from '@/lib/modalityColors'
import type { PhilosophyDescription } from '@/api/types'
import { ModalityMix } from './ModalityMix'
import { InlinePanel, IntensityBar, LevelPips, MixLegend, ModalityGlyph, StatTile } from './Glance'
import { PhilosophyTracks } from './PhilosophyTracks'
import { PhilosophyRules } from './PhilosophyRules'
import { PhilosophySessions } from './PhilosophySessions'

type MethodPanel = 'rules' | 'sources' | 'inventions' | 'open' | null

function PageSection({ title, icon: Icon, children, action }: {
  title: string; icon?: React.ComponentType<{ className?: string }>; children: React.ReactNode; action?: React.ReactNode
}) {
  return (
    <section className="space-y-2.5">
      <div className="flex items-center justify-between gap-2">
        <h3 className="flex items-center gap-1.5 text-sm font-semibold">
          {Icon && <Icon className="size-4 text-muted-foreground" />}{title}
        </h3>
        {action}
      </div>
      {children}
    </section>
  )
}

const range = (r: { min: number; ideal: number } | null, unit = '') =>
  !r ? '—' : r.min === r.ideal ? `${r.ideal}${unit}` : `${r.min}–${r.ideal}${unit}`

function Chip({ children, hex, onClick, title }: {
  children: React.ReactNode; hex?: string; onClick?: () => void; title?: string
}) {
  const cls = 'inline-flex max-w-full items-center gap-1 rounded-full border border-border/50 bg-card/60 px-2 py-0.5 text-[11px] text-muted-foreground'
  const style = hex ? { borderLeftColor: hex, borderLeftWidth: 2 } : undefined
  return onClick
    ? <button type="button" onClick={onClick} title={title} className={`${cls} hover:border-primary/40 hover:text-foreground`} style={style}>{children}</button>
    : <span title={title} className={cls} style={style}>{children}</span>
}

/** Goals: what the main track builds, and the standards that measure it. */
function Goals({ doc, measuresOpen, onMeasures }: { doc: PhilosophyDescription; measuresOpen: boolean; onMeasures: () => void }) {
  const g = doc.glance
  const primary = g.tracks.find((t) => t.id === g.primaryTrackId) ?? g.tracks[0]
  const standards = g.measures.standards
  return (
    <div className="space-y-3 rounded-lg border border-border/50 bg-card/40 p-3">
      <div className="space-y-1.5">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">Builds</p>
        <div className="flex flex-wrap gap-1">
          {(primary?.goals ?? []).slice(0, 8).map((x) => <Chip key={x}>{x}</Chip>)}
          {!primary?.goals.length && <span className="text-[11px] text-muted-foreground/60">—</span>}
        </div>
      </div>
      <div className="space-y-1.5">
        <p className="flex items-center gap-1 text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">
          <Target className="size-3" /> Progress is {g.measures.headline ? <span className="normal-case tracking-normal text-foreground/90">{g.measures.headline.toLowerCase()}</span> : '—'}
        </p>
        {standards.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {standards.slice(0, 6).map((s) => (
              <Chip key={s.id} hex={modalityHex(s.domain)} onClick={onMeasures} title={s.name}>
                <ModalityGlyph modality={s.domain} className="size-3" />
                <span className="truncate">{s.name.replace(/ \(.*\)$/, '')}</span>
                {g.tested.includes(s.name) && <FlaskConical className="size-3" />}
              </Chip>
            ))}
            {standards.length > 6 && <Chip onClick={onMeasures}>+{standards.length - 6}</Chip>}
          </div>
        )}
        <button type="button" onClick={onMeasures} aria-expanded={measuresOpen}
          className={`inline-flex items-center gap-1 text-[11px] hover:text-foreground ${measuresOpen ? 'text-foreground' : 'text-muted-foreground'}`}>
          <Info className="size-3" /> How progress is measured
        </button>
      </div>
    </div>
  )
}

/** Requirements: what the athlete needs — equipment, movements already
 *  owned per track, a pair of bells. */
function Requirements({ doc }: { doc: PhilosophyDescription }) {
  const g = doc.glance
  const [allEquipment, setAllEquipment] = useState(false)
  const prereq = g.tracks.filter((t) => t.requires.length > 0 || t.kettlebellPair)
  return (
    <div className="space-y-3 rounded-lg border border-border/50 bg-card/40 p-3">
      <div className="space-y-1.5">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">Equipment</p>
        <div className="flex flex-wrap gap-1">
          {(allEquipment ? g.equipment : g.equipment.slice(0, 8)).map((e) => <Chip key={e.id}>{e.name}</Chip>)}
          {g.equipment.length > 8 && (
            <Chip onClick={() => setAllEquipment((a) => !a)}>{allEquipment ? 'fewer' : `+${g.equipment.length - 8}`}</Chip>
          )}
          {!g.equipment.length && <span className="text-[11px] text-muted-foreground/60">None</span>}
        </div>
      </div>
      {prereq.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">You already own</p>
          <ul className="space-y-1">
            {prereq.map((t) => (
              <li key={t.id} className="text-[11px] text-muted-foreground">
                <span className="text-foreground/80">{t.name}:</span> {[...t.requires, ...(t.kettlebellPair ? ['a pair of bells'] : [])].join(', ')}
              </li>
            ))}
          </ul>
        </div>
      )}
      {doc.borrows.length > 0 && (
        <p className="text-[11px] text-muted-foreground">Borrows from {doc.borrows.map((b) => b.label).join(', ')}.</p>
      )}
    </div>
  )
}

/**
 * Explore ▸ Philosophies' detail, glance first: what a reader takes in without
 * reading — spec tiles, the modality fingerprint, every track and its phases
 * as bars and week glyphs, goals and requirements as chips — and the words on
 * demand, opened in place under what was clicked. Every number comes from the server's `glance`
 * (GET /philosophies/<id>/describe), the same keys for every philosophy, so a
 * comparison can set two side by side.
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
  const [about, setAbout] = useState(false)
  const [measures, setMeasures] = useState(false)
  const [method, setMethod] = useState<MethodPanel>(null)
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

  const g = doc.glance
  const spec = specs?.philosophies[doc.id]
  const primary = g.tracks.find((t) => t.id === g.primaryTrackId) ?? g.tracks[0]
  const phaseCount = g.tracks.reduce((n, t) => n + t.phases.length, 0)
  const toggleMethod = (m: Exclude<MethodPanel, null>) => setMethod((cur) => (cur === m ? null : m))

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-5xl space-y-7 px-4 py-4">
        {back}

        <header className="space-y-3 rounded-lg border border-border/60 bg-card p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="flex min-w-0 items-center gap-3">
              <div className="flex shrink-0 -space-x-1">
                {g.bias.slice(0, 3).map((m) => (
                  <span key={m} className="flex size-8 items-center justify-center rounded-full border-2 border-card"
                    style={{ backgroundColor: `${modalityHex(m)}26` }}>
                    <ModalityGlyph modality={m} className="size-4" />
                  </span>
                ))}
              </div>
              <h2 className="text-lg font-semibold leading-tight">{doc.name}</h2>
            </div>
            <div className="flex items-center gap-2">
              <Button size="sm" variant={about ? 'secondary' : 'outline'} aria-expanded={about} onClick={() => setAbout((a) => !a)}>
                <Info className="mr-1.5 size-3.5" /> About
              </Button>
              {phil && (
                <Button size="sm" onClick={() => { prefill(phil, ownFrameworks); navigate('/program/new') }}>
                  <Wand2 className="mr-1.5 size-3.5" /> Build a program
                </Button>
              )}
            </div>
          </div>

          {about && (
            <InlinePanel title="About" subtitle={doc.name} onClose={() => setAbout(false)}>
              <div className="max-w-3xl space-y-3">
                {doc.summary && <p className="text-xs leading-relaxed text-foreground/85">{doc.summary}</p>}
                {(doc.models.intensity || doc.models.progression) && (
                  <p className="text-[11px] text-muted-foreground">
                    {doc.models.intensity && <>Intensity: {doc.models.intensity.toLowerCase()}. </>}
                    {doc.models.progression && <>Progression: {doc.models.progression.toLowerCase()}.</>}
                  </p>
                )}
                {doc.borrows.map((b) => (
                  <p key={b.package} className="text-[11px] text-muted-foreground">
                    <span className="text-foreground/90">Borrows from {b.label}.</span> {b.reason}
                  </p>
                ))}
              </div>
            </InlinePanel>
          )}
          <div className="grid gap-1.5 grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))]">
            <StatTile icon={CalendarRange} value={range(g.weeks)} label="weeks" />
            <StatTile icon={CalendarDays} value={range(g.daysPerWeek)} label="days a week" />
            <StatTile icon={Timer} value={range(g.sessionMinutes, '′')} label="a session"
              title={g.longSessionMinutes ? `Long session ${g.longSessionMinutes} min` : undefined} />
            <StatTile icon={Target} label="level"><LevelPips levels={g.levels} /></StatTile>
            <StatTile icon={Package} value={g.equipment.length} label="equipment"
              title={g.equipment.map((e) => e.name).join(', ')} />
            <StatTile icon={GitBranch} value={`${g.counts.tracks} · ${phaseCount}`} label="tracks · phases" />
          </div>

          <div className="space-y-1.5">
            <ModalityMix mix={g.mix} legend={false} />
            <div className="flex flex-wrap items-center justify-between gap-2">
              <MixLegend mix={g.mix} />
              {Object.keys(g.intensity).length > 0 && (
                <div className="flex items-center gap-1.5" title="Easy → hard, by heart-rate zone">
                  <span className="text-[9px] text-muted-foreground">easy</span>
                  <IntensityBar split={g.intensity} className="w-24" />
                  <span className="text-[9px] text-muted-foreground">hard</span>
                </div>
              )}
            </div>
          </div>
          {primary && g.tracks.length > 1 && (
            <p className="text-[10px] text-muted-foreground/70">Mix and intensity of the main track, {primary.name}.</p>
          )}
        </header>

        <PageSection title="Tracks & phases" icon={GitBranch}>
          <PhilosophyTracks doc={doc} />
        </PageSection>

        <div className="grid gap-4 md:grid-cols-2">
          <PageSection title="Goals" icon={Target}>
            <Goals doc={doc} measuresOpen={measures} onMeasures={() => setMeasures((m) => !m)} />
          </PageSection>
          <PageSection title="Requirements" icon={Package}>
            <Requirements doc={doc} />
          </PageSection>
        </div>
        {measures && spec && specs && (
          <InlinePanel title="How progress is measured" subtitle={g.measures.headline ? `Progress is ${g.measures.headline.toLowerCase()}` : undefined}
            accent={modalityHex(doc.accent)} onClose={() => setMeasures(false)}>
            <PhilosophyMeasuresCard spec={spec} vocabulary={specs.vocabulary} accentHex={modalityHex(doc.accent)} />
          </InlinePanel>
        )}

        <PageSection title="The method" icon={BookOpen}>
          <div className="grid gap-1.5 grid-cols-[repeat(auto-fill,minmax(10rem,1fr))]">
            <StatTile icon={BookOpen} value={g.counts.rules || doc.principles.length}
              label={g.counts.rules ? 'rules from the source' : 'principles'}
              active={method === 'rules'} onClick={() => toggleMethod('rules')} />
            <StatTile icon={Library} value={g.counts.sources} label="sources"
              active={method === 'sources'} onClick={() => toggleMethod('sources')} />
            <StatTile icon={Sparkles} value={g.counts.inventions} label="app decisions"
              active={method === 'inventions'} onClick={() => toggleMethod('inventions')} />
            <StatTile icon={CircleHelp} value={g.counts.open} label="not modelled yet"
              active={method === 'open'} onClick={() => toggleMethod('open')} />
          </div>
          {method && (
            <InlinePanel key={method} onClose={() => setMethod(null)}
              title={{ rules: g.counts.rules ? 'What it holds true' : 'Core principles', sources: 'Sources',
                inventions: 'Where the app decides', open: 'Not modelled yet' }[method]}
              subtitle={{ rules: g.counts.rules ? 'The method’s rules, each with the passage it rests on.' : undefined,
                sources: undefined, inventions: 'What the sources leave open and the app had to settle.',
                open: 'What the package does not program yet.' }[method]}>
              {method === 'sources'
                ? (
                  <ul className="max-w-3xl space-y-1">
                    {doc.sources.map((s) => (
                      <li key={s.id ?? s.title} className="text-[11px] text-muted-foreground">
                        {s.where?.startsWith('http')
                          ? <a href={s.where} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 hover:text-foreground hover:underline">
                              {s.title} <ExternalLink className="size-2.5" />
                            </a>
                          : s.title}
                        {s.published && <span className="text-muted-foreground/60"> ({s.published.slice(0, 4)})</span>}
                      </li>
                    ))}
                  </ul>
                )
                : <PhilosophyRules doc={doc} show={method} />}
            </InlinePanel>
          )}
        </PageSection>

        <PageSection title={`Sessions (${g.counts.sessions})`} icon={Package}>
          <PhilosophySessions doc={doc} />
        </PageSection>

        <div className="grid gap-6 border-t border-border/40 pt-4 md:grid-cols-[3fr_2fr]">
          <LineageSection lineage={lineage} emptyUp="Nothing: a philosophy is where a program starts."
            emptyDown="It runs no framework." />
          <SimilarItems category="philosophies" id={doc.id}
            getLabel={(pid) => philosophies.find((p) => p.id === pid)?.name ?? pid}
            onSelect={onSelect} count={4} />
        </div>
      </div>
    </div>
  )
}
