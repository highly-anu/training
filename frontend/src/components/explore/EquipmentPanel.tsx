import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ArrowUpRight } from 'lucide-react'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { Section } from '@/components/explore/ExploreSection'
import { TOPIC_ICONS, useExploreNavigate } from '@/components/explore/topics'
import { useLinkIndex } from '@/components/explore/useLineage'
import { useExploreLinks } from '@/api/exploreLinks'
import { useEquipmentProfiles } from '@/api/constraints'
import { EQUIPMENT_GROUPS, equipmentLabel } from '@/lib/equipment'
import {
  FACETS, explore, indexEquipment, unlocks, type Facet, type FacetItem, type Picked, type Unlock,
} from '@/lib/equipmentExplorer'
import { cn } from '@/lib/utils'

// Explore ▸ Equipment: pick equipment, see what it enables, narrow by picking
// results (lib/equipmentExplorer.ts). The state is the URL —
// ?topic=equipment&eq=…&show=…&m=…&f=…&v=…&x=… — replaced on every change, so
// filtering leaves no history, while ↗ pushes the item's detail and Back
// returns here as it was.

const FACET_LABEL: Record<Facet, string> = {
  modalities: 'Modalities', frameworks: 'Frameworks', movements: 'Movements', exercises: 'Exercises',
}
const FACET_PARAM: Record<Facet, string> = { modalities: 'm', frameworks: 'f', movements: 'v', exercises: 'x' }
const COLLAPSED = 40

const list = (v: string | null) => (v ? v.split(',').filter(Boolean) : [])

function useExplorerState() {
  const [params, setParams] = useSearchParams()
  const key = params.toString()
  // Read once per URL, so the lists are recomputed only when it changes.
  const { equipment, show, picked } = useMemo(() => {
    const p = new URLSearchParams(key)
    const showParam = p.get('show')
    return {
      equipment: list(p.get('eq')),
      show: showParam === null ? [...FACETS] : FACETS.filter((f) => list(showParam).includes(f)),
      picked: Object.fromEntries(FACETS.map((f) => [f, list(p.get(FACET_PARAM[f]))])) as Picked,
    }
  }, [key])
  function write(next: { equipment?: string[]; show?: Facet[]; picked?: Picked }) {
    const eq = next.equipment ?? equipment
    const sh = next.show ?? show
    const pk = next.picked ?? picked
    const p: Record<string, string> = { topic: 'equipment' }
    if (eq.length) p.eq = eq.join(',')
    if (sh.length !== FACETS.length) p.show = sh.join(',')
    for (const f of FACETS) if (pk[f].length) p[FACET_PARAM[f]] = pk[f].join(',')
    setParams(p, { replace: true })
  }
  return { equipment, show, picked, write }
}

const toggle = (xs: string[], x: string) => (xs.includes(x) ? xs.filter((y) => y !== x) : [...xs, x])

/** The Explore filter chip (ExerciseLanding's `${hex}30` / `${hex}15` tints),
 *  mixed so it takes a theme variable as well as a hex. */
const tint = (color: string, pct: number) => `color-mix(in srgb, ${color} ${pct}%, transparent)`
function chipStyle(color: string, on: boolean) {
  return on
    ? { backgroundColor: tint(color, 19), color, border: `1px solid ${tint(color, 38)}` }
    : { backgroundColor: tint(color, 8), color, border: `1px solid ${tint(color, 19)}`, opacity: 0.7 }
}

const PRIMARY = 'var(--primary)'

function unlockTitle(u: Unlock | undefined) {
  if (!u || u.total === 0) return 'Adds nothing to these lists'
  return FACETS.filter((f) => u.byFacet[f] > 0)
    .map((f) => `+${u.byFacet[f]} ${FACET_LABEL[f].toLowerCase()}`).join(' · ')
}

function EquipmentChips({ selected, used, unlock, onToggle }: {
  selected: Set<string>
  used: Set<string>
  unlock: Record<string, Unlock>
  onToggle: (id: string) => void
}) {
  return (
    <div className="space-y-3">
      {EQUIPMENT_GROUPS.map((g) => (
        <div key={g.name} className="space-y-1.5">
          <p className="text-[10px] text-muted-foreground/60">{g.name}</p>
          <div className="flex flex-wrap gap-2">
            {g.items.map(({ id, label }) => {
              const on = selected.has(id)
              const usable = used.has(id)
              const u = unlock[id]
              return (
                <button
                  key={id}
                  type="button"
                  disabled={!usable}
                  onClick={() => onToggle(id)}
                  title={usable ? (on ? 'Selected' : unlockTitle(u)) : 'Nothing in the library needs it'}
                  className={cn('flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-mono transition-all',
                    !usable && 'cursor-not-allowed')}
                  style={usable ? chipStyle(PRIMARY, on) : { border: '1px dashed var(--border)', opacity: 0.35 }}
                >
                  <div className="size-1.5 rounded-full" style={{ backgroundColor: usable ? PRIMARY : 'var(--muted-foreground)' }} />
                  {label}
                  {!on && usable && u && u.total > 0 && <span className="opacity-70">+{u.total}</span>}
                </button>
              )
            })}
          </div>
        </div>
      ))}
    </div>
  )
}

function ResultChip({ item, facet, onPick }: { item: FacetItem; facet: Facet; onPick: () => void }) {
  const open = useExploreNavigate()
  const color = item.color ?? '#6366f1'
  const dim = item.partial || item.unmatched || item.unavailable
  const why = item.unavailable ? 'not enabled' : item.unmatched ? 'no match' : item.note
  return (
    <span
      className={cn('inline-flex max-w-full items-center rounded-full text-[10px] font-mono transition-all', dim && !item.picked && 'opacity-50')}
      style={chipStyle(color, item.picked)}
    >
      <button type="button" onClick={onPick} aria-pressed={item.picked}
        className="flex min-w-0 items-center gap-1.5 py-1 pl-2.5 pr-1.5">
        <div className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: color }} />
        <span className="truncate">{item.name}</span>
        {why && <span className="shrink-0 opacity-60">{why}</span>}
      </button>
      <button type="button" onClick={() => open(facet, item.id)} aria-label={`Open ${item.name}`}
        className="shrink-0 rounded-full py-1 pl-0.5 pr-2 opacity-60 hover:opacity-100">
        <ArrowUpRight className="size-3" />
      </button>
    </span>
  )
}

function FacetList({ facet, items, onPick, onClear }: {
  facet: Facet
  items: FacetItem[]
  onPick: (id: string) => void
  onClear: () => void
}) {
  const [all, setAll] = useState(false)
  const Icon = TOPIC_ICONS[facet]
  const shown = all ? items : items.slice(0, COLLAPSED)
  const count = items.filter((i) => !i.unavailable && !i.unmatched).length
  const anyPicked = items.some((i) => i.picked)
  return (
    <div className="rounded-lg border border-border/40 bg-card/30 p-3 space-y-2">
      <div className="flex items-center gap-2">
        <Icon className="size-3 text-muted-foreground/60" />
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium flex-1">
          {FACET_LABEL[facet]} <span className="font-mono text-muted-foreground/40">{count}</span>
        </p>
        {anyPicked && (
          <button type="button" onClick={onClear} className="text-[10px] text-muted-foreground/50 hover:text-foreground transition-colors">
            Clear
          </button>
        )}
      </div>
      {items.length === 0
        ? <p className="text-[10px] text-muted-foreground/60">Nothing with this equipment and these picks.</p>
        : (
          <div className="flex flex-wrap gap-1.5">
            {shown.map((item) => <ResultChip key={item.id} item={item} facet={facet} onPick={() => onPick(item.id)} />)}
            {items.length > COLLAPSED && (
              <button type="button" onClick={() => setAll(!all)}
                className="px-2 py-0.5 text-[10px] text-muted-foreground/60 hover:text-foreground transition-colors">
                {all ? 'Show fewer' : `Show all ${items.length}`}
              </button>
            )}
          </div>
        )}
    </div>
  )
}

export function EquipmentPanel() {
  const { data: links, isLoading, error } = useExploreLinks()
  const { data: profiles = [] } = useEquipmentProfiles()
  const { names, colors } = useLinkIndex()
  const { equipment, show, picked, write } = useExplorerState()

  const ix = useMemo(() => (links ? indexEquipment(links) : null), [links])
  const eqSet = useMemo(() => new Set(equipment), [equipment])
  const lists = useMemo(() => (ix ? explore(ix, eqSet, picked, names, colors) : null),
    [ix, eqSet, picked, names, colors])
  const unlock = useMemo(() => (ix ? unlocks(ix, eqSet, picked) : {}), [ix, eqSet, picked])

  if (isLoading) return <div className="p-6"><LoadingCard /></div>
  if (error) return <div className="p-6"><ErrorBanner error={error as Error} /></div>
  if (!ix || !lists) return null

  // Every piece of equipment the engine knows; an unknown id from a profile is dropped.
  const known = new Set(ix.vocabulary)
  const applyProfile = (eq: string[]) => write({ equipment: eq.filter((e) => known.has(e) && e !== 'open_space') })

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-5xl mx-auto px-8 py-12 space-y-8">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">Training ontology</p>
          <h2 className="text-2xl font-semibold leading-snug">What your equipment enables.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-xl">
            Pick what you have, read what it opens up — by the generator's own rule: an exercise or a session needs
            every piece it lists, open space is assumed. Pick results to narrow the other lists; +N on a piece is
            what adding it would open.
          </p>
        </div>

        <Section label="Equipment">
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-[10px] text-muted-foreground/60">Start from</span>
              {profiles.map((p) => (
                <button key={p.id} type="button" onClick={() => applyProfile(p.equipment)}
                  className="px-2.5 py-1 rounded text-[11px] border border-border/40 text-muted-foreground hover:bg-muted/40 transition-colors">
                  {p.name}
                </button>
              ))}
              {equipment.length > 0 && (
                <button type="button" onClick={() => write({ equipment: [] })}
                  className="text-[10px] text-muted-foreground/50 hover:text-foreground transition-colors">
                  Clear
                </button>
              )}
            </div>
            <EquipmentChips
              selected={eqSet}
              used={ix.used}
              unlock={unlock}
              onToggle={(id) => write({ equipment: toggle(equipment, id) })}
            />
            <p className="text-[10px] text-muted-foreground/60">
              {equipment.length
                ? `${equipment.length} selected: ${equipment.map(equipmentLabel).join(', ')}.`
                : 'Nothing selected: what bodyweight and open space alone enable.'}
            </p>
          </div>
        </Section>

        <Section label="Show">
          <div className="flex flex-wrap gap-2">
            {FACETS.map((f) => {
              const on = show.includes(f)
              const Icon = TOPIC_ICONS[f]
              return (
                <button key={f} type="button" aria-pressed={on}
                  onClick={() => write({ show: on ? show.filter((s) => s !== f) : FACETS.filter((x) => x === f || show.includes(x)) })}
                  className="flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-mono transition-all"
                  style={chipStyle(PRIMARY, on)}>
                  <Icon className="size-3" />
                  {FACET_LABEL[f]} · {lists[f].filter((i) => !i.unavailable && !i.unmatched).length}
                </button>
              )
            })}
          </div>
        </Section>

        <div className="grid gap-3 lg:grid-cols-2 items-start">
          {show.map((f) => (
            <FacetList
              key={f}
              facet={f}
              items={lists[f]}
              onPick={(id) => write({ picked: { ...picked, [f]: toggle(picked[f], id) } })}
              onClear={() => write({ picked: { ...picked, [f]: [] } })}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
