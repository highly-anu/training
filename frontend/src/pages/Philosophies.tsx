import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { BookOpen } from 'lucide-react'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import { PhilosophyExplorerPanel } from '@/components/devlab/PhilosophyExplorerPanel'
import type { Philosophy, ModalityId } from '@/api/types'

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

// ─── Overview (nothing selected) ─────────────────────────────────────────────

function PhilosophyOverview({ philosophies, frameworks }: {
  philosophies: Philosophy[]
  frameworks: { source_philosophy?: string; sessions_per_week?: Record<string, number> }[]
}) {
  // Aggregate modality exposure across all philosophies
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

  // Per-philosophy: primary bias + framework count
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

        {/* Headline */}
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
            Each philosophy encodes a distinct theory of adaptation — how to stress, recover, and progress. Select one to explore its frameworks, modality profile, archetypes, and exercise vocabulary.
          </p>
        </div>

        {/* Modality spectrum bar */}
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

        {/* Philosophy grid — colour-coded dots */}
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

// ─── Page ─────────────────────────────────────────────────────────────────────

export function Philosophies() {
  const { data: philosophies = [], isLoading, error } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const [selected, setSelected] = useState<Philosophy | null>(null)

  return (
    <motion.div
      key="philosophies"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <BookOpen className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Philosophies</h1>
      </div>

      {/* Body */}
      {isLoading ? (
        <div className="flex-1 p-6"><LoadingCard /></div>
      ) : error ? (
        <div className="flex-1 p-6"><ErrorBanner error={error as Error} /></div>
      ) : (
        <div className="flex flex-1 min-h-0">
          {/* Left: slim philosophy list */}
          <div className="shrink-0 overflow-y-auto border-r p-3 space-y-1.5" style={{ width: 272 }}>
            {philosophies.map((phil) => (
              <PhilCard
                key={phil.id}
                phil={phil}
                isSelected={selected?.id === phil.id}
                onSelect={setSelected}
              />
            ))}
          </div>

          {/* Right: overview or explorer */}
          <div className="flex-1 min-h-0 overflow-hidden">
            {selected
              ? <PhilosophyExplorerPanel controlledId={selected.id} />
              : <PhilosophyOverview philosophies={philosophies} frameworks={frameworks} />
            }
          </div>
        </div>
      )}
    </motion.div>
  )
}
