import { motion } from 'framer-motion'
import { format, parseISO } from 'date-fns'
import { DailyCheckin } from '@/components/bio/DailyCheckin'
import { HRTrendChart } from '@/components/bio/HRTrendChart'
import { ReadinessWidget } from '@/components/bio/ReadinessWidget'
import { Separator } from '@/components/ui/separator'
import { useBioStore } from '@/store/bioStore'

export function BioLog() {
  const dailyBioLogs = useBioStore((s) => s.dailyBioLogs)
  const recentLogs = Object.values(dailyBioLogs)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 14)

  return (
    <motion.div
      key="bio-log"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="h-full overflow-y-auto p-6 space-y-6 max-w-2xl"
    >
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Bio Log</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Track resting heart rate and HRV for daily readiness scoring.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {/* Check-in form */}
        <DailyCheckin />

        {/* Readiness widget */}
        <ReadinessWidget />
      </div>

      <Separator />

      {/* Trend chart */}
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
          30-Day Trend
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
                    <td className="px-4 py-2.5 text-xs text-muted-foreground truncate max-w-[160px]">
                      {log.notes ?? '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </motion.div>
  )
}
