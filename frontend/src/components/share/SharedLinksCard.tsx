import { format, parseISO } from 'date-fns'
import { Link2, X } from 'lucide-react'
import { useMyShares, useRevokeShare, type ShareKind } from '@/api/shares'
import { Button } from '@/components/ui/button'
import { FailedState, LoadingState } from '@/components/shared/states'
import { announce } from '@/lib/announce'

const KIND: Record<ShareKind, string> = { session: 'Session', package: 'Method', program: 'Program' }

function when(iso: string | null): string {
  if (!iso) return ''
  try { return format(parseISO(iso.replace(' ', 'T')), 'd MMM yyyy') } catch { return '' }
}

/**
 * The links this account has shared (Settings ▸ Account). A link shows what
 * it showed when it was made until it is removed here; removing one stops it
 * for everyone who has it.
 */
export function SharedLinksCard() {
  const { data, isLoading, isError, error, refetch } = useMyShares()
  const revoke = useRevokeShare()
  const shares = data?.shares ?? []

  return (
    <div className="space-y-3 rounded-lg border border-border/30 bg-card/40 p-4">
      <div className="flex items-center gap-2">
        <Link2 className="size-4 text-muted-foreground" aria-hidden />
        <p className="text-sm font-medium">Shared links</p>
      </div>
      <p className="text-[11px] text-muted-foreground">
        Anyone with a link can open it. It keeps showing what it showed when you shared it, even after you change or
        delete what it came from, until you remove it here.
      </p>
      {isLoading && <LoadingState shape="lines" label="Loading your links" />}
      {isError && (
        <FailedState size="compact" className="items-start border-0 bg-transparent p-0 text-left"
          title="Could not load your links" error={error} onRetry={() => void refetch()} />
      )}
      {data && shares.length === 0 && (
        <p className="text-xs text-muted-foreground">
          Nothing shared yet. Share a session, a method or your program from where you read it.
        </p>
      )}
      {shares.length > 0 && (
        <ul className="divide-y divide-border/40">
          {shares.map((s) => (
            <li key={s.token} className="flex items-center gap-3 py-2">
              <div className="min-w-0 flex-1">
                <a href={s.url} target="_blank" rel="noreferrer" className="block truncate text-xs font-medium hover:underline">
                  {s.title ?? KIND[s.kind]}
                </a>
                <p className="text-[11px] text-muted-foreground">{[KIND[s.kind], when(s.createdAt)].filter(Boolean).join(' · ')}</p>
              </div>
              <Button variant="ghost" size="sm" className="h-7 gap-1 text-[11px] text-muted-foreground"
                loading={revoke.isPending && revoke.variables === s.token}
                onClick={() => revoke.mutate(s.token, { onSuccess: () => announce(`Link to ${s.title ?? 'it'} removed.`) })}>
                <X className="size-3" aria-hidden /> Remove
              </Button>
            </li>
          ))}
        </ul>
      )}
      {revoke.isError && <p role="alert" className="text-[11px] text-bad">{revoke.error.message}</p>}
    </div>
  )
}
