import { useParams } from 'react-router-dom'
import { useShare, type ShareDocument } from '@/api/shares'
import { ShareLayout } from '@/components/share/ShareLayout'
import { SharedMethod } from '@/components/share/SharedMethod'
import { SharedProgram } from '@/components/share/SharedProgram'
import { SharedSession } from '@/components/share/SharedSession'
import { FailedState, LoadingState } from '@/components/shared/states'
import { useAuthStore } from '@/store/authStore'

const KIND = { session: 'Session', package: 'Method', program: 'Program' } as const

/**
 * Where a shared link lands: `<web>/s/<token>` (docs/roadmap.md item 25).
 * Outside the sidebar and outside sign-in — whoever has the link reads it.
 */
export function SharedLink() {
  const { token } = useParams()
  const viewer = useAuthStore((s) => s.user?.id)
  const share = useShare(token, viewer)
  const status = (share.error as { status?: number } | null)?.status

  if (share.isLoading) {
    return <ShareLayout><LoadingState shape="cards" count={3} label="Opening the link" /></ShareLayout>
  }
  if (!share.data) {
    return (
      <ShareLayout>
        {status === 404 ? (
          <div className="space-y-1.5 py-10 text-center">
            <p className="text-sm font-medium">This link is no longer shared</p>
            <p className="text-xs text-muted-foreground">Whoever sent it removed it, or the address is incomplete.</p>
          </div>
        ) : (
          <FailedState title="The link could not be opened" error={share.error} onRetry={() => void share.refetch()} />
        )}
      </ShareLayout>
    )
  }
  const doc = share.data
  return (
    <ShareLayout token={doc.token} kind={KIND[doc.kind]} title={doc.title} wide={doc.kind === 'package'}>
      <Body doc={doc} />
    </ShareLayout>
  )
}

function Body({ doc }: { doc: ShareDocument }) {
  if (doc.kind === 'session' && doc.session) return <SharedSession doc={doc.session} />
  if (doc.kind === 'program' && doc.program) return <SharedProgram doc={doc} />
  if (doc.kind === 'package' && doc.method) return <SharedMethod doc={doc} />
  return <p className="text-sm text-muted-foreground">This link has nothing this version of the page can show.</p>
}
