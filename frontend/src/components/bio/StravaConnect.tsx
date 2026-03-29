import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { RefreshCw, LogOut, Zap } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  useStravaStatus,
  useStravaAuthorize,
  useStravaSyncMutation,
  useStravaDisconnect,
} from '@/api/oauth'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { useCurrentProgram } from '@/api/programs'
import { autoMatchWorkouts } from '@/lib/workoutMatcher'

// Strava brand colour
const STRAVA_ORANGE = '#FC4C02'

export function StravaConnect() {
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()

  const { data: status, isLoading } = useStravaStatus()
  const authorize = useStravaAuthorize()
  const sync = useStravaSyncMutation()
  const disconnect = useStravaDisconnect()

  const addImportedWorkouts = useBioStore((s) => s.addImportedWorkouts)
  const addAutoMatch = useBioStore((s) => s.addAutoMatch)
  const setPendingMatches = useBioStore((s) => s.setPendingMatches)
  const workoutMatches = useBioStore((s) => s.workoutMatches)

  const program = useCurrentProgram()
  const programStartDate = useProgramStore((s) => s.programStartDate)

  // Handle redirect back from Strava OAuth
  const stravaParam = searchParams.get('strava')
  useEffect(() => {
    if (stravaParam === 'connected') {
      queryClient.invalidateQueries({ queryKey: ['oauth', 'strava', 'status'] })
      setSearchParams((prev) => { prev.delete('strava'); prev.delete('reason'); return prev }, { replace: true })
    }
  }, [stravaParam])

  function handleSync() {
    // Sync from last sync time (or all if never synced)
    const lastSync = status?.last_sync_at
    const since = lastSync ? new Date(lastSync).getTime() / 1000 : undefined
    sync.mutate(
      { since_timestamp: since },
      {
        onSuccess: ({ activities }) => {
          if (activities.length === 0) return
          addImportedWorkouts(activities)
          if (program && programStartDate) {
            const { confirmed, pending } = autoMatchWorkouts(
              activities, program, programStartDate, workoutMatches
            )
            confirmed.forEach((m) => addAutoMatch(m.importedWorkoutId, m.sessionKey))
            setPendingMatches(pending)
          }
        },
      }
    )
  }

  // ── Not configured ────────────────────────────────────────────────────────
  if (!isLoading && status && !status.configured) {
    return (
      <div className="rounded-xl border border-dashed border-border bg-muted/10 p-4">
        <div className="flex items-center gap-3">
          <StravaIcon />
          <div>
            <p className="text-sm font-medium">Connect Strava</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Set <code className="text-[11px] bg-muted px-1 rounded">STRAVA_CLIENT_ID</code> and{' '}
              <code className="text-[11px] bg-muted px-1 rounded">STRAVA_CLIENT_SECRET</code> in
              your API server environment to enable Strava sync.
            </p>
          </div>
        </div>
      </div>
    )
  }

  // ── Disconnected ──────────────────────────────────────────────────────────
  if (!isLoading && status && !status.connected) {
    return (
      <div className="rounded-xl border border-border bg-card p-4">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <StravaIcon />
            <div>
              <p className="text-sm font-medium">Connect Strava</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Auto-sync workouts from Strava (also captures Garmin, Suunto, Polar via Strava).
              </p>
            </div>
          </div>
          <Button
            size="sm"
            onClick={() => authorize.mutate()}
            disabled={authorize.isPending}
            style={{ backgroundColor: STRAVA_ORANGE, color: '#fff' }}
            className="shrink-0 hover:opacity-90 transition-opacity"
          >
            {authorize.isPending ? (
              <RefreshCw className="size-3.5 animate-spin mr-1.5" />
            ) : (
              <Zap className="size-3.5 mr-1.5" />
            )}
            Connect
          </Button>
        </div>

        {stravaParam === 'error' && (
          <p className="mt-2 text-xs text-red-400">
            Authorization failed: {searchParams.get('reason') ?? 'unknown error'}
          </p>
        )}
      </div>
    )
  }

  // ── Connected ─────────────────────────────────────────────────────────────
  if (!isLoading && status?.connected) {
    const lastSyncLabel = status.last_sync_at
      ? format(parseISO(status.last_sync_at), 'MMM d, h:mm a')
      : 'Never'

    return (
      <div className="rounded-xl border border-border bg-card p-4 space-y-3">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <StravaIcon />
            <div>
              <div className="flex items-center gap-2">
                <p className="text-sm font-medium">{status.athlete?.name ?? 'Strava'}</p>
                <Badge
                  variant="outline"
                  className="text-[10px] border-emerald-500/40 text-emerald-500"
                >
                  Connected
                </Badge>
              </div>
              <p className="text-xs text-muted-foreground mt-0.5">Last sync: {lastSyncLabel}</p>
            </div>
          </div>

          {/* Athlete avatar */}
          {status.athlete?.profile && (
            <img
              src={status.athlete.profile}
              alt={status.athlete.name}
              className="size-9 rounded-full shrink-0 object-cover border border-border"
            />
          )}
        </div>

        {/* Sync result feedback */}
        {sync.isSuccess && (
          <p className="text-xs text-emerald-500">
            Synced {sync.data.count} activit{sync.data.count === 1 ? 'y' : 'ies'}.
          </p>
        )}
        {sync.isError && (
          <p className="text-xs text-red-400">{sync.error.message}</p>
        )}

        <div className="flex gap-2">
          <Button
            size="sm"
            onClick={handleSync}
            disabled={sync.isPending}
            className="flex-1"
          >
            {sync.isPending ? (
              <RefreshCw className="size-3.5 animate-spin mr-1.5" />
            ) : (
              <RefreshCw className="size-3.5 mr-1.5" />
            )}
            {sync.isPending ? 'Syncing…' : 'Sync Now'}
          </Button>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => disconnect.mutate()}
            disabled={disconnect.isPending}
            className="text-muted-foreground hover:text-foreground"
          >
            <LogOut className="size-3.5 mr-1.5" />
            Disconnect
          </Button>
        </div>
      </div>
    )
  }

  // Loading skeleton
  return (
    <div className="rounded-xl border border-border bg-card p-4 animate-pulse">
      <div className="flex items-center gap-3">
        <div className="size-8 rounded-full bg-muted" />
        <div className="space-y-1.5">
          <div className="h-3 w-24 rounded bg-muted" />
          <div className="h-2 w-40 rounded bg-muted" />
        </div>
      </div>
    </div>
  )
}

function StravaIcon() {
  return (
    <svg width="32" height="32" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="40" height="40" rx="8" fill={STRAVA_ORANGE} />
      <path d="M17 28L11 17h6l6 11z" fill="white" opacity="0.6" />
      <path d="M23 28L17 17h6l6 11z" fill="white" />
    </svg>
  )
}
