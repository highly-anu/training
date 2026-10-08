import { Link, useSearchParams } from 'react-router-dom'
import { Watch } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useClaimDevice } from '@/api/devices'
import { pairingCode } from '@/lib/returnPath'

/**
 * Where the watch's pairing QR lands: `<web>/pair?code=ABC234`.
 *
 * The watch encodes this link when its `webBaseUrl` setting is filled in
 * (garmin/TrainingCompanionCIQ, Config.pairQrValue); with it empty the QR is
 * the bare code, typed into Settings ▸ Connections ▸ Watch devices instead.
 * Signing in on the way keeps the link (ProtectedRoute → LoginPage →
 * lib/returnPath). The claim waits for a tap: a QR is anyone's to print, and
 * claiming on load would bind whichever watch made it to the account of
 * whoever scanned it. The code is shown large so it can be checked against
 * the watch face first.
 */
export function PairDevice() {
  const [params] = useSearchParams()
  const code = pairingCode(params.get('code'))
  const claim = useClaimDevice()

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <Watch className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Pair a watch</h1>
      </div>

      <div className="flex flex-1 items-start justify-center p-6">
        <div className="w-full max-w-sm rounded-lg border border-border/30 bg-card/40 p-5 space-y-4">
          {!code && (
            <>
              <p className="text-sm">This link has no pairing code the watch could have made.</p>
              <p className="text-xs text-muted-foreground">
                Open the Training Companion app on the watch to get a new code, then scan it again or type it under
                Settings ▸ Connections.
              </p>
              <Button asChild size="sm" variant="outline" className="h-8 text-xs">
                <Link to="/settings?tab=connections">Open Connections</Link>
              </Button>
            </>
          )}

          {code && !claim.isSuccess && (
            <>
              <p className="text-xs text-muted-foreground">Check that the watch shows this code, then pair it with your account.</p>
              <p className="text-center font-mono text-3xl font-semibold tracking-[0.3em]" aria-label="Pairing code">
                {code}
              </p>
              <Button
                className="w-full h-9 text-sm"
                disabled={claim.isPending}
                onClick={() => claim.mutate(code)}
              >
                {claim.isPending ? 'Pairing…' : 'Pair this watch'}
              </Button>
              {claim.isError && (
                <p className="text-[11px] text-red-700 dark:text-red-300">
                  {claim.error.message}. Codes last ten minutes — open the app on the watch for a new one.
                </p>
              )}
            </>
          )}

          {code && claim.isSuccess && (
            <>
              <p className="text-sm font-medium text-emerald-700 dark:text-emerald-300">Paired</p>
              <p className="text-xs text-muted-foreground">
                The watch picks this up within a few seconds and shows today's session.
              </p>
              <Button asChild size="sm" variant="outline" className="h-8 text-xs">
                <Link to="/settings?tab=connections">See your devices</Link>
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
