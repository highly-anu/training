import { Info } from 'lucide-react'
import type { AnalyticsCoverage } from '@/api/types'
import { COVERAGE_REASONS } from './status'

/**
 * "Not measurable yet — and here is why." A methodology whose currency is not
 * being captured gets this instead of an empty chart. Coverage is the share of
 * completed in-scope sessions that produced the metric.
 */
export function CoverageNotice({ coverage }: { coverage: AnalyticsCoverage }) {
  if (coverage.inScope === 0) {
    return (
      <p className="text-xs text-muted-foreground">No completed sessions in scope yet.</p>
    )
  }
  if (coverage.measured === 0) {
    return (
      <div className="flex items-start gap-2 rounded-md border border-dashed border-border bg-muted/30 p-3">
        <Info className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
        <div className="text-xs">
          <p className="font-medium text-foreground">Not measurable yet</p>
          <p className="text-muted-foreground">
            {(coverage.reason && COVERAGE_REASONS[coverage.reason]) ?? 'Nothing logged for this metric yet.'}
          </p>
        </div>
      </div>
    )
  }
  if (coverage.pct < 100) {
    return (
      <p className="text-[11px] text-muted-foreground">
        Measured on {coverage.measured} of {coverage.inScope} completed sessions ({coverage.pct}%).
      </p>
    )
  }
  return null
}
