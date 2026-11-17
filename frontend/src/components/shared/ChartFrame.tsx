import type { ReactElement } from 'react'
import { ResponsiveContainer } from 'recharts'

interface ChartFrameProps {
  /** What the chart draws: "Resting heart rate, last 30 days". */
  label: string
  /** Its numbers in words, from lib/chartSummary. Without one the label stands alone. */
  summary?: string | null
  height: number
  width?: number | `${number}%`
  className?: string
  children: ReactElement
}

/**
 * The one home of a Recharts container. A chart is a picture to a screen
 * reader, so the frame is one image whose name is what the chart draws and
 * what its numbers are; the marks inside are not read one by one
 * (docs/frontend-design.md §12.11).
 */
export function ChartFrame({ label, summary, height, width = '100%', className, children }: ChartFrameProps) {
  return (
    <div role="img" aria-label={summary ? `${label}. ${summary}` : label} className={className}>
      <ResponsiveContainer width={width} height={height}>
        {children}
      </ResponsiveContainer>
    </div>
  )
}
