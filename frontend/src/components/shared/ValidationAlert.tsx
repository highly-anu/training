import { AlertTriangle, Info, XCircle } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import type { ValidationResult } from '@/api/types'

interface ValidationAlertProps {
  validation: ValidationResult
}

export function ValidationAlert({ validation }: ValidationAlertProps) {
  if (!validation.errors.length && !validation.warnings.length) return null

  return (
    <div className="space-y-2">
      {validation.errors.map((err, i) => (
        <Alert key={i} variant="destructive">
          <XCircle className="size-4" />
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>
            {err.message}
            {err.suggested_fix && (
              <p className="mt-1 text-xs opacity-80">Fix: {err.suggested_fix}</p>
            )}
          </AlertDescription>
        </Alert>
      ))}
      {validation.warnings.map((warn, i) => (
        <Alert key={i}>
          <AlertTriangle className="size-4 text-amber-500" />
          <AlertTitle>Warning</AlertTitle>
          <AlertDescription>
            {warn.message}
            {warn.suggested_fix && (
              <p className="mt-1 text-xs text-muted-foreground">Fix: {warn.suggested_fix}</p>
            )}
          </AlertDescription>
        </Alert>
      ))}
      {validation.info.map((item, i) => (
        <Alert key={i}>
          <Info className="size-4" />
          <AlertDescription>{item.message}</AlertDescription>
        </Alert>
      ))}
    </div>
  )
}
