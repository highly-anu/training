import { Network } from 'lucide-react'
import { CrossRefBadge } from '../CrossRefBadge'
import type { Philosophy } from '@/api/types'
import type { NavigateToFn, OpenInOntologyFn } from '../types'

interface PhilosophyDetailProps {
  philosophy: Philosophy
  navigateTo: NavigateToFn
  onOpenInOntology?: OpenInOntologyFn
}

function Pills({ items }: { items: string[] }) {
  if (!items?.length) return <span className="text-sm text-muted-foreground">—</span>
  return (
    <div className="flex flex-wrap gap-1">
      {items.map(item => (
        <span key={item} className="px-2 py-0.5 rounded text-xs bg-muted border border-border font-mono">
          {item}
        </span>
      ))}
    </div>
  )
}

export function PhilosophyDetail({ philosophy: p, navigateTo, onOpenInOntology }: PhilosophyDetailProps) {
  const connections = (p as { system_connections?: { frameworks: string[]; goals: string[] } }).system_connections

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">{p.name}</h2>
          <p className="text-xs text-muted-foreground font-mono mt-0.5">{p.id}</p>
        </div>
        {onOpenInOntology && (
          <button
            onClick={() => onOpenInOntology(`philosophy::${p.id}`)}
            className="shrink-0 flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
          >
            <Network className="size-3" />
            Ontology
          </button>
        )}
      </div>

      {/* Core principles */}
      {p.core_principles?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Core Principles</p>
          <ul className="space-y-1">
            {p.core_principles.map((pr, i) => (
              <li key={i} className="text-xs flex gap-2">
                <span className="text-muted-foreground shrink-0">·</span>
                <span>{pr.replace(/_/g, ' ')}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {/* Scope & Bias */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Scope</p>
        <Pills items={p.scope ?? []} />
      </div>
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Bias</p>
        <Pills items={p.bias ?? []} />
      </div>

      {/* Models */}
      {(p as { intensity_model?: string }).intensity_model && (
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Intensity Model</dt>
            <dd className="mt-0.5 font-mono text-xs">{(p as { intensity_model?: string }).intensity_model}</dd>
          </div>
          {(p as { progression_philosophy?: string }).progression_philosophy && (
            <div>
              <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Progression</dt>
              <dd className="mt-0.5 font-mono text-xs">{(p as { progression_philosophy?: string }).progression_philosophy}</dd>
            </div>
          )}
        </dl>
      )}

      {/* Avoid with */}
      {p.avoid_with?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Avoid With</p>
          <div className="flex flex-wrap gap-1">
            {p.avoid_with.map(id => (
              <CrossRefBadge key={id} label={id} type="philosophies" id={id} navigateTo={navigateTo} />
            ))}
          </div>
        </div>
      ) : null}

      {/* System connections */}
      {connections && (
        <div className="space-y-3 pt-2 border-t">
          <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">System Connections</p>

          {connections.frameworks?.length ? (
            <div>
              <p className="text-xs text-muted-foreground mb-1">Frameworks using this philosophy</p>
              <div className="flex flex-wrap gap-1">
                {connections.frameworks.map(id => (
                  <CrossRefBadge key={id} label={id} type="frameworks" id={id} navigateTo={navigateTo} />
                ))}
              </div>
            </div>
          ) : null}

        </div>
      )}
    </div>
  )
}
