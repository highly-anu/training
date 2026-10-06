import { useState } from 'react'
import { Watch, X } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Button } from '@/components/ui/button'
import { useDevices, useClaimDevice, useRevokeDevice, useLatestWellness } from '@/api/devices'
import { wellnessSummary } from '@/lib/wellness'

function when(iso: string | null): string {
  if (!iso) return 'never'
  try { return format(parseISO(iso), 'd MMM yyyy, HH:mm') } catch { return iso }
}

/**
 * Connect IQ watches bound to this account. A watch shows a six-character
 * code; entering it here claims it. The iOS app has had this screen since the
 * pairing routes existed; the web never did.
 */
export function DevicesCard() {
  const { data: devices = [], isLoading, isError } = useDevices()
  const claim = useClaimDevice()
  const revoke = useRevokeDevice()
  const { data: latest } = useLatestWellness()
  const [code, setCode] = useState('')

  return (
    <div className="rounded-lg border border-border/30 bg-card/40 p-4 space-y-4">
      <div className="flex items-center gap-2">
        <Watch className="size-4 text-muted-foreground" />
        <p className="text-sm font-medium">Watch devices</p>
      </div>
      <p className="text-[11px] text-muted-foreground">
        A Garmin watch running the companion app shows a pairing code. Enter it to let the watch read today's session and upload workouts.
      </p>

      <form
        className="flex items-center gap-2"
        onSubmit={(e) => { e.preventDefault(); if (code.trim()) claim.mutate(code, { onSuccess: () => setCode('') }) }}
      >
        <input
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="Pairing code"
          maxLength={8}
          aria-label="Pairing code"
          className="h-8 w-36 rounded-md border border-border bg-background px-2 text-xs font-mono uppercase focus:outline-none focus:ring-1 focus:ring-primary"
        />
        <Button type="submit" size="sm" className="h-8 text-xs" disabled={!code.trim() || claim.isPending}>
          {claim.isPending ? 'Pairing…' : 'Pair'}
        </Button>
        {claim.isError && <span className="text-[11px] text-red-700 dark:text-red-300">{claim.error.message}</span>}
        {claim.isSuccess && <span className="text-[11px] text-emerald-700 dark:text-emerald-300">Paired</span>}
      </form>

      {isLoading && <p className="text-[11px] text-muted-foreground">Loading devices…</p>}
      {isError && <p className="text-[11px] text-muted-foreground">Could not reach the API.</p>}
      {!isLoading && !isError && devices.length === 0 && (
        <p className="text-[11px] text-muted-foreground/70">No watch paired yet.</p>
      )}
      {devices.length > 0 && (
        <ul className="divide-y divide-border/30">
          {devices.map((d) => (
            <li key={d.deviceToken} className="flex items-center justify-between gap-3 py-2">
              <div className="min-w-0">
                <p className="text-sm truncate">{d.deviceName ?? 'Watch'}</p>
                <p className="text-[11px] text-muted-foreground">
                  paired {when(d.claimedAt)} · last used {when(d.lastUsedAt)} · <span className="font-mono">{d.deviceToken}</span>
                </p>
              </div>
              <Button
                variant="ghost"
                size="sm"
                className="h-8 px-2 text-muted-foreground hover:text-destructive"
                onClick={() => revoke.mutate(d.deviceToken)}
                aria-label={`Revoke ${d.deviceName ?? 'watch'}`}
              >
                <X className="size-3.5" />
              </Button>
            </li>
          ))}
        </ul>
      )}
      {latest && (
        <p className="text-[11px] text-muted-foreground">
          Last wellness reading{latest.model ? ` from the ${latest.model}` : ''}: {wellnessSummary(latest)}
        </p>
      )}
    </div>
  )
}
