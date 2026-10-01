import { format, parseISO } from 'date-fns'
import { Activity, Watch } from 'lucide-react'
import { DailyCheckin } from '@/components/bio/DailyCheckin'
import { RHRTrendChart } from '@/components/bio/RHRTrendChart'
import { HRVTrendChart } from '@/components/bio/HRVTrendChart'
import { ReadinessWidget } from '@/components/bio/ReadinessWidget'
import { SleepStageChart } from '@/components/bio/SleepStageChart'
import { WeeklyZoneSummary } from '@/components/bio/WeeklyZoneSummary'
import { EmptyState } from '@/components/shared/EmptyState'
import { useBioStore } from '@/store/bioStore'
import type { DailyBioLog } from '@/api/types'

/**
 * Analytics ▸ Recovery — the body's side of the ledger: today's check-in and
 * readiness, last night's sleep, the 30-day HRV / resting-HR / sleep trends,
 * and the check-in history. This was the Bio Log page; its training-load
 * charts live on the Load tab now, so each chart has one home.
 */

function fmtDuration(minutes: number): string {
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}m`
  return m > 0 ? `${h}h ${m}m` : `${h}h`
}

function fmtTime(iso: string): string {
  try {
    return format(new Date(iso), 'h:mm a')
  } catch {
    return '—'
  }
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
      {children}
    </h2>
  )
}

function LastNight({ log }: { log: DailyBioLog | undefined }) {
  if (!log) {
    return (
      <div className="rounded-xl border border-dashed border-border p-4 flex items-center gap-3 text-sm text-muted-foreground">
        <Watch className="size-4 shrink-0" />
        <span>No sleep data yet. Sync via the iOS companion app to see sleep stages here.</span>
      </div>
    )
  }
  return (
    <div className="rounded-xl border bg-card p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-2xl font-bold tabular-nums">{fmtDuration(log.sleepDurationMin!)}</span>
          {log.sleepStart && log.sleepEnd && (
            <span className="text-xs text-muted-foreground">
              {fmtTime(log.sleepStart)} → {fmtTime(log.sleepEnd)}
            </span>
          )}
        </div>
        {log.source === 'apple_watch' && (
          <span className="flex items-center gap-1 text-[10px] text-muted-foreground border border-border rounded-full px-2 py-0.5">
            <Watch className="size-3" /> Apple Watch
          </span>
        )}
      </div>

      {(log.deepSleepMin != null || log.remSleepMin != null) && (
        <div className="flex flex-wrap gap-2">
          {log.deepSleepMin != null && (
            <span className="rounded-full bg-blue-900/30 text-blue-700 dark:text-blue-300 border border-blue-800/40 px-2.5 py-0.5 text-xs font-medium">
              Deep {fmtDuration(log.deepSleepMin)}
            </span>
          )}
          {log.remSleepMin != null && (
            <span className="rounded-full bg-violet-900/30 text-violet-700 dark:text-violet-300 border border-violet-800/40 px-2.5 py-0.5 text-xs font-medium">
              REM {fmtDuration(log.remSleepMin)}
            </span>
          )}
          {log.lightSleepMin != null && (
            <span className="rounded-full bg-sky-900/30 text-sky-700 dark:text-sky-300 border border-sky-800/40 px-2.5 py-0.5 text-xs font-medium">
              Light {fmtDuration(log.lightSleepMin)}
            </span>
          )}
          {log.awakeMins != null && log.awakeMins > 0 && (
            <span className="rounded-full bg-muted text-muted-foreground border border-border px-2.5 py-0.5 text-xs font-medium">
              Awake {fmtDuration(log.awakeMins)}
            </span>
          )}
        </div>
      )}

      {(log.spo2Avg != null || log.respiratoryRateAvg != null) && (
        <div className="flex gap-4 text-xs text-muted-foreground border-t border-border pt-2.5">
          {log.spo2Avg != null && (
            <span>SpO₂ <span className="text-foreground font-medium">{log.spo2Avg.toFixed(1)}%</span></span>
          )}
          {log.respiratoryRateAvg != null && (
            <span>Resp. rate <span className="text-foreground font-medium">{log.respiratoryRateAvg.toFixed(1)} br/min</span></span>
          )}
        </div>
      )}
    </div>
  )
}

function CheckinHistory({ logs }: { logs: DailyBioLog[] }) {
  if (logs.length === 0) {
    return (
      <EmptyState
        icon={<Activity className="size-8 opacity-40" />}
        title="No check-ins yet"
        description="Log resting HR, HRV and sleep above, or let the iOS app sync them from Apple Watch."
      />
    )
  }
  return (
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
          {logs.map((log) => (
            <tr key={log.date} className="border-b last:border-0 hover:bg-muted/20 transition-colors">
              <td className="px-4 py-2.5 text-sm">{format(parseISO(log.date), 'EEE, MMM d')}</td>
              <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                {log.restingHR != null
                  ? <span className="text-red-700 dark:text-red-300 font-medium">{log.restingHR}</span>
                  : <span className="text-muted-foreground/40">—</span>}
              </td>
              <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                {log.hrv != null
                  ? <span className="text-sky-700 dark:text-sky-300 font-medium">{log.hrv}</span>
                  : <span className="text-muted-foreground/40">—</span>}
              </td>
              <td className="px-4 py-2.5 text-center text-sm tabular-nums">
                {log.sleepDurationMin != null
                  ? <span className="text-violet-700 dark:text-violet-300 font-medium">{fmtDuration(log.sleepDurationMin)}</span>
                  : <span className="text-muted-foreground/40">—</span>}
              </td>
              <td className="px-4 py-2.5 text-xs text-muted-foreground truncate max-w-[120px]">{log.notes ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function RecoveryTab() {
  const dailyBioLogs = useBioStore((s) => s.dailyBioLogs)
  const all = Object.values(dailyBioLogs)
  const recentLogs = all.slice().sort((a, b) => b.date.localeCompare(a.date)).slice(0, 30)
  const hasSleepData = all.some((l) => l.sleepDurationMin != null)
  const lastSleepLog = all
    .filter((l) => l.sleepDurationMin != null)
    .sort((a, b) => b.date.localeCompare(a.date))[0]

  return (
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-10">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <DailyCheckin />
        <ReadinessWidget />
      </div>

      <div>
        <SectionTitle>Last Night's Sleep</SectionTitle>
        <LastNight log={lastSleepLog} />
      </div>

      {hasSleepData && (
        <div>
          <SectionTitle>30-Day Sleep Stages</SectionTitle>
          <div className="rounded-xl border bg-card p-4">
            <SleepStageChart bioLogs={dailyBioLogs} days={30} />
          </div>
        </div>
      )}

      <div>
        <SectionTitle>Weekly Zone Distribution</SectionTitle>
        <div className="rounded-xl border bg-card p-4">
          <WeeklyZoneSummary />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        <div>
          <SectionTitle>30-Day Resting HR</SectionTitle>
          <div className="rounded-xl border bg-card p-4">
            <RHRTrendChart bioLogs={dailyBioLogs} days={30} />
          </div>
        </div>
        <div>
          <SectionTitle>30-Day HRV</SectionTitle>
          <div className="rounded-xl border bg-card p-4">
            <HRVTrendChart bioLogs={dailyBioLogs} days={30} />
          </div>
        </div>
      </div>

      <div>
        <SectionTitle>Recent Check-ins</SectionTitle>
        <CheckinHistory logs={recentLogs} />
      </div>
    </div>
  )
}
