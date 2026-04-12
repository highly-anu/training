import { useSimilarity, getTopSimilar } from '@/api/similarity'
import { cn } from '@/lib/utils'

interface SimilarItemsProps {
  category: string       // 'philosophies' | 'modalities' | 'exercises' | 'archetypes' | 'frameworks' | 'movement_patterns'
  id: string
  getLabel: (id: string) => string   // resolve display name from id
  onSelect?: (id: string) => void    // navigate to item
  count?: number
  accentHex?: string
}

function ScoreBar({ value, hex }: { value: number; hex?: string }) {
  return (
    <div className="relative h-1 w-12 rounded-full bg-muted/30 overflow-hidden shrink-0">
      <div className="absolute h-full rounded-full" style={{ width: `${value * 100}%`, backgroundColor: hex ?? '#6366f1', opacity: 0.7 }} />
    </div>
  )
}

export function SimilarItems({ category, id, getLabel, onSelect, count = 5, accentHex }: SimilarItemsProps) {
  const { data: matrix, isLoading } = useSimilarity()

  if (isLoading) return (
    <div className="space-y-1.5">
      <p className="text-[9px] uppercase tracking-wider text-muted-foreground/40 font-medium">Similar</p>
      {[...Array(3)].map((_, i) => (
        <div key={i} className="h-7 rounded bg-muted/20 animate-pulse" />
      ))}
    </div>
  )

  if (!matrix) return null

  const similar = getTopSimilar(matrix, category, id, count)
  if (similar.length === 0) return null

  return (
    <div className="space-y-1.5">
      <p className="text-[9px] uppercase tracking-wider text-muted-foreground/40 font-medium">Similar</p>
      {similar.map((item) => (
        <button
          key={item.id}
          onClick={() => onSelect?.(item.id)}
          disabled={!onSelect}
          className={cn(
            'w-full text-left rounded-md border border-border/30 bg-card/30 px-2.5 py-2 transition-colors',
            onSelect && 'hover:border-primary/30 hover:bg-muted/20 cursor-pointer',
            !onSelect && 'cursor-default',
          )}
        >
          <div className="flex items-center gap-2 min-w-0">
            <span className="text-[11px] font-medium flex-1 truncate">{getLabel(item.id)}</span>
            <div className="flex items-center gap-1.5 shrink-0">
              <ScoreBar value={item.score} hex={accentHex} />
              <span className="text-[9px] font-mono tabular-nums text-muted-foreground/50 w-7 text-right">
                {Math.round(item.score * 100)}%
              </span>
            </div>
          </div>
          <p className="text-[9px] text-muted-foreground/40 mt-0.5 truncate">{item.primary.detail}</p>
        </button>
      ))}
    </div>
  )
}
