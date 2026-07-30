import { useMemo } from 'react'
import { ResponsiveContainer, BarChart, Bar, XAxis, Tooltip, Cell } from 'recharts'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { computeHRZones, getEffectiveMaxHR, DEFAULT_ZONE_BOUNDARIES } from '@/lib/hrZones'
import { subDays, parseISO, isAfter } from 'date-fns'

const ZONE_COLORS = ['#94a3b8', '#38bdf8', '#fbbf24', '#f97316', '#ef4444']
const ZONE_NAMES  = ['Z1 Recovery', 'Z2 Aerobic', 'Z3 Tempo', 'Z4 Threshold', 'Z5 Max']

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ value: number; name: string; payload: { zone: string } }> }) {
  if (!active || !payload?.length) return null
  const d = payload[0]
  return (
    <div className="rounded-md border border-border bg-card px-2.5 py-1.5 text-xs shadow-md">
      <p className="font-semibold text-foreground">{d.payload.zone}</p>
      <p className="text-muted-foreground">{d.value} min</p>
    </div>
  )
}

export function WeeklyZoneSummary() {
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const dob = useProfileStore((s) => s.dateOfBirth ?? null)
  const hrConfig = useProfileStore((s) => s.hrConfig)
  const maxHR = getEffectiveMaxHR(dob, hrConfig.maxHROverride ?? undefined)
  const zoneBoundaries = hrConfig.zoneBoundaries ?? DEFAULT_ZONE_BOUNDARIES

  const { zoneMinutes, totalMinutes, aerobicPct } = useMemo(() => {
    const cutoff = subDays(new Date(), 7)
    const zoneMin = [0, 0, 0, 0, 0]
    let total = 0

    for (const w of importedWorkouts) {
      try {
        if (!isAfter(parseISO(w.date), cutoff)) continue
      } catch {
        continue
      }
      const samples = w.heartRate.samples ?? []
      if (samples.length === 0 && w.heartRate.avg == null) continue

      const zones = computeHRZones(maxHR, samples, w.heartRate.avg ?? undefined, zoneBoundaries)
      const dur = w.durationMinutes
      zoneMin[0] += (zones.z1 / 100) * dur
      zoneMin[1] += (zones.z2 / 100) * dur
      zoneMin[2] += (zones.z3 / 100) * dur
      zoneMin[3] += (zones.z4 / 100) * dur
      zoneMin[4] += (zones.z5 / 100) * dur
      total += dur
    }

    const rounded = zoneMin.map(Math.round)
    const aerobic = total > 0 ? Math.round(((rounded[0] + rounded[1]) / total) * 100) : 0
    return { zoneMinutes: rounded, totalMinutes: Math.round(total), aerobicPct: aerobic }
  }, [importedWorkouts, maxHR, zoneBoundaries])

  if (totalMinutes === 0) return null

  const chartData = ZONE_NAMES.map((zone, i) => ({ zone, minutes: zoneMinutes[i] }))

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-xs text-muted-foreground">Rolling 7-day zone distribution</p>
        <span className="text-xs font-medium">
          <span
            className={aerobicPct >= 80 ? 'text-emerald-700 dark:text-emerald-300' : aerobicPct >= 60 ? 'text-amber-700 dark:text-amber-300' : 'text-red-700 dark:text-red-300'}
          >
            {aerobicPct}% aerobic
          </span>
          <span className="text-muted-foreground ml-1.5">({totalMinutes} min total)</span>
        </span>
      </div>

      <ResponsiveContainer width="100%" height={80}>
        <BarChart data={chartData} layout="vertical" margin={{ top: 0, right: 8, left: 0, bottom: 0 }}>
          <XAxis type="number" hide />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'transparent' }} />
          <Bar dataKey="minutes" radius={[0, 3, 3, 0]} isAnimationActive={false}>
            {chartData.map((_, i) => (
              <Cell key={i} fill={ZONE_COLORS[i]} fillOpacity={zoneMinutes[i] === 0 ? 0.2 : 0.85} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>

      {/* Zone legend row */}
      <div className="flex gap-3 flex-wrap">
        {ZONE_NAMES.map((name, i) => (
          <span key={i} className="flex items-center gap-1 text-[10px] text-muted-foreground">
            <span className="inline-block size-2 rounded-sm" style={{ background: ZONE_COLORS[i] }} />
            {name.split(' ')[0]} {zoneMinutes[i]}m
          </span>
        ))}
      </div>
    </div>
  )
}
