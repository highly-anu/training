import type { Framework, ModalityId } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'

/** One row per modality: its name, one dot per weekly session, the count. */
export function SessionsPerWeekRows({ sessionsPerWeek, accentHex }: {
  sessionsPerWeek: Framework['sessions_per_week']; accentHex?: string
}) {
  const rows = Object.entries(sessionsPerWeek ?? {}).sort(([, a], [, b]) => (b ?? 0) - (a ?? 0))
  if (!rows.length) return null
  return (
    <div className="space-y-1.5">
      {rows.map(([mod, count]) => {
        const hex = accentHex ?? MODALITY_COLORS[mod as ModalityId]?.hex ?? '#6366f1'
        return (
          <div key={mod} className="flex items-center gap-2 text-xs">
            <span className="w-40 truncate text-muted-foreground text-[11px]">
              {MODALITY_COLORS[mod as ModalityId]?.label ?? mod.replace(/_/g, ' ')}
            </span>
            <div className="flex gap-0.5">
              {Array.from({ length: count ?? 0 }).map((_, i) => (
                <div key={i} className="size-2 rounded-full" style={{ backgroundColor: hex, opacity: 0.7 }} />
              ))}
            </div>
            <span className="font-mono text-muted-foreground text-[10px]">{count}×/wk</span>
          </div>
        )
      })}
    </div>
  )
}
