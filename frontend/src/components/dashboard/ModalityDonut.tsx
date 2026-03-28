import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { sortPriorities } from '@/lib/prioritySort'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { GoalPriorities } from '@/api/types'

interface ModalityDonutProps {
  priorities: GoalPriorities
}

export function ModalityDonut({ priorities }: ModalityDonutProps) {
  const sorted = sortPriorities(priorities)
  const data = sorted.map(({ modality, weight }) => ({
    name: MODALITY_COLORS[modality].label,
    value: Math.round(weight * 100),
    hex: MODALITY_COLORS[modality].hex,
  }))

  const dominant = sorted[0]

  return (
    <div className="relative flex flex-col items-center">
      <ResponsiveContainer width="100%" height={180}>
        <PieChart>
          <Pie
            data={data}
            cx="50%"
            cy="50%"
            innerRadius={54}
            outerRadius={80}
            paddingAngle={2}
            dataKey="value"
            animationBegin={200}
            animationDuration={800}
          >
            {data.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.hex} stroke="transparent" />
            ))}
          </Pie>
          <Tooltip
            contentStyle={{
              backgroundColor: 'var(--card)',
              border: '1px solid var(--border)',
              borderRadius: '8px',
              fontSize: '12px',
              color: 'var(--foreground)',
            }}
            formatter={(v, name) => [`${String(v)}%`, String(name)]}
          />
        </PieChart>
      </ResponsiveContainer>

      {/* Center label */}
      {dominant && (
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="text-lg font-bold text-foreground">
            {Math.round(dominant.weight * 100)}%
          </span>
          <span className="text-[10px] text-muted-foreground text-center max-w-[60px] leading-tight">
            {MODALITY_COLORS[dominant.modality].label}
          </span>
        </div>
      )}
    </div>
  )
}
