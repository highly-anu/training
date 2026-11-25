import { useParams } from 'react-router-dom'
import { useShare, type ShareDocument } from '@/api/shares'
import { ShareLayout } from '@/components/share/ShareLayout'
import { SharedSession } from '@/components/share/SharedSession'
import { FailedState, LoadingState } from '@/components/shared/states'

const KIND = { session: 'Session', package: 'Method', program: 'Program' } as const

/**
 * Where a shared link lands: `<web>/s/<token>` (docs/roadmap.md item 25).
 * Outside the sidebar and outside sign-in — whoever has the link reads it.
 */
export function SharedLink() {
  const { token } = useParams()
  const share = useShare(token)
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
    <ShareLayout token={doc.token} kind={KIND[doc.kind]} title={doc.title}>
      <Body doc={doc} />
    </ShareLayout>
  )
}

function Body({ doc }: { doc: ShareDocument }) {
  if (doc.kind === 'session' && doc.session) return <SharedSession doc={doc.session} />
  // Methods and programs get their own views with 25.3; until then the page
  // says what the link is and sends the reader to the app.
  return (
    <div className="space-y-3">
      <p className="text-sm">
        {doc.kind === 'program' ? 'A program' : 'A method'} was shared with you: <span className="font-medium">{doc.title}</span>.
      </p>
      {!!doc.methods?.length && (
        <ul className="space-y-1 text-xs text-muted-foreground">
          {doc.methods.map((m) => <li key={m.id}>{m.name}</li>)}
        </ul>
      )}
      <p className="text-xs text-muted-foreground">Open it in the app to save it.</p>
    </div>
  )
}
