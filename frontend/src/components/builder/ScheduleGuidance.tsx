interface GuidanceProps {
  ideal: {
    days: number
    longSessions: number
    shortSessions: number
    mobilitySessions: number
    totalMinutes: number
  }
  actual: {
    days: number
    longSessions: number
    shortSessions: number
    mobilitySessions: number
    totalMinutes: number
  }
  compromises: string[]
}

export function ScheduleGuidance({ ideal, actual, compromises }: GuidanceProps) {
  const compareMetric = (idealVal: number, actualVal: number) => {
    if (actualVal >= idealVal) return '✓'
    if (actualVal >= idealVal * 0.8) return '⚠️'
    return '❌'
  }

  return (
    <div className="rounded-lg border border-border/40 bg-card/40 p-4 space-y-3">
      <h3 className="text-sm font-semibold">Program Guidance</h3>

      <div className="grid grid-cols-2 gap-4 text-xs">
        <div className="space-y-1">
          <p className="text-muted-foreground font-medium">Recommended:</p>
          <ul className="space-y-0.5">
            <li>{ideal.days} training days</li>
            <li>{ideal.longSessions} long sessions (60+ min)</li>
            <li>{ideal.shortSessions} short sessions (30-45 min)</li>
            <li>{ideal.mobilitySessions} mobility sessions (15-20 min)</li>
          </ul>
        </div>

        <div className="space-y-1">
          <p className="text-muted-foreground font-medium">Your schedule:</p>
          <ul className="space-y-0.5">
            <li>
              {compareMetric(ideal.days, actual.days)} {actual.days} training days
            </li>
            <li>
              {compareMetric(ideal.longSessions, actual.longSessions)} {actual.longSessions} long
              sessions
            </li>
            <li>
              {compareMetric(ideal.shortSessions, actual.shortSessions)} {actual.shortSessions}{' '}
              short sessions
            </li>
            <li>
              {compareMetric(ideal.mobilitySessions, actual.mobilitySessions)}{' '}
              {actual.mobilitySessions} mobility sessions
            </li>
          </ul>
        </div>
      </div>

      {compromises.length > 0 && (
        <div className="pt-2 border-t border-border/30">
          <p className="text-xs font-medium text-muted-foreground mb-1">Adjustments made:</p>
          <ul className="text-xs text-muted-foreground/80 space-y-0.5">
            {compromises.map((comp, i) => (
              <li key={i}>• {comp}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
