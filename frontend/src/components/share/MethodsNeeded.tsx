import { Link, useLocation } from 'react-router-dom'
import { Check, CircleDashed, Package } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useSaveShare, type MethodState, type ShareDocument } from '@/api/shares'
import { useAuthStore } from '@/store/authStore'

const STATE: Record<MethodState, string> = {
  shipped: 'In the app',
  have: 'You have it',
  different: 'You have another version',
  missing: 'Not saved yet',
}

/** Why a save did not happen, in the reader's words. */
export function saveRefusal(err: { status?: number; body?: { error?: string; busy?: boolean; olderEngine?: boolean; name?: string; problems?: { message: string }[] }; message: string }): string {
  const body = err.body ?? {}
  if (body.busy) return 'The server is busy with another check. Try again in a moment.'
  if (body.error === 'too_many_packages') return 'You keep the most methods an account can hold. Remove one, then save this.'
  if (body.error === 'not_enabled') return 'Saving methods is not available for this account.'
  if (body.error === 'not_found') return 'This link is no longer shared.'
  if (body.error === 'not_installable') {
    return body.olderEngine
      ? `${body.name ?? 'This method'} was written for an earlier version of the app and no longer passes its checks. Ask for a new link.`
      : `${body.name ?? 'This method'} did not pass the app's checks${body.problems?.[0] ? `: ${body.problems[0].message}` : '.'}`
  }
  return err.message
}

/**
 * The methods a link needs and what the reader has of them, with the one
 * action that closes the gap: Save (docs/frontend-design.md §13.14). Signed
 * out it lists them and offers sign-in, which comes back to the link.
 */
export function MethodsNeeded({ doc, saveLabel, onSaved }: {
  doc: ShareDocument
  /** "Save to your methods", "Save the methods it needs". */
  saveLabel: string
  onSaved?: () => void
}) {
  const user = useAuthStore((s) => s.user)
  const location = useLocation()
  const save = useSaveShare(doc.token)
  const a = doc.availability
  const rows = a?.methods ?? (doc.methods ?? []).map((m) => ({ id: m.id, name: m.name, state: null, savable: m.private }))
  const different = save.error?.body?.error === 'different'
  const needsSave = !!a && a.toSave > 0

  return (
    <section aria-label="Methods it needs" className="space-y-2 rounded-lg border border-border/40 bg-card/40 p-3">
      <ul className="space-y-1.5">
        {rows.map((m) => {
          const done = m.state === 'have' || m.state === 'shipped'
          return (
            <li key={m.id} className="flex items-center gap-2 text-sm">
              {done ? <Check className="size-3.5 shrink-0 text-done" aria-hidden />
                : m.state ? <CircleDashed className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
                  : <Package className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />}
              <span className="min-w-0 flex-1 truncate">{m.name}</span>
              {m.state && <span className="shrink-0 text-xs text-muted-foreground">{STATE[m.state]}</span>}
            </li>
          )
        })}
      </ul>

      {!user && rows.some((m) => m.savable) && (
        <Button asChild size="sm" className="h-8 text-xs">
          <Link to="/login" state={{ from: location.pathname + location.search }}>Sign in to save</Link>
        </Button>
      )}
      {a?.yours && <p className="text-xs text-muted-foreground">This is your own link.</p>}
      {a && !a.yours && needsSave && a.canSave && !different && (
        <Button size="sm" className="h-8 text-xs" loading={save.isPending}
          onClick={() => save.mutate(undefined, { onSuccess: onSaved })}>
          {saveLabel}
        </Button>
      )}
      {a && !a.canSave && needsSave && (
        <p className="text-xs text-muted-foreground">Saving methods is not available for this account.</p>
      )}
      {different && (
        <div className="space-y-1.5">
          <p className="text-xs text-muted-foreground">
            You already have another version of {save.error?.body?.methods?.map((m) => m.name).join(', ') ?? 'this method'} —
            one you saved earlier or changed since. Replacing it keeps nothing of yours.
          </p>
          <Button size="sm" variant="outline" className="h-8 text-xs" loading={save.isPending}
            onClick={() => save.mutate({ replace: true }, { onSuccess: onSaved })}>
            Replace my version
          </Button>
        </div>
      )}
      {save.isError && !different && <p role="alert" className="text-xs text-bad">{saveRefusal(save.error)}</p>}
      {save.isSuccess && save.data.installed.length > 0 && (
        <p role="status" className="text-xs text-done">
          Saved {save.data.installed.map((m) => m.name).join(', ')} to your methods.
        </p>
      )}
    </section>
  )
}
