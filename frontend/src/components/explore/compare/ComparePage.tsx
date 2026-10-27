import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronLeft, FlaskConical, Loader2, Plus, Wand2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useSimilarity } from '@/api/similarity'
import { usePhilosophyCompare } from '@/api/philosophyCompare'
import { useBuilderStore } from '@/store/builderStore'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { philosophyHex } from '@/lib/exploreColors'
import { cn } from '@/lib/utils'
import type { CompareGlance, CompareRow, CompareSplit, CompareStandard, PhilosophyCompare } from '@/api/types'
import { IntensityBar, LevelPips, MixLegend, ModalityGlyph, PhaseBar } from '../philosophy/Glance'
import { ModalityMix } from '../philosophy/ModalityMix'
import { ForYouSection } from './ForYouSection'
import { Cell, Row, SectionTitle, WideLine } from './CompareGrid'
import { MAX_COMPARE, gridStyle, nearestTo } from './compareIds'

const range = (r: { min: number; ideal: number } | null, unit = '') =>
  !r ? '—' : r.min === r.ideal ? `${r.ideal}${unit}` : `${r.min}–${r.ideal}${unit}`

function Chip({ children, hex, title }: { children: React.ReactNode; hex?: string; title?: string }) {
  return (
    <span title={title} style={hex ? { borderLeftColor: hex, borderLeftWidth: 2 } : undefined}
      className="inline-flex max-w-full items-center gap-1 rounded-full border border-border/50 bg-card/60 px-2 py-0.5 text-[11px] text-muted-foreground">
      {children}
    </span>
  )
}

/** A split row's cell: what this column holds alone, then what it shares with
 *  one other (named), each drawn by `render`. */
function SplitCell<T>({ split, id, names, render, keyOf }: {
  split: CompareSplit<T>; id: string; names: Record<string, string>
  render: (item: T) => React.ReactNode; keyOf: (item: T) => string
}) {
  const own = split.only[id] ?? []
  const some = split.some.filter((s) => s.ids.includes(id))
  if (!own.length && !some.length) return <span className="text-[11px] text-muted-foreground/50">—</span>
  return (
    <div className="flex flex-wrap gap-1">
      {own.map((x) => <span key={keyOf(x)}>{render(x)}</span>)}
      {some.map((s) => (
        <span key={keyOf(s.item)} title={`Also ${s.ids.filter((x) => x !== id).map((x) => names[x]).join(', ')}`}
          className="opacity-80">{render(s.item)}</span>
      ))}
    </div>
  )
}

function SharedLine<T>({ items, render, keyOf, n }: {
  items: T[]; render: (item: T) => React.ReactNode; keyOf: (item: T) => string; n: number
}) {
  if (!items.length) return null
  return (
    <WideLine className="flex flex-wrap items-center gap-1">
      <span className="mr-1 text-[10px] uppercase tracking-wider text-muted-foreground/70">
        {n === 2 ? 'Both' : 'All three'}
      </span>
      {items.map((x) => <span key={keyOf(x)}>{render(x)}</span>)}
    </WideLine>
  )
}

const standardChip = (s: CompareStandard) => (
  <Chip hex={modalityHex(s.domain)} title={s.name}>
    <ModalityGlyph modality={s.domain} className="size-3" />
    <span className="truncate">{s.name.replace(/ \(.*\)$/, '')}</span>
    {(s.tested || (s.testedBy?.length ?? 0) > 0) && <FlaskConical className="size-3" aria-label="tested" />}
  </Chip>
)

/** The column header: name, track, remove, build. */
function ColumnHead({ g, trackId, onTrack, onRemove, onOpen, onBuild }: {
  g: CompareGlance; trackId: string; onTrack: (id: string) => void
  onRemove?: () => void; onOpen: () => void; onBuild?: () => void
}) {
  return (
    <div className="min-w-0 space-y-1.5 rounded-md border border-border/50 bg-card/60 p-2"
      style={{ borderTopColor: philosophyHex(g.bias), borderTopWidth: 2 }}>
      <div className="flex items-start gap-1">
        <button type="button" onClick={onOpen} className="min-w-0 flex-1 text-left text-xs font-semibold leading-snug hover:text-primary">
          {g.name}
        </button>
        {onRemove && (
          <button type="button" onClick={onRemove} aria-label={`Remove ${g.name}`}
            className="rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground">
            <X className="size-3.5" />
          </button>
        )}
      </div>
      {g.tracks.length > 1 && (
        <select value={trackId} onChange={(e) => onTrack(e.target.value)} aria-label={`${g.name} track`}
          className="w-full rounded border border-border/60 bg-background px-1.5 py-0.5 text-[11px]">
          {g.tracks.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
      )}
      {onBuild && (
        <Button size="sm" variant="outline" className="h-6 w-full text-[11px]" onClick={onBuild}>
          <Wand2 className="mr-1 size-3" /> Build with this
        </Button>
      )}
    </div>
  )
}

/**
 * Explore ▸ Philosophies ▸ Compare: two or three philosophies as columns of
 * the same rows (frontend-design §13.9). Every value is the server's — the
 * glances, what they share and what only one has, how alike each pair is
 * (GET /philosophies/compare) — and the For you rows are each one generated
 * on the athlete's profile (POST /philosophies/<id>/for-me).
 */
export function ComparePage({ ids, onChange, onOpen, onBack }: {
  ids: string[]
  onChange: (ids: string[]) => void
  onOpen: (id: string) => void
  onBack: () => void
}) {
  const { data: doc, isLoading, error } = usePhilosophyCompare(ids)
  const { data: philosophies = [] } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: matrix } = useSimilarity()
  const prefill = useBuilderStore((s) => s.prefillFromPhilosophy)
  const setTrack = useBuilderStore((s) => s.setTrack)
  const navigate = useNavigate()
  const [onlyDiff, setOnlyDiff] = useState(false)
  const [tracks, setTracks] = useState<Record<string, string>>({})

  const names = useMemo(() => Object.fromEntries((doc?.philosophies ?? []).map((g) => [g.id, g.name])), [doc])
  const candidates = useMemo(
    () => nearestTo(ids, philosophies.map((p) => p.id), matrix?.['philosophies'])
      .map((id) => philosophies.find((p) => p.id === id)!).filter(Boolean),
    [ids, philosophies, matrix])

  const back = (
    <button type="button" onClick={onBack}
      className="flex items-center gap-1 text-[11px] text-muted-foreground/70 hover:text-foreground">
      <ChevronLeft className="size-3" /> All philosophies
    </button>
  )
  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="size-4 animate-spin" /> Setting them side by side…
      </div>
    )
  }
  if (error || !doc) {
    return <div className="space-y-3 p-4">{back}<ErrorBanner error={(error as Error) ?? new Error('Not found')} /></div>
  }

  const cols = doc.philosophies
  const n = cols.length
  const trackOf = (g: CompareGlance) => tracks[g.id] ?? g.primaryTrackId ?? g.tracks[0]?.id ?? ''
  const hide = (row: CompareRow) => onlyDiff && doc.same[row]
  const build = (g: CompareGlance) => {
    const phil = philosophies.find((p) => p.id === g.id)
    if (!phil) return undefined
    return () => {
      prefill(phil, frameworks.filter((f) => f.source_philosophy === g.id))
      setTrack(trackOf(g))
      navigate('/program/new')
    }
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-6xl space-y-4 px-4 py-4">
        {back}
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div className="space-y-1">
            <p className="text-[10px] font-medium uppercase tracking-widest text-muted-foreground/50">Compare</p>
            <h2 className="text-lg font-semibold leading-tight">{cols.map((g) => g.name.replace(/ \(.*\)$/, '')).join(' · ')}</h2>
          </div>
          <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
            <Switch checked={onlyDiff} onCheckedChange={setOnlyDiff} aria-label="Only differences" />
            Only differences
          </label>
        </div>

        <div className="overflow-x-auto">
          <div className="grid gap-x-3" style={gridStyle(n)}>
            {/* Column heads */}
            <div className="sticky left-0 z-10 bg-background">
              {n < MAX_COMPARE && candidates.length > 0 && (
                <label className="flex flex-col gap-1 text-[10px] text-muted-foreground">
                  <span className="flex items-center gap-1"><Plus className="size-3" /> Add</span>
                  <select value="" onChange={(e) => e.target.value && onChange([...ids, e.target.value])}
                    aria-label="Add a philosophy"
                    className="w-full rounded border border-border/60 bg-background px-1.5 py-0.5 text-[11px]">
                    <option value="">Choose…</option>
                    {candidates.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </label>
              )}
            </div>
            {cols.map((g) => (
              <ColumnHead key={g.id} g={g} trackId={trackOf(g)} onTrack={(t) => setTracks((s) => ({ ...s, [g.id]: t }))}
                onOpen={() => onOpen(g.id)} onBuild={build(g)}
                onRemove={n > 2 ? () => onChange(ids.filter((x) => x !== g.id)) : undefined} />
            ))}

            <SectionTitle>At a glance</SectionTitle>
            <Row label="Weeks" same={doc.same.weeks} hidden={hide('weeks')}>
              {cols.map((g) => <Cell key={g.id} className="font-mono tabular-nums">{range(g.weeks)}</Cell>)}
            </Row>
            <Row label="Days a week" same={doc.same.daysPerWeek} hidden={hide('daysPerWeek')}>
              {cols.map((g) => <Cell key={g.id} className="font-mono tabular-nums">{range(g.daysPerWeek)}</Cell>)}
            </Row>
            <Row label="A session" same={doc.same.sessionMinutes} hidden={hide('sessionMinutes')}>
              {cols.map((g) => (
                <Cell key={g.id} className="font-mono tabular-nums">
                  {range(g.sessionMinutes, '′')}
                  {g.longSessionMinutes ? <span className="text-muted-foreground"> · long {g.longSessionMinutes}′</span> : null}
                </Cell>
              ))}
            </Row>
            <Row label="Level" same={doc.same.levels} hidden={hide('levels')}>
              {cols.map((g) => <Cell key={g.id}><LevelPips levels={g.levels} /></Cell>)}
            </Row>

            <SectionTitle>Shape</SectionTitle>
            <Row label="Fingerprint" same={doc.same.mix} hidden={hide('mix')}>
              {cols.map((g) => (
                <Cell key={g.id} className="space-y-1.5">
                  <ModalityMix mix={g.mix} legend={false} />
                  <MixLegend mix={g.mix} />
                </Cell>
              ))}
            </Row>
            {!onlyDiff && <SharedLine n={n} items={doc.bias.shared} keyOf={(m) => m}
              render={(m) => <Chip hex={modalityHex(m)}><ModalityGlyph modality={m} className="size-3" />{modalityLabel(m)}</Chip>} />}
            <Row label="Leans toward">
              {cols.map((g) => (
                <Cell key={g.id}>
                  <SplitCell split={doc.bias} id={g.id} names={names} keyOf={(m) => m}
                    render={(m) => <Chip hex={modalityHex(m)}><ModalityGlyph modality={m} className="size-3" />{modalityLabel(m)}</Chip>} />
                </Cell>
              ))}
            </Row>
            <Row label="Easy → hard" same={doc.same.intensity} hidden={hide('intensity')}>
              {cols.map((g) => (
                <Cell key={g.id}>
                  {Object.keys(g.intensity).length ? <IntensityBar split={g.intensity} className="h-1.5" />
                    : <span className="text-[11px] text-muted-foreground/50">Not declared</span>}
                </Cell>
              ))}
            </Row>
            <Row label="Intensity model" same={doc.same.intensityModel} hidden={hide('intensityModel')}>
              {cols.map((g) => <Cell key={g.id}>{g.models.intensity ?? '—'}</Cell>)}
            </Row>
            <Row label="Progression" same={doc.same.progression} hidden={hide('progression')}>
              {cols.map((g) => <Cell key={g.id}>{g.models.progression ?? '—'}</Cell>)}
            </Row>

            <SectionTitle>Tracks & phases</SectionTitle>
            <Row label={`On one scale (${doc.scale.trackWeeks} wk)`} same={doc.same.tracks} hidden={hide('tracks')}>
              {cols.map((g) => (
                <Cell key={g.id} className="space-y-1.5">
                  {g.tracks.map((t) => (
                    <div key={t.id} className={cn('space-y-0.5', t.id !== trackOf(g) && 'opacity-50')}>
                      <div className="flex justify-between gap-2 text-[10px] text-muted-foreground">
                        <span className="truncate">{t.name}</span>
                        <span className="font-mono">{t.weeks} wk{t.repeatable ? ' ↻' : ''}</span>
                      </div>
                      <PhaseBar phases={t.phases} scaleWeeks={doc.scale.trackWeeks} height="h-2" />
                    </div>
                  ))}
                </Cell>
              ))}
            </Row>

            <SectionTitle>Progress</SectionTitle>
            <Row label="Progress is" same={doc.same.headline} hidden={hide('headline')}>
              {cols.map((g) => <Cell key={g.id}>{g.measures.headline ?? '—'}</Cell>)}
            </Row>
            {!onlyDiff && <SharedLine n={n} items={doc.standards.shared} keyOf={(s) => s.name} render={standardChip} />}
            <Row label="Standards">
              {cols.map((g) => (
                <Cell key={g.id}>
                  <SplitCell split={doc.standards} id={g.id} names={names} keyOf={(s) => s.name} render={standardChip} />
                </Cell>
              ))}
            </Row>

            <SectionTitle>Requirements</SectionTitle>
            {!onlyDiff && <SharedLine n={n} items={doc.equipment.shared} keyOf={(e) => e.id} render={(e) => <Chip>{e.name}</Chip>} />}
            <Row label="Equipment">
              {cols.map((g) => (
                <Cell key={g.id}>
                  {g.equipment.length === 0
                    ? <span className="text-[11px] text-muted-foreground/60">None</span>
                    : <SplitCell split={doc.equipment} id={g.id} names={names} keyOf={(e) => e.id}
                        render={(e) => <Chip>{e.name}</Chip>} />}
                </Cell>
              ))}
            </Row>
            <Row label="You already own">
              {cols.map((g) => {
                const t = g.tracks.find((x) => x.id === trackOf(g))
                const asks = [...(t?.requires ?? []), ...(t?.kettlebellPair ? ['a pair of bells'] : [])]
                return <Cell key={g.id} className="text-[11px] text-muted-foreground">{asks.length ? asks.join(', ') : '—'}</Cell>
              })}
            </Row>

            <ForYouSection cols={cols} trackOf={trackOf} />
          </div>
        </div>

        <Likeness doc={doc} names={names} />
      </div>
    </div>
  )
}

/** How alike each pair is, in the landing's likeness score and its reasons. */
function Likeness({ doc, names }: { doc: PhilosophyCompare; names: Record<string, string> }) {
  const short = (id: string) => (names[id] ?? id).replace(/ \(.*\)$/, '').replace(/ \/.*$/, '')
  return (
    <section className="space-y-2 border-t border-border/40 pt-4">
      <h3 className="text-sm font-semibold">How alike</h3>
      <ul className="space-y-1.5">
        {doc.pairs.map((p) => (
          <li key={`${p.a}-${p.b}`} className="flex flex-wrap items-center gap-2 text-[11px]">
            <span className="w-56 truncate">{short(p.a)} · {short(p.b)}</span>
            <span className="relative h-1 w-16 overflow-hidden rounded-full bg-muted/40">
              <span className="absolute h-full rounded-full bg-foreground/60" style={{ width: `${p.score * 100}%` }} />
            </span>
            <span className="w-8 font-mono tabular-nums text-muted-foreground">{Math.round(p.score * 100)}%</span>
            <span className="text-muted-foreground">{p.primary.detail}; {p.secondary.detail}</span>
          </li>
        ))}
      </ul>
    </section>
  )
}
