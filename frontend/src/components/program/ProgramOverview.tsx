import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { PHASE_COLORS } from '@/lib/phaseColors'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend, ReferenceArea,
} from 'recharts'
import type { GeneratedProgram } from '@/api/types'
import type { PhaseSegment } from '@/hooks/usePhaseCalendar'

const VOL_CATEGORIES = [
  { id: 'Strength',     color: '#ef4444' },
  { id: 'Conditioning', color: '#0ea5e9' },
  { id: 'Durability',   color: '#f59e0b' },
  { id: 'Mobility',     color: '#10b981' },
] as const

interface ProgramOverviewProps {
  program: GeneratedProgram
  segments: PhaseSegment[]
}

export function ProgramOverview({ program, segments }: ProgramOverviewProps) {
  const { goal, volume_summary, minimum_prerequisites } = program as GeneratedProgram & {
    minimum_prerequisites?: Record<string, number>
  }

  const chartData = (volume_summary ?? []).map((s) => ({
    week: `W${s.week_number}`,
    Strength:     Math.round((s.strength_sets * 4) / 60),
    Conditioning: s.cond_minutes,
    Durability:   s.dur_minutes,
    Mobility:     s.mob_minutes,
  }))

  const prerequisites = (goal.minimum_prerequisites ?? {}) as Record<string, number>

  return (
    <div className="p-6 space-y-8">

      {/* 1. Program rationale */}
      {goal.notes && (
        <div>
          <h2 className="text-sm font-semibold mb-2">About this Program</h2>
          <p className="text-sm text-muted-foreground leading-relaxed">{goal.notes}</p>
          {goal.primary_sources.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mt-3">
              {goal.primary_sources.map((src) => (
                <Badge key={src} variant="secondary" className="text-xs">{src}</Badge>
              ))}
            </div>
          )}
        </div>
      )}

      {/* 2. Phase cards */}
      {segments.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-3">Training Phases</h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {segments.map((seg) => {
              const colors = PHASE_COLORS[seg.phase]

              const phaseWeeks = (volume_summary ?? []).filter(
                (s) => s.week_number >= seg.startWeek && s.week_number <= seg.endWeek
              )
              const volData = [
                { ...VOL_CATEGORIES[0], minutes: phaseWeeks.reduce((sum, s) => sum + Math.round((s.strength_sets * 4) / 60), 0) },
                { ...VOL_CATEGORIES[1], minutes: phaseWeeks.reduce((sum, s) => sum + s.cond_minutes, 0) },
                { ...VOL_CATEGORIES[2], minutes: phaseWeeks.reduce((sum, s) => sum + s.dur_minutes, 0) },
                { ...VOL_CATEGORIES[3], minutes: phaseWeeks.reduce((sum, s) => sum + s.mob_minutes, 0) },
              ].filter(({ minutes }) => minutes > 0)
              const totalMinutes = volData.reduce((sum, { minutes }) => sum + minutes, 0)

              return (
                <div key={seg.phase + seg.startWeek} className="rounded-xl border bg-card p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className={cn(
                      'text-xs font-semibold px-2 py-0.5 rounded-full',
                      colors.bg, colors.text
                    )}>
                      {colors.label}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {seg.startWeek === seg.endWeek
                        ? `Week ${seg.startWeek}`
                        : `Weeks ${seg.startWeek}–${seg.endWeek}`}
                    </span>
                  </div>

                  <p className="text-xs text-muted-foreground leading-relaxed">{seg.focus}</p>

                  {volData.length > 0 && (
                    <div className="space-y-1.5">
                      <div className="flex h-1.5 w-full overflow-hidden rounded-full bg-muted">
                        {volData.map(({ id, color, minutes }) => (
                          <div
                            key={id}
                            style={{ width: `${(minutes / totalMinutes) * 100}%`, backgroundColor: color }}
                          />
                        ))}
                      </div>
                      <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                        {volData.map(({ id, color }) => (
                          <span key={id} className="text-[10px] text-muted-foreground flex items-center gap-1">
                            <span className="inline-block size-1.5 rounded-full shrink-0" style={{ backgroundColor: color }} />
                            {id}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* 3. Volume progression chart */}
      {chartData.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-3">Volume Progression</h2>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={chartData} barSize={6} barGap={1} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
              <XAxis
                dataKey="week"
                tick={{ fontSize: 9, fill: 'var(--muted-foreground)' }}
                axisLine={false}
                tickLine={false}
                interval={chartData.length > 12 ? Math.floor(chartData.length / 12) : 0}
              />
              <YAxis
                tick={{ fontSize: 9, fill: 'var(--muted-foreground)' }}
                axisLine={false}
                tickLine={false}
                width={24}
              />
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

              {segments.map((seg) => (
                <ReferenceArea
                  key={seg.phase + seg.startWeek}
                  x1={`W${seg.startWeek}`}
                  x2={`W${seg.endWeek}`}
                  fill={PHASE_COLORS[seg.phase]?.hex}
                  fillOpacity={0.06}
                  stroke={PHASE_COLORS[seg.phase]?.hex}
                  strokeOpacity={0.25}
                  label={{ value: PHASE_COLORS[seg.phase]?.label, position: 'insideTopLeft', fontSize: 8, fill: PHASE_COLORS[seg.phase]?.hex, opacity: 0.7 }}
                />
              ))}

              <Bar dataKey="Conditioning" fill="#0ea5e9" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Durability"   fill="#f59e0b" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Strength"     fill="#ef4444" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Mobility"     fill="#10b981" radius={[2, 2, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* 4. Entry standards */}
      {Object.keys(prerequisites).length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-1">Entry Standards</h2>
          <p className="text-xs text-muted-foreground mb-3">
            Minimum benchmarks recommended before starting this program.
          </p>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {Object.entries(prerequisites).map(([key, val]) => (
              <div key={key} className="rounded-lg border bg-muted/30 px-3 py-2">
                <div className="text-[10px] text-muted-foreground capitalize">
                  {key.replace(/_/g, ' ')}
                </div>
                <div className="text-sm font-semibold">{val}</div>
              </div>
            ))}
          </div>
        </div>
      )}

    </div>
  )
}
