import type { BenchmarkStandard, BenchmarkLevel } from '@/api/types'

interface BenchmarkDetailProps {
  benchmark: BenchmarkStandard
}

const LEVELS: BenchmarkLevel[] = ['entry', 'intermediate', 'advanced', 'elite']

export function BenchmarkDetail({ benchmark: b }: BenchmarkDetailProps) {
  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">{b.name}</h2>
        <p className="text-xs text-muted-foreground font-mono mt-0.5">{b.id}</p>
      </div>

      <dl className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Category</dt>
          <dd className="mt-0.5 capitalize">{b.category}</dd>
        </div>
        {b.domain && (
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Domain</dt>
            <dd className="mt-0.5">{b.domain.replace(/_/g, ' ')}</dd>
          </div>
        )}
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Unit</dt>
          <dd className="mt-0.5 font-mono text-xs">{b.unit}</dd>
        </div>
        {b.lower_is_better != null && (
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Lower is Better</dt>
            <dd className="mt-0.5">{b.lower_is_better ? 'Yes' : 'No'}</dd>
          </div>
        )}
      </dl>

      {/* Standards table */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Standards</p>
        <table className="w-full text-xs border-collapse">
          <thead>
            <tr>
              <th className="text-left text-muted-foreground font-normal py-1 pr-3">Level</th>
              <th className="text-right text-muted-foreground font-normal py-1">Value</th>
            </tr>
          </thead>
          <tbody>
            {LEVELS.map(level => {
              const val = b.standards?.[level]
              return (
                <tr key={level} className="border-t border-border/50">
                  <td className="py-1.5 pr-3 capitalize text-muted-foreground">{level}</td>
                  <td className="py-1.5 text-right font-mono">
                    {val != null ? `${val} ${b.unit}` : '—'}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {b.notes && (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Notes</p>
          <p className="text-xs text-muted-foreground">{b.notes}</p>
        </div>
      )}
    </div>
  )
}
