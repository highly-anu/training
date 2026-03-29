import { useState, useCallback } from 'react'
import { motion } from 'framer-motion'
import { Upload, FileText, CheckCircle2, AlertCircle, X, Link2 } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { MatchConfirmDialog } from '@/components/bio/MatchConfirmDialog'
import { StravaConnect } from '@/components/bio/StravaConnect'
import { parseAppleHealthXml, parseStravaJson } from '@/lib/importParsers'
import { autoMatchWorkouts } from '@/lib/workoutMatcher'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { useCurrentProgram } from '@/api/programs'
import type { ImportedWorkout, PendingMatch } from '@/api/types'

type ParseStatus = 'idle' | 'parsing' | 'done' | 'error'

export function WorkoutImport() {
  const [status, setStatus] = useState<ParseStatus>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [parsed, setParsed] = useState<ImportedWorkout[]>([])
  const [activePending, setActivePending] = useState<PendingMatch | null>(null)

  const addImportedWorkouts = useBioStore((s) => s.addImportedWorkouts)
  const addAutoMatch = useBioStore((s) => s.addAutoMatch)
  const setPendingMatches = useBioStore((s) => s.setPendingMatches)
  const removeImportedWorkout = useBioStore((s) => s.removeImportedWorkout)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const pendingMatches = useBioStore((s) => s.pendingMatches)

  const program = useCurrentProgram()
  const programStartDate = useProgramStore((s) => s.programStartDate)

  function matchStatus(workoutId: string): 'matched' | 'pending' | 'unmatched' {
    const match = workoutMatches.find((m) => m.importedWorkoutId === workoutId)
    if (match && match.matchConfidence !== 'rejected') return 'matched'
    if (match?.matchConfidence === 'rejected') return 'unmatched'
    if (pendingMatches.some((p) => p.importedWorkout.id === workoutId)) return 'pending'
    return 'unmatched'
  }

  async function processFile(file: File) {
    setStatus('parsing')
    setErrorMsg('')
    try {
      let workouts: ImportedWorkout[] = []

      if (file.name.endsWith('.xml')) {
        if (file.size > 50 * 1024 * 1024) {
          // Large file — use server-side parse
          const fd = new FormData()
          fd.append('workout_file', file)
          const res = await fetch('/api/workouts/parse', { method: 'POST', body: fd })
          if (!res.ok) throw new Error('Server parse failed')
          workouts = await res.json()
        } else {
          const text = await file.text()
          workouts = parseAppleHealthXml(text)
        }
      } else if (file.name.endsWith('.json')) {
        const text = await file.text()
        workouts = parseStravaJson(JSON.parse(text))
      } else if (file.name.endsWith('.fit')) {
        // FIT is binary — always server-side
        const fd = new FormData()
        fd.append('workout_file', file)
        const res = await fetch('/api/workouts/parse', { method: 'POST', body: fd })
        if (!res.ok) {
          const body = await res.json().catch(() => ({}))
          throw new Error(body.detail ?? 'FIT parse failed')
        }
        workouts = await res.json()
      } else {
        throw new Error('Unsupported file type. Please upload a .fit, .xml (Apple Health), or .json (Strava) file.')
      }

      setParsed(workouts)
      addImportedWorkouts(workouts)

      // Run matching if we have a program + start date
      if (program && programStartDate) {
        const { confirmed, pending } = autoMatchWorkouts(
          workouts,
          program,
          programStartDate,
          workoutMatches
        )
        confirmed.forEach((m) => addAutoMatch(m.importedWorkoutId, m.sessionKey))
        setPendingMatches(pending)
      }

      setStatus('done')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Unknown error')
      setStatus('error')
    }
  }

  const onDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      const file = e.dataTransfer.files[0]
      if (file) processFile(file)
    },
    [program, programStartDate, workoutMatches]
  )

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) processFile(file)
    e.target.value = ''
  }

  const allImported = importedWorkouts.slice().sort((a, b) => b.date.localeCompare(a.date))

  return (
    <motion.div
      key="workout-import"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="h-full overflow-y-auto p-6 space-y-6 max-w-2xl"
    >
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Import Workouts</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Upload a Garmin/Suunto/WorkOutDoors .fit file, Apple Health export (.xml), or Strava activities export (.json) to sync workout data with your training sessions.
        </p>
      </div>

      {/* Strava OAuth connect */}
      <StravaConnect />

      {/* Program start date input */}
      {program && (
        <ProgramStartDateInput />
      )}

      {/* Drop zone */}
      <div
        onDrop={onDrop}
        onDragOver={(e) => e.preventDefault()}
        className="flex flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-border bg-muted/20 px-6 py-10 transition-colors hover:border-primary/50 hover:bg-primary/5"
      >
        <Upload className="size-8 text-muted-foreground" />
        <div className="text-center">
          <p className="text-sm font-medium">Drop your export file here</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            .fit (Garmin/Suunto/WorkOutDoors), Apple Health .xml, or Strava .json
          </p>
        </div>
        <label className="cursor-pointer">
          <span className="rounded-md bg-primary px-3 py-1.5 text-sm font-medium text-primary-foreground hover:bg-primary/90 transition-colors">
            Browse file
          </span>
          <input
            type="file"
            accept=".fit,.xml,.json"
            onChange={onFileChange}
            className="sr-only"
          />
        </label>
      </div>

      {/* Status */}
      {status === 'parsing' && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          Parsing file…
        </div>
      )}
      {status === 'done' && (
        <div className="flex items-center gap-2 text-sm text-emerald-500">
          <CheckCircle2 className="size-4" />
          Imported {parsed.length} workout{parsed.length !== 1 ? 's' : ''}
          {pendingMatches.length > 0 && (
            <span className="text-amber-500">
              — {pendingMatches.length} need{pendingMatches.length === 1 ? 's' : ''} manual matching
            </span>
          )}
        </div>
      )}
      {status === 'error' && (
        <div className="flex items-center gap-2 text-sm text-red-500">
          <AlertCircle className="size-4" />
          {errorMsg}
        </div>
      )}

      {/* Pending matches banner */}
      {pendingMatches.length > 0 && (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3">
          <p className="text-sm font-medium text-amber-500 mb-2">
            {pendingMatches.length} workout{pendingMatches.length !== 1 ? 's need' : ' needs'} manual matching
          </p>
          <div className="flex flex-wrap gap-2">
            {pendingMatches.map((p) => (
              <Button
                key={p.importedWorkout.id}
                size="sm"
                variant="outline"
                onClick={() => setActivePending(p)}
                className="text-xs border-amber-500/40 text-amber-500 hover:bg-amber-500/10"
              >
                <Link2 className="size-3 mr-1" />
                {p.importedWorkout.date} — {p.importedWorkout.activityType.replace(/HKWorkoutActivityType/, '')}
              </Button>
            ))}
          </div>
        </div>
      )}

      {/* All imported workouts */}
      {allImported.length > 0 && (
        <>
          <Separator />
          <div>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
              Imported Workouts ({allImported.length})
            </h2>
            <div className="space-y-2">
              {allImported.map((w) => {
                const ms = matchStatus(w.id)
                return (
                  <div
                    key={w.id}
                    className="flex items-center gap-3 rounded-lg border border-border bg-card px-3 py-2.5"
                  >
                    <FileText className="size-4 shrink-0 text-muted-foreground" />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-medium truncate">
                          {w.activityType.replace(/HKWorkoutActivityType/, '')}
                        </p>
                        <Badge
                          variant="outline"
                          className={
                            ms === 'matched'
                              ? 'text-[10px] border-emerald-500/40 text-emerald-500'
                              : ms === 'pending'
                              ? 'text-[10px] border-amber-500/40 text-amber-500'
                              : 'text-[10px] border-border text-muted-foreground'
                          }
                        >
                          {ms}
                        </Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {(() => {
                          try { return format(parseISO(w.startTime), 'EEE, MMM d') }
                          catch { return w.date }
                        })()}
                        {' · '}{w.durationMinutes} min
                        {w.heartRate.avg != null && ` · ${Math.round(w.heartRate.avg)} bpm`}
                      </p>
                    </div>
                    {ms === 'pending' && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setActivePending(pendingMatches.find((p) => p.importedWorkout.id === w.id) ?? null)}
                        className="text-xs text-amber-500 hover:text-amber-400"
                      >
                        Match
                      </Button>
                    )}
                    <button
                      type="button"
                      onClick={() => removeImportedWorkout(w.id)}
                      className="p-1 text-muted-foreground hover:text-foreground transition-colors rounded"
                      aria-label="Remove workout"
                    >
                      <X className="size-3.5" />
                    </button>
                  </div>
                )
              })}
            </div>
          </div>
        </>
      )}

      {/* Match confirm dialog */}
      <MatchConfirmDialog
        match={activePending}
        onClose={() => setActivePending(null)}
      />
    </motion.div>
  )
}

// ── Program start date input ───────────────────────────────────────────────────

function ProgramStartDateInput() {
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const setProgramStartDate = useProgramStore((s) => s.setProgramStartDate)

  return (
    <div className="flex items-center gap-3 rounded-lg border border-border bg-card/50 px-4 py-3">
      <div className="flex-1">
        <p className="text-xs font-medium text-muted-foreground">Program Start Date</p>
        <p className="text-[11px] text-muted-foreground/60 mt-0.5">
          Used to map program sessions to calendar dates for workout matching.
        </p>
      </div>
      <input
        type="date"
        value={programStartDate ?? ''}
        onChange={(e) => setProgramStartDate(e.target.value || null)}
        className="h-8 rounded-md border border-border bg-background px-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
      />
    </div>
  )
}
