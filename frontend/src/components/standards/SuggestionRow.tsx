import { useState } from 'react'
import { format, parseISO } from 'date-fns'
import { Check, Pencil, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { parseSessionKey } from '@/lib/sessionKeys'
import { useDecideSuggestion, useStandardSuggestions } from '@/api/standards'
import type { StandardSuggestion } from '@/api/types'
import { StandardLevelBadge } from './StandardLadder'

/**
 * A result a logged session suggests, with the athlete's three answers: Save,
 * correct it and save, or "Not a test". The same row on Profile ▸ Standards'
 * "To confirm", on Today and under the test slot that produced it; the
 * phone's is `StandardSuggestionRow` (design-system §6.32). Every word and
 * number is the server's — the value, its level, what it would follow.
 */
export function SuggestionRow({ suggestion: s, compact = false, showName = true }: {
  suggestion: StandardSuggestion
  /** Under the slot it came from: no session line. */
  compact?: boolean
  showName?: boolean
}) {
  const decide = useDecideSuggestion()
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState(s.valueText)

  const from = [
    s.sessionName ?? (s.origin === 'derived_single' ? 'A single in training'
      : s.origin === 'best_effort' ? 'An imported run' : 'A logged session'),
    s.loggedOn ? format(parseISO(s.loggedOn), 'EEE d MMM') : null,
  ].filter(Boolean).join(' · ')
  const was = s.current ? `was ${s.current.valueText}` : 'first result'

  function save() {
    const typed = editing && text.trim() !== s.valueText ? text.trim() : undefined
    decide.mutate({ id: s.id, action: 'confirm', text: typed }, { onSuccess: () => setEditing(false) })
  }

  return (
    <div className={cn('rounded-md border border-primary/30 bg-primary/5 px-3 py-2 text-xs', compact && 'mt-1.5 px-2 py-1.5')}
         aria-label={`Suggested result: ${s.name}`}>
      <div className="flex flex-wrap items-center gap-x-1.5 gap-y-1">
        {showName && <span className="font-medium text-foreground">{s.shortName ?? s.name}</span>}
        {editing ? (
          <input
            autoFocus
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') save(); if (e.key === 'Escape') setEditing(false) }}
            className="h-6 w-20 rounded border border-border bg-background px-1.5 text-center text-[11px] tabular-nums focus:outline-none focus:ring-1 focus:ring-primary"
            aria-label={`Correct ${s.name}`}
          />
        ) : (
          <span className="font-semibold tabular-nums text-foreground">{s.valueText}</span>
        )}
        <StandardLevelBadge level={s.level} domain={s.domain} />
        <span className="text-muted-foreground">
          · {s.replacesText ? `corrects ${s.replacesText}` : s.isBest && s.current ? 'new best' : was}
        </span>
      </div>
      {(!compact || s.inputText) && (
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {[s.inputText, compact ? null : from].filter(Boolean).join(' · ')}
        </p>
      )}
      <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
        <button type="button" onClick={save} disabled={decide.isPending}
                className="inline-flex items-center gap-1 rounded bg-primary px-2 py-0.5 text-[11px] font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-60">
          <Check className="size-3" aria-hidden="true" /> Save result
        </button>
        {!editing && (
          <button type="button" onClick={() => { setText(s.valueText); setEditing(true) }}
                  className="inline-flex items-center gap-1 rounded border border-border px-2 py-0.5 text-[11px] text-muted-foreground hover:bg-muted">
            <Pencil className="size-3" aria-hidden="true" /> Correct
          </button>
        )}
        <button type="button" onClick={() => decide.mutate({ id: s.id, action: 'dismiss' })} disabled={decide.isPending}
                className="inline-flex items-center gap-1 rounded border border-border px-2 py-0.5 text-[11px] text-muted-foreground hover:bg-muted disabled:opacity-60">
          <X className="size-3" aria-hidden="true" /> Not a test
        </button>
        {decide.isError && (
          <span role="alert" className="text-[11px] text-red-700 dark:text-red-300">
            {decide.error?.message || 'Could not save — try again'}
          </span>
        )}
      </div>
    </div>
  )
}

/** Under a test's scored slot: the suggestion its logged outcome produced. */
export function SessionSuggestion({ standardId, sessionKey }: { standardId: string; sessionKey: string }) {
  const { data: suggestions = [] } = useStandardSuggestions()
  const day = parseSessionKey(sessionKey)?.dayKey ?? sessionKey
  const s = suggestions.find((x) => x.benchmarkId === standardId && x.origin === 'test_slot'
    && (parseSessionKey(x.sessionKey ?? '')?.dayKey ?? x.sessionKey) === day)
  return s ? <SuggestionRow suggestion={s} compact showName={false} /> : null
}
