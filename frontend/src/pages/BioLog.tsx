import { motion } from 'framer-motion'
import { format, parseISO } from 'date-fns'
import { Activity, Watch } from 'lucide-react'
import { DailyCheckin } from '@/components/bio/DailyCheckin'
import { HRTrendChart } from '@/components/bio/HRTrendChart'
import { ReadinessWidget } from '@/components/bio/ReadinessWidget'
import { SleepStageChart } from '@/components/bio/SleepStageChart'
import { Separator } from '@/components/ui/separator'
import { useBioStore } from '@/store/bioStore'

function fmtDuration(minutes: number): string {
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m > 0 ? `${h}h ${m}m` : `${h}h`
}

function fmtTime(iso: string): string {
  try {
    return format(new Date(iso), 'h:mm a')
  } catch {
    return '—'
  }
}

export function BioLog() {
  const dailyBioLogs = useBioStore((s) => s.dailyBioLogs)
  const recentLogs = Object.values(dailyBioLogs)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 14)

  const hasSleepData = Object.values(dailyBioLogs).some((l) => l.sleepDurationMin != null)

  // Last night = most recent log with sleep data
  const lastSleepLog = Object.values(dailyBioLogs)
    .filter((l) => l.sleepDurationMin != null)
    .sort((a, b) => b.date.localeCompare(a.date))[0]

  return (
    <motion.div
      key="bio-log"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col overflow-hidden"
    >
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <Activity className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Bio Log</h1>
        <span className="text-muted-foreground/50 text-xs select-none">·</span>
        <span className="text-xs text-muted-foreground">Readiness · Sleep · HRV</span>
      </div>

      <div className="flex-1 overflow-y-auto p-6 space-y-6 max-w-2xl">

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <DailyCheckin />
        <ReadinessWidget />
      </div>

      <Separator />

      {/* Sleep summary card */}
      {lastSleepLog ? (
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Last Night's Sleep
          </h2>
          <div className="rounded-xl border bg-card p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-2xl font-bold tabular-nums">
                  {fmtDuration(lastSleepLog.sleepDurationMin!)}
                </span>
                {lastSleepLog.sleepStart && lastSleepLog.sleepEnd && (
                  <span className="text-xs text-muted-foreground">
                    {fmtTime(lastSleepLog.sleepStart)} → {fmtTime(lastSleepLog.sleepEnd)}
                  </span>
                )}
              </div>
              {lastSleepLog.source === 'apple_watch' && (
                <span className="flex items-center gap-1 text-[10px] text-muted-foreground border border-border rounded-full px-2 py-0.5">
                  <Watch className="size-3" /> Apple Watch
                </span>
              )}
            </div>

            {/* Stage breakdown */}
            {(lastSleepLog.deepSleepMin != null || lastSleepLog.remSleepMin != null) && (
              <div className="flex flex-wrap gap-2">
                {lastSleepLog.deepSleepMin != null && (
                  <span className="rounded-full bg-blue-900/30 text-blue-400 border border-blue-800/40 px-2.5 py-0.5 text-xs font-medium">
                    Deep {fmtDuration(lastSleepLog.deepSleepMin)}
                  </span>
                )}
                {lastSleepLog.remSleepMin != null && (
                  <span className="rounded-full bg-violet-900/30 text-violet-400 border border-violet-800/40 px-2.5 py-0.5 text-xs font-medium">
                    REM {fmtDuration(lastSleepLog.remSleepMin)}
                  </span>
                )}
                {lastSleepLog.lightSleepMin != null && (
                  <span className="rounded-full bg-sky-900/30 text-sky-400 border border-sky-800/40 px-2.5 py-0.5 text-xs font-medium">
                    Light {fmtDuration(lastSleepLog.lightSleepMin)}
                  </span>
                )}
                {lastSleepLog.awakeMins != null && lastSleepLog.awakeMins > 0 && (
                  <span className="rounded-full bg-muted text-muted-foreground border border-border px-2.5 py-0.5 text-xs font-medium">
                    Awake {fmtDuration(lastSleepLog.awakeMins)}
                  </span>
                )}
              </div>
            )}

            {/* SpO2 + respiratory rate */}
            {(lastSleepLog.spo2Avg != null || lastSleepLog.respiratoryRateAvg != null) && (
              <div className="flex gap-4 text-xs text-muted-foreground border-t border-border pt-2.5">
                {lastSleepLog.spo2Avg != null && (
                  <span>SpO₂ <span className="text-foreground font-medium">{lastSleepLog.spo2Avg.toFixed(1)}%</span></span>
                )}
                {lastSleepLog.respiratoryRateAvg != null && (
                  <span>Resp. rate <span className="text-foreground font-medium">{lastSleepLog.respiratoryRateAvg.toFixed(1)} br/min</span></span>
                )}
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="rounded-xl border border-dashed border-border p-4 flex items-center gap-3 text-sm text-muted-foreground">
          <Watch className="size-4 shrink-0" />
          <span>No sleep data yet. Sync via the iOS companion app to see sleep stages here.</span>
        </div>
      )}

      {/* Sleep stage chart */}
      {hasSleepData && (
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            30-Day Sleep Stages
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <SleepStageChart bioLogs={dailyBioLogs} days={30} />
          </div>
        </div>
      )}

      <Separator />

      {/* HR/HRV trend chart */}
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
          30-Day HR / HRV Trend
        </h2>
        <div className="rounded-xl border bg-card p-4">
          <HRTrendChart bioLogs={dailyBioLogs} days={30} />
        </div>
      </div>

      {/* History table */}
      {recentLogs.length > 0 && (
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Recent Check-ins
          </h2>
          <div className="rounded-xl border bg-card overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/30">
                  <th className="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground">Date</th>
                  <th className="px-4 py-2.5 text-center text-xs font-medium text-muted-foreground">Resting HR</th>
                  <th className="px-4 py-2.5 text-center text-xs font-medium text-muted-foreground">HRV</th>
                  <th className="px-4 py-2.5 text-center text-xs font-medium text-muted-foreground">Sleep</th>
                  <th className="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground">Notes</th>
                </tr>
              </thead>
              <tbody>
                {recentLogs.map((log) => (
                  <tr key={log.date} className="border-b last:border-0 hover:bg-muted/20 transition-colors">
                    <td className="px-4 py-2.5 text-sm">
                      {format(parseISO(log.date), 'EEE, MMM d')}
                    </td>
                    <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                      {log.restingHR != null ? (
                        <span className="text-red-400 font-medium">{log.restingHR}</span>
                      ) : (
                        <span className="text-muted-foreground/40">—</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                      {log.hrv != null ? (
                        <span className="text-sky-400 font-medium">{log.hrv}</span>
                      ) : (
                        <span className="text-muted-foreground/40">—</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                      {log.sleepDurationMin != null ? (
                        <span className="text-violet-400 font-medium">{fmtDuration(log.sleepDurationMin)}</span>
                      ) : (
                        <span className="text-muted-foreground/40">—</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-muted-foreground truncate max-w-[120px]">
                      {log.notes ?? '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
      </div>
    </motion.div>
  )
}
