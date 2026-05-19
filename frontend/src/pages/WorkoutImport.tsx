import { useState, useCallback } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Upload, FileText, CheckCircle2, AlertCircle, X, Link2, ChevronRight, ArrowDownToLine } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { MatchConfirmDialog } from '@/components/bio/MatchConfirmDialog'
import { parseAppleHealthXml, parseStravaJson } from '@/lib/importParsers'
import { autoMatchWorkouts, sessionCalendarDate } from '@/lib/workoutMatcher'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { useCurrentProgram } from '@/api/programs'
import type { ImportedWorkout, PendingMatch, GeneratedProgram } from '@/api/types'

// ── Types ──────────────────────────────────────────────────────────────────────

type SubTab = 'import' | 'history' | 'matched'
type ParseStatus = 'idle' | 'parsing' | 'done' | 'error'

// ── Helpers ────────────────────────────────────────────────────────────────────

function sessionLabel(sessionKey: string): string {
  const parts = sessionKey.split('-')
  if (parts.length < 2) return sessionKey
  return `Week ${parts[0]} — ${parts.slice(1).join('-')}`
}

function formatActivityType(raw: string): string {
  return (
    raw
      .replace(/HKWorkoutActivityType/g, '')
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .trim() || raw
  )
}

// ── Tab Selector ───────────────────────────────────────────────────────────────

function TabSelector({
  active,
  onChange,
  tabs,
}: {
  active: SubTab
  onChange: (t: SubTab) => void
  tabs: { id: SubTab; label: string }[]
}) {
  return (
    <div className="flex items-center gap-1">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onChange(tab.id)}
          className={cn(
            'px-3 py-1 text-xs rounded border transition-colors',
            tab.id === active
              ? 'bg-primary/15 border-primary/40 text-primary'
              : 'border-border text-muted-foreground hover:bg-muted'
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}

// ── Import Tab ─────────────────────────────────────────────────────────────────

function ImportTab({
  status,
  errorMsg,
  parsed,
  duplicateCount,
  pendingMatches,
  linkedSuccess,
  linkToSession,
  activePending,
  hasProgram,
  onDrop,
  onFileChange,
  setActivePending,
  navigate,
}: {
  status: ParseStatus
  errorMsg: string
  parsed: ImportedWorkout[]
  duplicateCount: number
  pendingMatches: PendingMatch[]
  linkedSuccess: string | null
  linkToSession: string | null
  activePending: PendingMatch | null
  hasProgram: boolean
  onDrop: (e: React.DragEvent) => void
  onFileChange: (e: React.ChangeEvent<HTMLInputElement>) => void
  setActivePending: (p: PendingMatch | null) => void
  navigate: (to: string) => void
}) {
  return (
    <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

      {hasProgram && <ProgramStartDateInput />}

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
            .fit (Garmin / Suunto / WorkOutDoors) · Apple Health .xml · Strava .json
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

      {/* Parse status */}
      {status === 'parsing' && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          Parsing file…
        </div>
      )}
      {status === 'done' && (
        <div className="flex items-center gap-2 text-sm text-emerald-500">
          <CheckCircle2 className="size-4" />
          {duplicateCount === parsed.length ? (
            <span className="text-muted-foreground">
              All {parsed.length} workout{parsed.length !== 1 ? 's' : ''} already imported
            </span>
          ) : (
            <>
              Imported {parsed.length - duplicateCount} workout{parsed.length - duplicateCount !== 1 ? 's' : ''}
              {duplicateCount > 0 && (
                <span className="text-muted-foreground">({duplicateCount} already imported)</span>
              )}
              {pendingMatches.length > 0 && (
                <span className="text-amber-500">
                  — {pendingMatches.length} need{pendingMatches.length === 1 ? 's' : ''} manual matching
                </span>
              )}
            </>
          )}
        </div>
      )}
      {status === 'error' && (
        <div className="flex items-center gap-2 text-sm text-red-500">
          <AlertCircle className="size-4" />
          {errorMsg}
        </div>
      )}

      {/* Linked success banner */}
      {linkedSuccess && (
        <div className="flex items-center justify-between rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-4 py-3">
          <div className="flex items-center gap-2 text-sm text-emerald-500">
            <CheckCircle2 className="size-4" />
            Workout linked to {sessionLabel(linkedSuccess)}
          </div>
          <Button size="sm" variant="outline" onClick={() => navigate('/')}>
            Back to Dashboard
          </Button>
        </div>
      )}

      {/* Link-to context banner */}
      {linkToSession && !linkedSuccess && status !== 'done' && (
        <div className="flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-4 py-3 text-sm text-primary">
          <Link2 className="size-4" />
          Importing for {sessionLabel(linkToSession)}
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
                {p.importedWorkout.date} — {formatActivityType(p.importedWorkout.activityType)}
              </Button>
            ))}
          </div>
        </div>
      )}

      <MatchConfirmDialog
        match={activePending}
        onClose={() => setActivePending(null)}
      />
    </div>
  )
}

// ── History Tab ────────────────────────────────────────────────────────────────

function HistoryTab({
  allImported,
  matchStatus,
  pendingMatches,
  activePending,
  setActivePending,
  removeImportedWorkout,
  navigate,
}: {
  allImported: ImportedWorkout[]
  matchStatus: (id: string) => 'matched' | 'pending' | 'unmatched'
  pendingMatches: PendingMatch[]
  activePending: PendingMatch | null
  setActivePending: (p: PendingMatch | null) => void
  removeImportedWorkout: (id: string) => void
  navigate: (to: string) => void
}) {
  if (allImported.length === 0) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <div className="rounded-xl border border-dashed border-border p-12 flex flex-col items-center gap-3 text-center text-muted-foreground">
          <ArrowDownToLine className="size-8 opacity-40" />
          <p className="text-sm">No workouts imported yet.</p>
          <p className="text-xs">Use the Import tab to upload a .fit, .xml, or .json file.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
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
                role="button"
                tabIndex={0}
                onClick={() => navigate(`/import/${encodeURIComponent(w.id)}`)}
                onKeyDown={(e) => e.key === 'Enter' && navigate(`/import/${encodeURIComponent(w.id)}`)}
                className="flex items-center gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 cursor-pointer hover:bg-card/60 transition-colors"
              >
                <FileText className="size-4 shrink-0 text-muted-foreground" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium truncate">
                      {formatActivityType(w.activityType)}
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
                    onClick={(e) => {
                      e.stopPropagation()
                      setActivePending(pendingMatches.find((p) => p.importedWorkout.id === w.id) ?? null)
                    }}
                    className="text-xs text-amber-500 hover:text-amber-400"
                  >
                    Match
                  </Button>
                )}
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); removeImportedWorkout(w.id) }}
                  className="p-1 text-muted-foreground hover:text-foreground transition-colors rounded"
                  aria-label="Remove workout"
                >
                  <X className="size-3.5" />
                </button>
                <ChevronRight className="size-4 shrink-0 text-muted-foreground/50" />
              </div>
            )
          })}
        </div>
      </div>

      <MatchConfirmDialog
        match={activePending}
        onClose={() => setActivePending(null)}
      />
    </div>
  )
}

// ── Matched Tab ────────────────────────────────────────────────────────────────

function MatchedTab({
  workoutMatches,
  importedWorkouts,
  currentProgram,
  navigate,
}: {
  workoutMatches: { importedWorkoutId: string; sessionKey: string; matchConfidence: string }[]
  importedWorkouts: ImportedWorkout[]
  currentProgram: GeneratedProgram | null
  navigate: (to: string) => void
}) {
  const confirmed = workoutMatches.filter((m) => m.matchConfidence !== 'rejected')

  const workoutMap = new Map(importedWorkouts.map((w) => [w.id, w]))

  // Build lookup by both day-level ("weekNum-Day") and per-session ("weekNum-Day-si") keys
  const sessionLookup = new Map<string, { archetypeName: string; modality: string }>()
  for (const week of currentProgram?.weeks ?? []) {
    for (const [dayName, daySessions] of Object.entries(week.schedule)) {
      const dayKey = `${week.week_number}-${dayName}`
      daySessions.forEach((s, si) => {
        const label = { archetypeName: s.archetype?.name ?? s.modality.replace(/_/g, ' '), modality: s.modality }
        sessionLookup.set(`${dayKey}-${si}`, label)
        if (si === 0) sessionLookup.set(dayKey, label) // fallback for legacy day-level keys
      })
    }
  }

  // Parse "weekNum-DayName[-sessionIdx]" → { weekNum, dayName }
  function parseSessionKey(key: string): { weekNum: string; dayName: string } {
    const lastDash = key.lastIndexOf('-')
    const tail = key.slice(lastDash + 1)
    const isPerSession = !isNaN(parseInt(tail, 10)) && String(parseInt(tail, 10)) === tail
    const dayKey = isPerSession ? key.slice(0, lastDash) : key
    const firstDash = dayKey.indexOf('-')
    return { weekNum: dayKey.slice(0, firstDash), dayName: dayKey.slice(firstDash + 1) }
  }

  type MatchRow = { match: { importedWorkoutId: string; sessionKey: string; matchConfidence: string }; workout: ImportedWorkout }
  const rows: MatchRow[] = confirmed
    .map((m) => ({ match: m, workout: workoutMap.get(m.importedWorkoutId) }))
    .filter((r): r is MatchRow => !!r.workout)
    .sort((a, b) => b.workout.date.localeCompare(a.workout.date))

  if (rows.length === 0) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <div className="rounded-xl border border-dashed border-border p-12 flex flex-col items-center gap-3 text-center text-muted-foreground">
          <Link2 className="size-8 opacity-40" />
          <p className="text-sm">No matched workouts yet.</p>
          <p className="text-xs">Import a file on the Import tab and link it to a session.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
          Matched Workouts ({rows.length})
        </h2>
        <div className="space-y-2">
          {rows.map(({ match, workout }) => {
            const session = sessionLookup.get(match.sessionKey)
            const { weekNum, dayName } = parseSessionKey(match.sessionKey)
            const sourceLabel =
              workout.source === 'fit_file' ? 'FIT'
              : workout.source === 'strava' ? 'Strava'
              : workout.source === 'apple_health' || workout.source === 'apple_watch_live' ? 'Apple Health'
              : 'GPS'
            return (
              <div
                key={workout.id}
                role="button"
                tabIndex={0}
                onClick={() => navigate(`/import/${encodeURIComponent(workout.id)}`)}
                onKeyDown={(e) => e.key === 'Enter' && navigate(`/import/${encodeURIComponent(workout.id)}`)}
                className="flex items-center gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 cursor-pointer hover:bg-card/60 transition-colors"
              >
                <FileText className="size-4 shrink-0 text-muted-foreground" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium truncate">
                      {formatActivityType(workout.activityType)}
                    </p>
                    <Badge
                      variant="outline"
                      className="text-[10px] border-emerald-500/40 text-emerald-500 shrink-0"
                    >
                      matched
                    </Badge>
                    <span className="text-[9px] text-muted-foreground/60 border border-border/40 rounded px-1 py-px shrink-0">
                      {sourceLabel}
                    </span>
                  </div>
                  <div className="flex items-center gap-1.5 mt-0.5 text-xs text-muted-foreground">
                    <span>
                      {(() => {
                        try { return format(parseISO(workout.startTime), 'EEE, MMM d') }
                        catch { return workout.date }
                      })()}
                    </span>
                    <span>·</span>
                    <span>{workout.durationMinutes} min</span>
                    {workout.heartRate.avg != null && (
                      <><span>·</span><span>{Math.round(workout.heartRate.avg)} bpm</span></>
                    )}
                    {session && (
                      <><span>·</span><span className="text-muted-foreground/70">Wk {weekNum} {dayName} — {session.archetypeName}</span></>
                    )}
                  </div>
                </div>
                <ChevronRight className="size-4 shrink-0 text-muted-foreground/50" />
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

export function WorkoutImport() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const linkToSession = searchParams.get('linkTo')

  const [activeTab, setActiveTab] = useState<SubTab>(
    searchParams.get('tab') === 'history' ? 'history' : 'import'
  )
  const [status, setStatus] = useState<ParseStatus>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [parsed, setParsed] = useState<ImportedWorkout[]>([])
  const [activePending, setActivePending] = useState<PendingMatch | null>(null)
  const [linkedSuccess, setLinkedSuccess] = useState<string | null>(null)
  const [duplicateCount, setDuplicateCount] = useState(0)

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

      const existingIds = new Set(importedWorkouts.map((w) => w.id))
      const novelCount = workouts.filter((w) => !existingIds.has(w.id)).length
      setDuplicateCount(workouts.length - novelCount)

      addImportedWorkouts(workouts)

      if (program && programStartDate) {
        const { confirmed, pending } = autoMatchWorkouts(
          workouts,
          program,
          programStartDate,
          workoutMatches
        )
        confirmed.forEach((m) => addAutoMatch(m.importedWorkoutId, m.sessionKey))
        setPendingMatches(pending)

        if (linkToSession) {
          const wasLinked = confirmed.some((m) => m.sessionKey === linkToSession)
          if (wasLinked) {
            setLinkedSuccess(linkToSession)
          } else {
            const dashIdx = linkToSession.indexOf('-')
            const weekNumber = parseInt(linkToSession.slice(0, dashIdx), 10)
            const dayName = linkToSession.slice(dashIdx + 1)
            const weekIdx = program.weeks.findIndex(w => w.week_number === weekNumber)
            const calDate = weekIdx >= 0 ? sessionCalendarDate(programStartDate, weekIdx, dayName) : ''
            const dateWorkouts = workouts.filter((w) => w.date === calDate)
            if (dateWorkouts.length > 0) {
              setActivePending({
                importedWorkout: dateWorkouts[0],
                candidateSessionKeys: [linkToSession],
              })
            }
          }
        }
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
  const matchedCount = workoutMatches.filter((m) => m.matchConfidence !== 'rejected').length

  const subTabs: { id: SubTab; label: string }[] = [
    { id: 'import',  label: 'Import' },
    { id: 'history', label: 'History' },
    { id: 'matched', label: matchedCount > 0 ? `Matched (${matchedCount})` : 'Matched' },
  ]

  return (
    <motion.div
      key="workout-import"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <ArrowDownToLine className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Import Workouts</h1>
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <TabSelector active={activeTab} onChange={setActiveTab} tabs={subTabs} />
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'import' && (
          <ImportTab
            status={status}
            errorMsg={errorMsg}
            parsed={parsed}
            duplicateCount={duplicateCount}
            pendingMatches={pendingMatches}
            linkedSuccess={linkedSuccess}
            linkToSession={linkToSession}
            activePending={activePending}
            hasProgram={!!program}
            onDrop={onDrop}
            onFileChange={onFileChange}
            setActivePending={setActivePending}
            navigate={navigate}
          />
        )}
        {activeTab === 'history' && (
          <HistoryTab
            allImported={allImported}
            matchStatus={matchStatus}
            pendingMatches={pendingMatches}
            activePending={activePending}
            setActivePending={setActivePending}
            removeImportedWorkout={removeImportedWorkout}
            navigate={navigate}
          />
        )}
        {activeTab === 'matched' && (
          <MatchedTab
            workoutMatches={workoutMatches}
            importedWorkouts={importedWorkouts}
            currentProgram={program ?? null}
            navigate={navigate}
          />
        )}
      </div>
    </motion.div>
  )
}

// ── Program Start Date Input ───────────────────────────────────────────────────

function ProgramStartDateInput() {
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const setProgramStartDate = useProgramStore((s) => s.setProgramStartDate)

  return (
    <div className="flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-3">
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
