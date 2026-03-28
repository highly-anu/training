import { AlertCircle } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'

interface ErrorBannerProps {
  error: Error | null | undefined
  title?: string
}

export function ErrorBanner({ error, title = 'Something went wrong' }: ErrorBannerProps) {
  if (!error) return null

  return (
    <Alert variant="destructive">
      <AlertCircle className="size-4" />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{error.message}</AlertDescription>
    </Alert>
  )
}
