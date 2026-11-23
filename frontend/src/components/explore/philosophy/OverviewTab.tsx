import { useState } from 'react'
import { FlaskConical, Info } from 'lucide-react'
import type { AnalyticsSpecs, PhilosophyDescription } from '@/api/types'
import { LineageSection } from '@/components/explore/LineageSection'
import { PhilosophyMeasuresCard } from '@/components/explore/PhilosophyMeasuresCard'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { SimilarItems } from '@/components/shared/SimilarItems'
import type { Lineage } from '@/lib/exploreLinks'
import { modalityLabel } from '@/lib/modalityColors'
import { InlinePanel, IntensityBar, IntensityLegend } from './Glance'

const perWeek = (n: number) => `${Number.isInteger(n) ? n : n.toFixed(1)}×`

/** A plain card of the overview: a quiet label, then what it holds. */
function Card({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-4 rounded-xl border border-border bg-card p-5" aria-label={title}>
      <div>
        <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{title}</h3>
        {note && <p className="mt-0.5 text-[11px] text-muted-foreground/80">{note}</p>}
      </div>
      {children}
    </section>
  )
}

function Label({ children }: { children: React.ReactNode }) {
  return <p className="text-[11px] font-medium text-muted-foreground">{children}</p>
}

function Chips({ items, empty = '—' }: { items: string[]; empty?: string }) {
  if (!items.length) return <span className="text-xs text-muted-foreground/60">{empty}</span>
  return (
    <div className="flex flex-wrap gap-1.5">
      {items.map((x) => (
        <span key={x} className="rounded-full border border-border/70 px-2.5 py-0.5 text-xs text-foreground/85">{x}</span>
      ))}
    </div>
  )
}

/**
 * A philosophy on one screen: the week it asks for, what it builds and how
 * that is measured, what the athlete needs, and what it sits beside. Four
 * cards and no colour but the marks'.
 */
export function OverviewTab({ doc, spec, vocabulary, lineage, nameOf, onSelect, onCompare }: {
  doc: PhilosophyDescription
  spec: AnalyticsSpecs['philosophies'][string] | undefined
  vocabulary: AnalyticsSpecs['vocabulary'] | undefined
  lineage: Lineage | null
  nameOf: (id: string) => string
  onSelect: (id: string) => void
  onCompare?: (id: string) => void
}) {
  const g = doc.glance
  const [measures, setMeasures] = useState(false)
  const [allEquipment, setAllEquipment] = useState(false)
  const primary = g.tracks.find((t) => t.id === g.primaryTrackId) ?? g.tracks[0]
  const mix = primary?.mix.length ? primary.mix : g.mix
  const intensity = primary && Object.keys(primary.intensity).length ? primary.intensity : g.intensity
  const total = mix.reduce((n, m) => n + m.perWeek, 0)
  const prereq = g.tracks.filter((t) => t.requires.length > 0 || t.implement)
  const standards = g.measures.standards
  const equipment = allEquipment ? g.equipment : g.equipment.slice(0, 10)

  return (
    <div className="space-y-4">
      <div className="grid items-start gap-4 md:grid-cols-2">
        <Card title="The week"
          note={primary && g.tracks.length > 1 ? `Of the main track, ${primary.name}` : undefined}>
          <ul className="space-y-2.5">
            {mix.map((m) => (
              <li key={m.modality} className="flex items-center gap-3 text-sm">
                <ModalityMark modality={m.modality} size="md" tile />
                <span className="min-w-0 flex-1 truncate">{modalityLabel(m.modality)}</span>
                <span className="font-mono text-xs tabular-nums text-muted-foreground">{perWeek(m.perWeek)} a week</span>
              </li>
            ))}
            {mix.length === 0 && <li className="text-xs text-muted-foreground/60">No week declared.</li>}
          </ul>
          {mix.length > 1 && (
            <p className="text-xs text-muted-foreground">
              {perWeek(Math.round(total * 10) / 10)} sessions a week in all.
            </p>
          )}
          {Object.keys(intensity).length > 0 && (
            <div className="space-y-1.5 border-t border-border/50 pt-3">
              <Label>Easy to hard</Label>
              <IntensityBar split={intensity} className="h-1.5" />
              <IntensityLegend split={intensity} />
            </div>
          )}
        </Card>

        <Card title="What it builds">
          <Chips items={(primary?.goals ?? []).slice(0, 8)} />
          <div className="space-y-2 border-t border-border/50 pt-3">
            <Label>
              Progress is {g.measures.headline
                ? <span className="text-foreground">{g.measures.headline.toLowerCase()}</span> : 'not declared'}
            </Label>
            {standards.length > 0 && (
              <ul className="space-y-1.5">
                {standards.slice(0, 6).map((s) => (
                  <li key={s.id} className="flex items-center gap-2 text-xs">
                    <ModalityMark modality={s.domain} />
                    <span className="min-w-0 flex-1 truncate">{s.name.replace(/ \(.*\)$/, '')}</span>
                    {g.tested.includes(s.name) && (
                      <span className="inline-flex shrink-0 items-center gap-1 text-[10px] text-muted-foreground">
                        <FlaskConical className="size-3" aria-hidden /> tested
                      </span>
                    )}
                  </li>
                ))}
                {standards.length > 6 && (
                  <li className="text-[11px] text-muted-foreground">and {standards.length - 6} more</li>
                )}
              </ul>
            )}
            {spec && vocabulary && (
              <button type="button" onClick={() => setMeasures((m) => !m)} aria-expanded={measures}
                className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
                <Info className="size-3.5" /> How progress is measured
              </button>
            )}
          </div>
        </Card>
      </div>

      {measures && spec && vocabulary && (
        <InlinePanel title="How progress is measured" onClose={() => setMeasures(false)}
          subtitle={g.measures.headline ? `Progress is ${g.measures.headline.toLowerCase()}` : undefined}>
          <PhilosophyMeasuresCard spec={spec} vocabulary={vocabulary} />
        </InlinePanel>
      )}

      <div className="grid items-start gap-4 md:grid-cols-2">
        <Card title="What you need">
          <div className="space-y-2">
            <Label>Equipment</Label>
            <Chips items={equipment.map((e) => e.name)} empty="None" />
            {g.equipment.length > 10 && (
              <button type="button" onClick={() => setAllEquipment((a) => !a)} aria-expanded={allEquipment}
                className="text-xs text-muted-foreground hover:text-foreground">
                {allEquipment ? 'Show fewer' : `Show all ${g.equipment.length}`}
              </button>
            )}
          </div>
          {prereq.length > 0 && (
            <div className="space-y-2 border-t border-border/50 pt-3">
              <Label>You already own</Label>
              <ul className="space-y-1.5">
                {prereq.map((t) => (
                  <li key={t.id} className="text-xs leading-relaxed text-muted-foreground">
                    <span className="text-foreground/90">{t.name}:</span>{' '}
                    {[...t.requires, ...(t.implement ? [t.implement] : [])].join(', ')}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {doc.borrows.length > 0 && (
            <p className="border-t border-border/50 pt-3 text-xs text-muted-foreground">
              Borrows from {doc.borrows.map((b) => b.label).join(', ')}.
            </p>
          )}
        </Card>

        <Card title="Most alike">
          <SimilarItems category="philosophies" id={doc.id} getLabel={nameOf} onSelect={onSelect}
            onCompare={onCompare} count={4} bare />
        </Card>
      </div>

      <LineageSection lineage={lineage} emptyUp="Nothing: a philosophy is where a program starts."
        emptyDown="It runs no framework." />
    </div>
  )
}
