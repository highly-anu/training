import { useNavigate } from 'react-router-dom'
import { Page } from '@/components/layout/Page'
import { Compass } from 'lucide-react'
import { EmptyState } from '@/components/shared/EmptyState'

export function NotFound() {
  const navigate = useNavigate()
  return (
    <Page
      key="not-found"
      className="flex h-full items-center justify-center p-6"
    >
      <EmptyState
        title="Page not found"
        description="Nothing lives at this address. Old links to the builder, imports and the bio log redirect; anything else lands here."
        action={{ label: 'Go home', onClick: () => navigate('/') }}
        icon={<Compass className="size-10" />}
        className="max-w-md"
      />
    </Page>
  )
}
