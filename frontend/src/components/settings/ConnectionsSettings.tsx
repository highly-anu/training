/**
 * Profile → Connections.
 *
 * Where the athlete connects a service and decides what imports automatically.
 * The toggles are server-backed rather than local, because the Garmin webhook
 * worker reads them: a preference the browser kept to itself would do nothing
 * about activities Garmin is already pushing.
 */
import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { format, parseISO } from 'date-fns'
import { AlertCircle, Check, Loader2, LogOut, Watch } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { StravaConnect } from '@/components/bio/StravaConnect'
import { useProfileStore } from '@/store/profileStore'
import {
  useGarminStatus,
  useGarminAuthorize,
  useGarminDisconnect,
  useGarminBackfill,
} from '@/api/garmin'
import { CONNECTABLE_SOURCES } from '@/lib/workoutSource'

function formatWhen(iso?: string | null): string {
  if (!iso) return 'never'
  try {
    return format(parseISO(iso), 'd MMM, HH:mm')
  } catch {
    return 'never'
  }
}

// ── Garmin ────────────────────────────────────────────────────────────────────

function GarminConnect() {
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()

  const { data: status, isLoading } = useGarminStatus()
  const authorize = useGarminAuthorize()
  const disconnect = useGarminDisconnect()
  const backfill = useGarminBackfill()

  // The OAuth callback redirects back here with ?garmin=connected|error.
  const garminParam = searchParams.get('garmin')
  const garminReason = searchParams.get('reason')
  useEffect(() => {
    if (!garminParam) return
    if (garminParam === 'connected') {
      queryClient.invalidateQueries({ queryKey: ['oauth', 'garmin', 'status'] })
    }
    setSearchParams(
      (prev) => {
        prev.delete('garmin')
        prev.delete('reason')
        return prev
      },
      { replace: true }
    )
    // queryClient and setSearchParams are stable references from their
    // providers; the effect should run when the callback param changes.
  }, [garminParam, queryClient, setSearchParams])

  if (isLoading) {
    return (
      <div className="rounded-lg border border-border bg-card p-4">
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
      </div>
    )
  }

  // No server credentials — the whole integration is inert, so say so plainly
  // rather than offering a button that can only fail.
  if (!status?.configured) {
    return (
      <div className="rounded-lg border border-dashed border-border bg-card/50 p-4 space-y-2">
        <div className="flex items-center gap-2">
          <Watch className="h-4 w-4 text-muted-foreground" />
          <p className="text-sm font-medium">Garmin</p>
          <Badge variant="outline" className="text-[10px]">Not configured</Badge>
        </div>
        <p className="text-xs text-muted-foreground leading-relaxed">
          This server has no Garmin credentials yet. Until it does, Garmin activities
          can still arrive via Strava or, on iPhone, via Apple Health.
        </p>
      </div>
    )
  }

  if (!status.connected) {
    return (
      <div className="rounded-lg border border-border bg-card p-4 space-y-3">
        <div className="flex items-center gap-2">
          <Watch className="h-4 w-4 text-muted-foreground" />
          <p className="text-sm font-medium">Garmin</p>
        </div>
        <p className="text-xs text-muted-foreground leading-relaxed">
          Connect your Garmin account and every activity you record will appear here
          on its own, with GPS, heart rate and elevation, matched to the session you
          had planned.
        </p>
        {garminParam === 'error' && (
          <p className="flex items-start gap-1.5 text-xs text-destructive">
            <AlertCircle className="h-3.5 w-3.5 shrink-0 mt-px" />
            <span>Could not connect{garminReason ? `: ${garminReason}` : ''}.</span>
          </p>
        )}
        <Button
          size="sm"
          onClick={() => authorize.mutate()}
          disabled={authorize.isPending}
        >
          {authorize.isPending ? 'Redirecting…' : 'Connect Garmin'}
        </Button>
      </div>
    )
  }

  return (
    <div className="rounded-lg border border-border bg-card p-4 space-y-3">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <Watch className="h-4 w-4 text-muted-foreground" />
            <p className="text-sm font-medium">Garmin</p>
            <Badge variant="outline" className="gap-1 text-[10px]">
              <Check className="h-3 w-3" /> Connected
            </Badge>
          </div>
          <p className="text-xs text-muted-foreground">
            Last activity received {formatWhen(status.last_webhook_at)}
          </p>
        </div>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => disconnect.mutate()}
          disabled={disconnect.isPending}
          className="text-muted-foreground"
        >
          <LogOut className="h-3.5 w-3.5 mr-1" />
          Disconnect
        </Button>
      </div>

      {/* No "sync now": Garmin pushes. The only useful manual action is asking
          it to replay history, which it also delivers through the webhook. */}
      <div className="flex items-center gap-3 pt-1">
        <Button
          size="sm"
          variant="outline"
          onClick={() => backfill.mutate({ days: 90 })}
          disabled={backfill.isPending}
        >
          {backfill.isPending ? 'Requesting…' : 'Import last 90 days'}
        </Button>
        {backfill.isSuccess && (
          <p className="text-xs text-muted-foreground">
            Requested — Garmin delivers these over the next few minutes.
          </p>
        )}
      </div>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

export function ConnectionsSettings() {
  const integrations = useProfileStore((s) => s.integrations)
  const setIntegrations = useProfileStore((s) => s.setIntegrations)

  const masterOn = integrations.autoImport

  function setMaster(enabled: boolean) {
    setIntegrations({ ...integrations, autoImport: enabled })
  }

  function setSource(key: string, enabled: boolean) {
    setIntegrations({
      ...integrations,
      sources: { ...integrations.sources, [key]: { enabled } },
    })
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Profile settings
          </p>
          <h2 className="text-2xl font-semibold leading-snug">Connections.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Connect the services you record with and your workouts arrive here on their
            own — matched to the session you had planned, with the richest copy kept
            when the same activity comes from more than one place.
          </p>
        </div>

        {/* Master switch */}
        <div className="space-y-4">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
            Automatic import
          </h3>
          <div className="rounded-lg border border-border bg-card p-4">
            <div className="flex items-start justify-between gap-4">
              <div className="space-y-1">
                <p className="text-sm font-medium">Import workouts automatically</p>
                <p className="text-xs text-muted-foreground leading-relaxed max-w-md">
                  Turn this off to stop every connected service from importing, without
                  disconnecting any of them.
                </p>
              </div>
              <Switch
                checked={masterOn}
                onCheckedChange={setMaster}
                aria-label="Import workouts automatically"
              />
            </div>
          </div>
        </div>

        {/* Per-source toggles */}
        <div className="space-y-4">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
            Sources
          </h3>
          <div className="rounded-lg border border-border bg-card divide-y divide-border">
            {CONNECTABLE_SOURCES.map(({ key, name, description }) => {
              const enabled = integrations.sources[key]?.enabled ?? true
              return (
                <div
                  key={key}
                  className={`flex items-start justify-between gap-4 p-4 transition-opacity ${
                    masterOn ? '' : 'opacity-50'
                  }`}
                >
                  <div className="space-y-1">
                    <p className="text-sm font-medium">{name}</p>
                    <p className="text-xs text-muted-foreground leading-relaxed max-w-md">
                      {description}
                      {key === 'appleHealth' && (
                        <span className="block mt-1 text-muted-foreground/70">
                          Applies to the iPhone app; there is nothing to import from a browser.
                        </span>
                      )}
                    </p>
                  </div>
                  <Switch
                    checked={enabled}
                    disabled={!masterOn}
                    onCheckedChange={(v) => setSource(key, v)}
                    aria-label={`Import from ${name}`}
                  />
                </div>
              )
            })}
          </div>
        </div>

        {/* Accounts */}
        <div className="space-y-4">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
            Accounts
          </h3>
          <GarminConnect />
          <StravaConnect />
        </div>
      </div>
    </div>
  )
}
