import { useState, useCallback, useMemo } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Upload, CheckCircle2, AlertCircle, Link2, Inbox, ClipboardList, ArrowDownToLine } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet'
import { MatchConfirmDialog } from '@/components/bio/MatchConfirmDialog'
import { SuggestionRow } from '@/components/bio/SuggestionRow'
import { EmptyState } from '@/components/shared/EmptyState'
import { WorkoutList } from '@/components/workout/WorkoutList'
import type { WorkoutMatchStatus } from '@/components/workout/WorkoutRow'
import { parseAppleHealthXml, parseStravaJson } from '@/lib/importParsers'
import { autoMatchWorkouts, sessionCalendarDate } from '@/lib/workoutMatcher'
import { parseSessionKey, sessionLabel } from '@/lib/sessionKeys'
import { formatActivityType } from '@/lib/activityType'
import { parseWorkoutFile, startAsyncParse, pollParseJob } from '@/api/workouts'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { useCurrentProgram } from '@/api/programs'
import type { ImportedWorkout, PendingMatch } from '@/api/types'

/**
 * Log — the record of what happened and the decisions waiting on it.
 *
 * One list of recorded workouts (this used to be three: Import ▸ History,
 * Import ▸ Matched and Analytics ▸ Activity), the suggestions inbox, and
 * Import as an action rather than a page. Analytics interprets; this is the
 * ledger it reads.
 */

type LogTab = 'workouts' | 'suggestions'
type Filter = 'all' | 'matched' | 'unmatched' | 'pending'
type ParseStatus = 'idle' | 'parsing' | 'done' | 'error'

const LARGE_XML_BYTES = 50 * 1024 * 1024

// ── Tab selector ───────────────────────────────────────────────────────────────

function TabSelector({ active, onChange, tabs }: {
  active: LogTab
  onChange: (t: LogTab) => void
  tabs: { id: LogTab; label: string }[]
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

// ── Import panel (inside the sheet) ────────────────────────────────────────────

function ImportPanel({
  status, parseProgress, errorMsg, parsed, duplicateCount, pendingMatches,
  linkedSuccess, linkToSession, onDrop, onFileChange, onReview, onDone,
}: {
  status: ParseStatus
  parseProgress: { progress: number; stage: string } | null
  errorMsg: string
  parsed: ImportedWorkout[]
  duplicateCount: number
  pendingMatches: PendingMatch[]
  linkedSuccess: string | null
  linkToSession: string | null
  onDrop: (e: React.DragEvent) => void
  onFileChange: (e: React.ChangeEvent<HTMLInputElement>) => void
  onReview: (p: PendingMatch) => void
  onDone: () => void
}) {
  const novel = parsed.length - duplicateCount
  return (
    <div className="mt-4 space-y-6">
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
          <input type="file" accept=".fit,.xml,.json" onChange={onFileChange} className="sr-only" />
        </label>
      </div>

      {/* Link-to context */}
      {linkToSession && !linkedSuccess && status !== 'done' && (
        <div className="flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-4 py-3 text-sm text-primary">
          <Link2 className="size-4" />
          Importing for {sessionLabel(linkToSession)}
        </div>
      )}

      {/* Parse status */}
      {status === 'parsing' && (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent shrink-0" />
            <span>{parseProgress?.stage ?? 'Parsing file…'}</span>
          </div>
          {parseProgress && parseProgress.progress > 0 && (
            <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
              <div
                className="h-full rounded-full bg-primary transition-all duration-500"
                style={{ width: `${Math.round(parseProgress.progress * 100)}%` }}
              />
            </div>
          )}
        </div>
      )}
      {status === 'done' && (
        <div className="flex flex-wrap items-center gap-2 text-sm text-emerald-700 dark:text-emerald-300">
          <CheckCircle2 className="size-4" />
          {novel === 0 ? (
            <span className="text-muted-foreground">
              All {parsed.length} workout{parsed.length !== 1 ? 's' : ''} already imported
            </span>
          ) : (
            <>
              Imported {novel} workout{novel !== 1 ? 's' : ''}
              {duplicateCount > 0 && (
                <span className="text-muted-foreground">({duplicateCount} already imported)</span>
              )}
            </>
          )}
        </div>
      )}
      {status === 'error' && (
        <div className="flex items-center gap-2 text-sm text-red-700 dark:text-red-300">
          <AlertCircle className="size-4" />
          {errorMsg}
        </div>
      )}

      {/* Linked success */}
      {linkedSuccess && (
        <div className="flex items-center justify-between gap-3 rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-4 py-3">
          <div className="flex items-center gap-2 text-sm text-emerald-700 dark:text-emerald-300">
            <CheckCircle2 className="size-4" />
            Workout linked to {sessionLabel(linkedSuccess)}
          </div>
          <Button size="sm" variant="outline" onClick={onDone}>Done</Button>
        </div>
      )}

      {/* Decisions waiting */}
      {pendingMatches.length > 0 && (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3">
          <p className="text-sm font-medium text-amber-700 dark:text-amber-300 mb-2">
            {pendingMatches.length} workout{pendingMatches.length !== 1 ? 's need' : ' needs'} a match decision
          </p>
          <div className="flex flex-wrap gap-2">
            {pendingMatches.map((p) => (
              <Button
                key={p.importedWorkout.id}
                size="sm"
                variant="outline"
                onClick={() => onReview(p)}
                className="text-xs border-amber-500/40 text-amber-700 dark:text-amber-300 hover:bg-amber-500/10"
              >
                <Link2 className="size-3 mr-1" />
                {p.importedWorkout.date} — {formatActivityType(p.importedWorkout.activityType)}
              </Button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// ── Suggestions ────────────────────────────────────────────────────────────────

/**
 * Weak matches waiting for a decision: the browser's own auto-matcher after an
 * upload, and the server's suggestions (GET /api/health/matches/suggestions)
 * written by the Garmin webhook and the iOS Apple Health relay.
 */
function SuggestionsTab({ pendingMatches, onReview, onDismiss }: {
  pendingMatches: PendingMatch[]
  onReview: (p: PendingMatch) => void
  onDismiss: (id: string) => void
}) {
  if (pendingMatches.length === 0) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <EmptyState
          icon={<Inbox className="size-8 opacity-40" />}
          title="No suggestions"
          description="Workouts that look like a planned session but could not be matched with confidence wait here for your decision."
        />
      </div>
    )
  }
  return (
    <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
      <div>
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
          Needs a decision ({pendingMatches.length})
        </h2>
        <ul className="space-y-2">
          {pendingMatches.map((p) => (
            <SuggestionRow
              key={p.importedWorkout.id}
              match={p}
              onReview={() => onReview(p)}
              onDismiss={() => onDismiss(p.importedWorkout.id)}
            />
          ))}
        </ul>
      </div>
    </div>
  )
}

// ── Page ───────────────────────────────────────────────────────────────────────

export function Log() {
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const linkToSession = searchParams.get('linkTo')
  const activeTab: LogTab = searchParams.get('tab') === 'suggestions' ? 'suggestions' : 'workouts'
  // ?linkTo= (from a session) and ?import=1 (from Home) open the sheet directly.
  const [importOpen, setImportOpen] = useState(() => !!linkToSession || searchParams.get('import') === '1')
  const [filter, setFilter] = useState<Filter>('all')

  const [status, setStatus] = useState<ParseStatus>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [parsed, setParsed] = useState<ImportedWorkout[]>([])
  const [parseProgress, setParseProgress] = useState<{ progress: number; stage: string } | null>(null)
  const [duplicateCount, setDuplicateCount] = useState(0)
  const [linkedSuccess, setLinkedSuccess] = useState<string | null>(null)
  const [activePending, setActivePending] = useState<PendingMatch | null>(null)

  const addImportedWorkouts = useBioStore((s) => s.addImportedWorkouts)
  const addAutoMatch = useBioStore((s) => s.addAutoMatch)
  const setPendingMatches = useBioStore((s) => s.setPendingMatches)
  const removeImportedWorkout = useBioStore((s) => s.removeImportedWorkout)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const pendingMatches = useBioStore((s) => s.pendingMatches)
  const dismissSuggestion = useBioStore((s) => s.dismissSuggestion)

  const program = useCurrentProgram()
  const programStartDate = useProgramStore((s) => s.programStartDate)

  function setActiveTab(tab: LogTab) {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (tab === 'workouts') next.delete('tab')
        else next.set('tab', tab)
        return next
      },
      { replace: true }
    )
  }

  function closeImport() {
    setImportOpen(false)
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.delete('linkTo')
        next.delete('import')
        return next
      },
      { replace: true }
    )
  }

  // Which planned session each matched workout belongs to, for the row label.
  const sessionNames = useMemo(() => {
    const names = new Map<string, string>()
    for (const week of program?.weeks ?? []) {
      for (const [dayName, daySessions] of Object.entries(week.schedule)) {
        const dayKey = `${week.week_number}-${dayName}`
        daySessions.forEach((s, si) => {
          const label = `Wk ${week.week_number} ${dayName} — ${s.archetype?.name ?? s.modality.replace(/_/g, ' ')}`
          names.set(`${dayKey}-${si}`, label)
          if (si === 0) names.set(dayKey, label)   // legacy day-level keys
        })
      }
    }
    return names
  }, [program])

  const matchFor = (id: string) => workoutMatches.find((m) => m.importedWorkoutId === id)

  function statusFor(w: ImportedWorkout): WorkoutMatchStatus {
    const match = matchFor(w.id)
    if (match && match.matchConfidence !== 'rejected') return 'matched'
    if (match?.matchConfidence === 'rejected') return 'unmatched'
    if (pendingMatches.some((p) => p.importedWorkout.id === w.id)) return 'pending'
    return 'unmatched'
  }

  function sessionLabelFor(w: ImportedWorkout): string | null {
    const match = matchFor(w.id)
    if (!match || match.matchConfidence === 'rejected') return null
    return sessionNames.get(match.sessionKey) ?? sessionLabel(match.sessionKey)
  }

  const processFile = useCallback(async (file: File) => {
    setStatus('parsing')
    setErrorMsg('')
    setParseProgress(null)
    try {
      let workouts: ImportedWorkout[] = []

      if (file.name.endsWith('.xml')) {
        if (file.size > LARGE_XML_BYTES) {
          setParseProgress({ progress: 0, stage: 'Uploading file…' })
          const jobId = await startAsyncParse(file)
          workouts = await pollParseJob(jobId, (progress, stage) => setParseProgress({ progress, stage }))
        } else {
          workouts = parseAppleHealthXml(await file.text())
        }
      } else if (file.name.endsWith('.json')) {
        workouts = parseStravaJson(JSON.parse(await file.text()))
      } else if (file.name.endsWith('.fit')) {
        workouts = await parseWorkoutFile(file)
      } else {
        throw new Error('Unsupported file type. Please upload a .fit, .xml (Apple Health), or .json (Strava) file.')
      }

      setParsed(workouts)
      const existingIds = new Set(importedWorkouts.map((w) => w.id))
      const novelCount = workouts.filter((w) => !existingIds.has(w.id)).length
      setDuplicateCount(workouts.length - novelCount)
      addImportedWorkouts(workouts)

      if (program && programStartDate) {
        const { confirmed, pending } = autoMatchWorkouts(workouts, program, programStartDate, workoutMatches)
        confirmed.forEach((m) => addAutoMatch(m.importedWorkoutId, m.sessionKey))
        setPendingMatches(pending)

        if (linkToSession) {
          const wasLinked = confirmed.some((m) => m.sessionKey === linkToSession)
          if (wasLinked) {
            setLinkedSuccess(linkToSession)
          } else {
            const parsedKey = parseSessionKey(linkToSession)
            const weekIdx = parsedKey ? program.weeks.findIndex((w) => w.week_number === parsedKey.weekNumber) : -1
            const calDate = parsedKey && weekIdx >= 0 ? sessionCalendarDate(programStartDate, weekIdx, parsedKey.dayName) : ''
            const dateWorkouts = workouts.filter((w) => w.date === calDate)
            if (dateWorkouts.length > 0) {
              setActivePending({ importedWorkout: dateWorkouts[0], candidateSessionKeys: [linkToSession] })
            }
          }
        }
      }

      setStatus('done')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Unknown error')
      setStatus('error')
    }
  }, [importedWorkouts, program, programStartDate, workoutMatches, linkToSession, addImportedWorkouts, addAutoMatch, setPendingMatches])

  const onDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) void processFile(file)
  }, [processFile])

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void processFile(file)
    e.target.value = ''
  }

  const allImported = useMemo(
    () => importedWorkouts.slice().sort((a, b) => b.date.localeCompare(a.date)),
    [importedWorkouts]
  )
  const counts = useMemo(() => {
    const c = { all: allImported.length, matched: 0, unmatched: 0, pending: 0 }
    for (const w of allImported) c[statusFor(w)]++
    return c
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allImported, workoutMatches, pendingMatches])
  const visible = filter === 'all' ? allImported : allImported.filter((w) => statusFor(w) === filter)

  const filters: { id: Filter; label: string }[] = [
    { id: 'all',       label: `All (${counts.all})` },
    { id: 'matched',   label: `Matched (${counts.matched})` },
    { id: 'unmatched', label: `Unmatched (${counts.unmatched})` },
    ...(counts.pending > 0 ? [{ id: 'pending' as Filter, label: `Pending (${counts.pending})` }] : []),
  ]
  const tabs: { id: LogTab; label: string }[] = [
    { id: 'workouts',    label: 'Workouts' },
    { id: 'suggestions', label: pendingMatches.length > 0 ? `Suggestions (${pendingMatches.length})` : 'Suggestions' },
  ]

  return (
    <motion.div
      key="log"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <ClipboardList className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Log</h1>
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <TabSelector active={activeTab} onChange={setActiveTab} tabs={tabs} />
        </div>
        <div className="ml-auto flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon"
            className="size-8"
            onClick={() => setImportOpen(true)}
            aria-label="Import workouts"
            title="Import workouts"
          >
            <ArrowDownToLine className="size-4" />
          </Button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'workouts' && (
          allImported.length === 0 ? (
            <div className="max-w-2xl mx-auto px-8 py-12">
              <EmptyState
                icon={<ArrowDownToLine className="size-8 opacity-40" />}
                title="No workouts yet"
                description="Connected sources import automatically. Upload a .fit, Apple Health .xml or Strava .json file to add one by hand."
                action={{ label: 'Import a file', onClick: () => setImportOpen(true) }}
              />
            </div>
          ) : (
            <div className="max-w-2xl mx-auto px-8 py-12 space-y-6">
              <div className="flex flex-wrap items-center gap-1">
                {filters.map((f) => (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => setFilter(f.id)}
                    className={cn(
                      'px-2.5 py-1 text-[11px] rounded border transition-colors',
                      filter === f.id
                        ? 'bg-primary/15 border-primary/40 text-primary'
                        : 'border-border text-muted-foreground hover:bg-muted'
                    )}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
              {visible.length === 0 ? (
                <p className="text-sm text-muted-foreground">No {filter} workouts.</p>
              ) : (
                <WorkoutList
                  workouts={visible}
                  statusFor={statusFor}
                  sessionLabelFor={sessionLabelFor}
                  onOpen={(w) => navigate(`/log/${encodeURIComponent(w.id)}`, { state: { workout: w } })}
                  onMatch={(w) => setActivePending(pendingMatches.find((p) => p.importedWorkout.id === w.id) ?? null)}
                  onRemove={(w) => removeImportedWorkout(w.id)}
                />
              )}
            </div>
          )
        )}
        {activeTab === 'suggestions' && (
          <SuggestionsTab
            pendingMatches={pendingMatches}
            onReview={setActivePending}
            onDismiss={dismissSuggestion}
          />
        )}
      </div>

      {/* Import — an action, not a place */}
      <Sheet open={importOpen} onOpenChange={(open) => (open ? setImportOpen(true) : closeImport())}>
        <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
          <SheetHeader>
            <SheetTitle>Import workouts</SheetTitle>
            <SheetDescription>
              Garmin, Strava and Apple Health connections import on their own; this is for files.
            </SheetDescription>
          </SheetHeader>
          <ImportPanel
            status={status}
            parseProgress={parseProgress}
            errorMsg={errorMsg}
            parsed={parsed}
            duplicateCount={duplicateCount}
            pendingMatches={pendingMatches}
            linkedSuccess={linkedSuccess}
            linkToSession={linkToSession}
            onDrop={onDrop}
            onFileChange={onFileChange}
            onReview={setActivePending}
            onDone={closeImport}
          />
        </SheetContent>
      </Sheet>

      <MatchConfirmDialog match={activePending} onClose={() => setActivePending(null)} />
    </motion.div>
  )
}
