import { useState } from 'react'
import { CheckCircle2, AlertTriangle, XCircle, Info, ChevronDown, ChevronUp } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useFeasibility } from '@/hooks/useFeasibility'
import { useBuilderStore } from '@/store/builderStore'
import type { FeasibilitySignal } from '@/lib/feasibility'

interface FeasibilityPanelProps {
  mode: 'compact' | 'full'
}

// ── Signal pill (compact mode) ────────────────────────────────────────────────

function SignalPill({
  signal,
  onQuickFix,
}: {
  signal: FeasibilitySignal
  onQuickFix: (s: FeasibilitySignal) => void
}) {
  const [open, setOpen] = useState(false)

  const isOk = signal.severity === 'info' && signal.code.endsWith('_OK')

  const colors = isOk
    ? 'bg-emerald-500/10 text-emerald-600 border-emerald-500/20 dark:text-emerald-400'
    : signal.severity === 'error'
      ? 'bg-destructive/10 text-destructive border-destructive/20'
      : signal.severity === 'warning'
        ? 'bg-amber-500/10 text-amber-600 border-amber-500/20 dark:text-amber-400'
        : 'bg-muted text-muted-foreground border-border'

  const Icon = isOk
    ? CheckCircle2
    : signal.severity === 'error'
      ? XCircle
      : signal.severity === 'warning'
        ? AlertTriangle
        : Info

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => !isOk && setOpen((v) => !v)}
        className={cn(
          'inline-flex items-center gap-1.5 px-2 py-1 rounded-full border text-[11px] font-medium transition-colors',
          colors,
          !isOk && 'hover:opacity-80 cursor-pointer',
          isOk && 'cursor-default',
        )}
      >
        <Icon className="size-3 shrink-0" />
        <span>{signal.label}</span>
        {!isOk && (open ? <ChevronUp className="size-2.5 opacity-60" /> : <ChevronDown className="size-2.5 opacity-60" />)}
      </button>

      {open && (
        <div className={cn(
          'absolute top-full left-0 z-10 mt-1.5 w-72 rounded-lg border bg-card p-3 shadow-md space-y-2',
        )}>
          <p className="text-xs text-foreground leading-relaxed">{signal.message}</p>
          {signal.suggestion && (
            <p className="text-[11px] text-muted-foreground leading-relaxed">{signal.suggestion}</p>
          )}
          {signal.quickFix && (
            <button
              type="button"
              onClick={() => {
                onQuickFix(signal)
                setOpen(false)
              }}
              className="text-[11px] font-medium text-primary hover:underline"
            >
              {signal.quickFix.label} →
            </button>
          )}
        </div>
      )}
    </div>
  )
}

// ── Signal row (full mode) ─────────────────────────────────────────────────────

function SignalRow({
  signal,
  onQuickFix,
}: {
  signal: FeasibilitySignal
  onQuickFix: (s: FeasibilitySignal) => void
}) {
  const isOk = signal.severity === 'info' && signal.code.endsWith('_OK')

  const Icon = isOk
    ? CheckCircle2
    : signal.severity === 'error'
      ? XCircle
      : signal.severity === 'warning'
        ? AlertTriangle
        : Info

  const iconColor = isOk
    ? 'text-emerald-500'
    : signal.severity === 'error'
      ? 'text-destructive'
      : signal.severity === 'warning'
        ? 'text-amber-500'
        : 'text-muted-foreground'

  if (isOk) return null  // don't show OK rows in full mode — only surface issues

  return (
    <div className="flex gap-3 py-3 border-b last:border-0">
      <Icon className={cn('size-4 shrink-0 mt-0.5', iconColor)} />
      <div className="flex-1 min-w-0 space-y-1">
        <p className="text-sm text-foreground leading-snug">{signal.message}</p>
        {signal.suggestion && (
          <p className="text-xs text-muted-foreground leading-relaxed">{signal.suggestion}</p>
        )}
        {signal.quickFix && (
          <button
            type="button"
            onClick={() => onQuickFix(signal)}
            className="text-xs font-medium text-primary hover:underline mt-0.5"
          >
            {signal.quickFix.label} →
          </button>
        )}
      </div>
    </div>
  )
}

// ── Panel ─────────────────────────────────────────────────────────────────────

export function FeasibilityPanel({ mode }: FeasibilityPanelProps) {
  const signals = useFeasibility()
  const updateConstraints = useBuilderStore((s) => s.updateConstraints)
  const setNumWeeks = useBuilderStore((s) => s.setNumWeeks)

  if (!signals.length) return null

  function applyQuickFix(signal: FeasibilitySignal) {
    if (!signal.quickFix) return
    if (signal.quickFix.constraintPatch) updateConstraints(signal.quickFix.constraintPatch)
    if (signal.quickFix.numWeeks != null) setNumWeeks(signal.quickFix.numWeeks)
  }

  if (mode === 'compact') {
    // Hide OK signals — coverage bar in WeeklyScheduler already shows this info
    const issues = signals.filter((s) => !(s.severity === 'info' && s.code.endsWith('_OK')))
    if (!issues.length) return null
    return (
      <div className="flex flex-wrap gap-2">
        {issues.map((s) => (
          <SignalPill key={s.code} signal={s} onQuickFix={applyQuickFix} />
        ))}
      </div>
    )
  }

  // full mode
  const hasIssues = signals.some((s) => s.severity !== 'info' || !s.code.endsWith('_OK'))
  if (!hasIssues) return null

  return (
    <div className="rounded-xl border bg-card overflow-hidden">
      <div className="px-4 py-3 border-b bg-muted/30">
        <p className="text-sm font-semibold">Before you generate</p>
        <p className="text-xs text-muted-foreground">Review these compatibility notes for your selected goal</p>
      </div>
      <div className="px-4 divide-y divide-border">
        {signals.map((s) => (
          <SignalRow key={s.code} signal={s} onQuickFix={applyQuickFix} />
        ))}
      </div>
    </div>
  )
}
