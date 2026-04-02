import { useState } from 'react'
import { format } from 'date-fns'
import { CheckCircle2, ChevronDown, ChevronUp } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useBioStore } from '@/store/bioStore'

export function DailyCheckin() {
  const today = format(new Date(), 'yyyy-MM-dd')
  const existing = useBioStore((s) => s.dailyBioLogs[today])
  const upsertDailyBio = useBioStore((s) => s.upsertDailyBio)

  const [rhr, setRhr] = useState(existing?.restingHR?.toString() ?? '')
  const [hrv, setHrv] = useState(existing?.hrv?.toString() ?? '')
  const [notes, setNotes] = useState(existing?.notes ?? '')
  const [sleepH, setSleepH] = useState(
    existing?.sleepDurationMin != null ? Math.floor(existing.sleepDurationMin / 60).toString() : ''
  )
  const [sleepM, setSleepM] = useState(
    existing?.sleepDurationMin != null ? (existing.sleepDurationMin % 60).toString() : ''
  )
  const [showSleep, setShowSleep] = useState(existing?.sleepDurationMin != null)
  const [saved, setSaved] = useState(false)

  function handleSave() {
    const sleepDurationMin =
      sleepH || sleepM
        ? (parseInt(sleepH || '0', 10) * 60) + parseInt(sleepM || '0', 10)
        : undefined
    upsertDailyBio({
      date: today,
      restingHR: rhr ? parseFloat(rhr) : undefined,
      hrv: hrv ? parseFloat(hrv) : undefined,
      notes: notes || undefined,
      sleepDurationMin,
      source: 'manual',
    })
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  const inputCls =
    'h-9 w-full rounded-md border border-border bg-background px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary'

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold">Today's Check-in</h2>
        <span className="text-xs text-muted-foreground">{format(new Date(), 'EEEE, MMM d')}</span>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1">
          <label className="text-xs text-muted-foreground">Resting HR (bpm)</label>
          <input
            type="number"
            min={30}
            max={120}
            step={1}
            placeholder="e.g. 52"
            value={rhr}
            onChange={(e) => setRhr(e.target.value)}
            className={inputCls}
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-muted-foreground">HRV — RMSSD (ms)</label>
          <input
            type="number"
            min={0}
            max={300}
            step={1}
            placeholder="e.g. 68"
            value={hrv}
            onChange={(e) => setHrv(e.target.value)}
            className={inputCls}
          />
        </div>
      </div>

      {/* Sleep — optional, collapsible */}
      <div>
        <button
          type="button"
          onClick={() => setShowSleep((v) => !v)}
          className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          {showSleep ? <ChevronUp className="size-3" /> : <ChevronDown className="size-3" />}
          Sleep duration (optional)
        </button>
        {showSleep && (
          <div className="flex gap-2 mt-2">
            <div className="space-y-1 flex-1">
              <label className="text-xs text-muted-foreground">Hours</label>
              <input
                type="number"
                min={0}
                max={16}
                step={1}
                placeholder="7"
                value={sleepH}
                onChange={(e) => setSleepH(e.target.value)}
                className={inputCls}
              />
            </div>
            <div className="space-y-1 flex-1">
              <label className="text-xs text-muted-foreground">Minutes</label>
              <input
                type="number"
                min={0}
                max={59}
                step={5}
                placeholder="30"
                value={sleepM}
                onChange={(e) => setSleepM(e.target.value)}
                className={inputCls}
              />
            </div>
          </div>
        )}
      </div>

      <textarea
        rows={2}
        placeholder="How do you feel today? (optional)"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        className="w-full resize-none rounded-md border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary"
      />

      <Button
        size="sm"
        onClick={handleSave}
        disabled={!rhr && !hrv && !sleepH && !sleepM}
        className="w-full"
      >
        {saved ? (
          <>
            <CheckCircle2 className="size-3.5 mr-1.5" /> Saved
          </>
        ) : (
          'Save Check-in'
        )}
      </Button>
    </div>
  )
}
