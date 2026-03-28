import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import type { WeekVolumeSummary } from '@/api/types'

interface VolumeBarProps {
  summaries: WeekVolumeSummary[]
}

export function VolumeBar({ summaries }: VolumeBarProps) {
  const data = summaries.slice(0, 8).map((s) => ({
    week: `W${s.week_number}`,
    Strength: Math.round((s.strength_sets * 4) / 60), // rough min estimate
    Conditioning: s.cond_minutes,
    Durability: s.dur_minutes,
    Mobility: s.mob_minutes,
  }))

  return (
    <ResponsiveContainer width="100%" height={160}>
      <BarChart data={data} barSize={8} barGap={2}>
        <XAxis dataKey="week" tick={{ fontSize: 10, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fontSize: 10, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} width={28} />
        <Tooltip
          cursor={{ fill: '#888', fillOpacity: 0.08 }}
          contentStyle={{
            backgroundColor: 'var(--card)',
            border: '1px solid var(--border)',
            borderRadius: '8px',
            fontSize: '11px',
          }}
          formatter={(v) => [`${String(v)} min`]}
        />
        <Legend iconType="circle" iconSize={6} wrapperStyle={{ fontSize: 10 }} />
        <Bar dataKey="Conditioning" fill="#0ea5e9" radius={[3, 3, 0, 0]} />
        <Bar dataKey="Durability" fill="#f59e0b" radius={[3, 3, 0, 0]} />
        <Bar dataKey="Strength" fill="#ef4444" radius={[3, 3, 0, 0]} />
        <Bar dataKey="Mobility" fill="#10b981" radius={[3, 3, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  )
}
