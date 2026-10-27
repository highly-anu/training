import type { DescribedMix } from '@/api/types'
import { modalityHex as hex, modalityLabel as label } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'

const perWeek = (n: number) => `${Number.isInteger(n) ? n : n.toFixed(1)}×/wk`

/**
 * A philosophy's fingerprint: its week's sessions as a strip of modality
 * colours, each as wide as its share (frontend-design §8.1 — the same colours
 * as the Program calendar's session cards). The server weighs a track's phases
 * by their weeks; the strip only draws it.
 */
export function ModalityMix({ mix, legend = true, className }: {
  mix: DescribedMix[]; legend?: boolean; className?: string
}) {
  if (!mix.length) return null
  return (
    <div className={cn('space-y-1.5', className)}>
      <div className="flex h-2 w-full overflow-hidden rounded-full bg-muted gap-px" role="img"
        aria-label={mix.map((m) => `${label(m.modality)} ${Math.round(m.share * 100)}%`).join(', ')}>
        {mix.map((m) => (
          <div key={m.modality} style={{ width: `${m.share * 100}%`, backgroundColor: hex(m.modality) }}
            title={`${label(m.modality)}: ${perWeek(m.perWeek)}`} />
        ))}
      </div>
      {legend && (
        <div className="flex flex-wrap gap-x-3 gap-y-0.5">
          {mix.map((m) => (
            <span key={m.modality} className="flex items-center gap-1 text-[10px] text-muted-foreground">
              <span className="size-1.5 rounded-full" style={{ backgroundColor: hex(m.modality) }} />
              {label(m.modality)} <span className="font-mono text-muted-foreground/70">{perWeek(m.perWeek)}</span>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

