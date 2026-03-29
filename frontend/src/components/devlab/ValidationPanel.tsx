import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import type { ValidationResult } from '@/api/types'

interface Props {
  validation: ValidationResult
}

export function ValidationPanel({ validation }: Props) {
  const allChecks = [
    ...validation.errors.map(v => ({ ...v, level: 'error' as const })),
    ...validation.warnings.map(v => ({ ...v, level: 'warning' as const })),
    ...validation.info.map(v => ({ ...v, level: 'info' as const })),
  ]

  return (
    <div className="space-y-4 max-w-2xl">
      <div className="flex items-center gap-2 flex-wrap">
        <Badge variant={validation.feasible ? 'default' : 'destructive'}>
          {validation.feasible ? 'Feasible' : 'Infeasible'}
        </Badge>
        <span className="text-xs text-muted-foreground">
          {validation.errors.length} errors · {validation.warnings.length} warnings · {validation.info.length} info
        </span>
      </div>

      {allChecks.length === 0 ? (
        <p className="text-sm text-muted-foreground">All checks passed.</p>
      ) : (
        <div className="space-y-2">
          {allChecks.map((check, i) => (
            <Card key={i}>
              <CardContent className="flex items-start gap-3 px-4 py-3">
                <Badge
                  variant={
                    check.level === 'error'
                      ? 'destructive'
                      : check.level === 'warning'
                        ? 'outline'
                        : 'secondary'
                  }
                  className="shrink-0 mt-0.5"
                >
                  {check.level.toUpperCase()}
                </Badge>
                <div className="min-w-0">
                  <p className="text-xs font-mono text-muted-foreground">{check.code}</p>
                  <p className="text-sm mt-0.5">{check.message}</p>
                  {check.suggested_fix && (
                    <p className="text-xs text-primary mt-1">Fix: {check.suggested_fix}</p>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
