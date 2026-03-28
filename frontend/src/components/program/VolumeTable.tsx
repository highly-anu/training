import type { WeekVolumeSummary } from '@/api/types'

interface VolumeTableProps {
  summary: WeekVolumeSummary
}

export function VolumeTable({ summary }: VolumeTableProps) {
  const stats = [
    { label: 'Strength Sets', value: String(summary.strength_sets), unit: 'sets' },
    { label: 'Conditioning', value: String(summary.cond_minutes), unit: 'min' },
    { label: 'Durability', value: String(summary.dur_minutes), unit: 'min' },
    { label: 'Mobility', value: String(summary.mob_minutes), unit: 'min' },
    { label: 'Total', value: String(summary.total_minutes), unit: 'min', highlight: true },
  ]

  return (
    <div className="flex gap-4 flex-wrap">
      {stats.map(({ label, value, unit, highlight }) => (
        <div
          key={label}
          className={`rounded-lg border px-4 py-2.5 text-center min-w-[80px] ${
            highlight ? 'border-primary/40 bg-primary/5' : 'border-border bg-card'
          }`}
        >
          <div className={`text-lg font-bold ${highlight ? 'text-primary' : 'text-foreground'}`}>
            {value}
          </div>
          <div className="text-[10px] text-muted-foreground leading-tight">{unit}</div>
          <div className="text-[10px] text-muted-foreground leading-tight">{label}</div>
        </div>
      ))}
    </div>
  )
}
