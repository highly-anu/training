import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { cn } from '@/lib/utils'
import type { ModalityId, WeekTrace, SessionTrace, SlotTrace, ProgressionEntry } from '@/api/types'

interface Props {
  weeks: WeekTrace[]
}

function FilterCounts({ counts }: { counts: Record<string, number> }) {
  return (
    <div className="flex flex-wrap gap-1">
      {Object.entries(counts).map(([k, v]) => (
        <Badge key={k} variant="outline" className="text-[10px] font-mono">
          {k}: {v}
        </Badge>
      ))}
    </div>
  )
}

function ArchetypeSelectionBlock({ trace }: { trace: SessionTrace['archetype'] }) {
  if (trace.candidates.length === 0) {
    return <p className="text-xs text-destructive">No archetype candidates found.</p>
  }
  return (
    <div className="space-y-2">
      <FilterCounts counts={trace.filter_counts} />
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="text-left text-muted-foreground">
              <th className="pb-1 pr-3">Archetype</th>
              <th className="pb-1 pr-3 text-right">Score</th>
              <th className="pb-1 pr-3 text-right">Equip</th>
              <th className="pb-1 pr-3 text-right">Source</th>
              <th className="pb-1 pr-3 text-right">Recency</th>
              <th className="pb-1 text-right">Injury</th>
            </tr>
          </thead>
          <tbody>
            {trace.candidates.map(c => (
              <tr
                key={c.id}
                className={cn(
                  'border-t border-border/30',
                  c.id === trace.selected_id ? 'bg-primary/5' : ''
                )}
              >
                <td className="py-1 pr-3 font-medium">
                  {c.id === trace.selected_id && (
                    <span className="text-primary mr-1">✓</span>
                  )}
                  {c.name || c.id}
                </td>
                <td className="py-1 pr-3 text-right font-mono font-bold">{c.score}</td>
                <td className="py-1 pr-3 text-right font-mono text-sky-400">{c.breakdown.equipment ?? 0}</td>
                <td className="py-1 pr-3 text-right font-mono text-emerald-400">{c.breakdown.source ?? 0}</td>
                <td className="py-1 pr-3 text-right font-mono text-amber-400">{c.breakdown.recency ?? 0}</td>
                <td className="py-1 text-right font-mono text-rose-400">{c.breakdown.injury_penalty ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function SlotRow({ slot }: { slot: SlotTrace }) {
  const [expanded, setExpanded] = useState(false)

  if (slot.meta) {
    return (
      <div className="flex items-center gap-2 py-1.5 px-2 text-xs text-muted-foreground">
        <span className="font-mono text-[10px] bg-muted px-1 rounded">meta</span>
        <span>{slot.slot_role}</span>
        <Badge variant="outline" className="text-[10px]">{slot.slot_type}</Badge>
      </div>
    )
  }

  return (
    <div className="border-b border-border/20 last:border-0">
      <button
        onClick={() => setExpanded(v => !v)}
        className="w-full flex items-center gap-2 py-1.5 px-2 text-xs text-left hover:bg-muted/40 rounded transition-colors"
      >
        <span className="font-mono text-muted-foreground w-5 shrink-0">{slot.slot_index}</span>
        <span className="font-medium">{slot.slot_role}</span>
        <Badge variant="outline" className="text-[10px] shrink-0">{slot.slot_type}</Badge>
        {slot.movement_pattern && (
          <span className="text-muted-foreground text-[10px]">({slot.movement_pattern})</span>
        )}
        <span className="ml-auto flex items-center gap-1.5 shrink-0">
          {slot.injury_blocked && (
            <Badge variant="destructive" className="text-[10px]">injury skip</Badge>
          )}
          {slot.selected_id ? (
            <span className="text-green-400 font-mono text-[10px]">{slot.selected_id}</span>
          ) : (
            <span className="text-destructive text-[10px]">no match</span>
          )}
          <span className="text-muted-foreground text-[10px]">
            ({slot.filter_counts.final ?? 0} candidates)
          </span>
          <span className="text-muted-foreground">{expanded ? '▲' : '▼'}</span>
        </span>
      </button>

      {expanded && (
        <div className="px-2 pb-3 space-y-2">
          <FilterCounts counts={slot.filter_counts} />
          {slot.candidates.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="text-left text-muted-foreground">
                    <th className="pb-1 pr-3">Exercise</th>
                    <th className="pb-1 pr-3 text-right">Score</th>
                    <th className="pb-1 pr-3 text-right">Recency</th>
                    <th className="pb-1 pr-3 text-right">Unlocks</th>
                    <th className="pb-1 text-right">Pattern</th>
                  </tr>
                </thead>
                <tbody>
                  {slot.candidates.map(c => (
                    <tr
                      key={c.id}
                      className={cn(
                        'border-t border-border/20',
                        c.id === slot.selected_id ? 'bg-primary/5' : ''
                      )}
                    >
                      <td className="py-0.5 pr-3 font-medium">
                        {c.id === slot.selected_id && (
                          <span className="text-primary mr-1">✓</span>
                        )}
                        {c.name || c.id}
                      </td>
                      <td className="py-0.5 pr-3 text-right font-mono font-bold">{c.score}</td>
                      <td className="py-0.5 pr-3 text-right font-mono text-amber-400">
                        {c.breakdown.recency_penalty ?? 0}
                      </td>
                      <td className="py-0.5 pr-3 text-right font-mono text-emerald-400">
                        {c.breakdown.unlocks_bonus ?? 0}
                      </td>
                      <td className="py-0.5 text-right font-mono text-sky-400">
                        {c.breakdown.pattern_bonus ?? 0}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">No candidates — {slot.injury_blocked ? 'movement pattern excluded by injury flag' : 'no exercises match slot constraints'}</p>
          )}
        </div>
      )}
    </div>
  )
}

function ProgressionBlock({ entries }: { entries: ProgressionEntry[] }) {
  const relevant = entries.filter(e => e.slot_type !== 'meta')
  if (relevant.length === 0) return null

  return (
    <div>
      <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-2">
        Load Calculation
      </p>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="text-left text-muted-foreground">
              <th className="pb-1 pr-3">Exercise</th>
              <th className="pb-1 pr-3">Role</th>
              <th className="pb-1 pr-3">Model</th>
              <th className="pb-1 pr-3 text-right">Wk</th>
              <th className="pb-1">Output</th>
            </tr>
          </thead>
          <tbody>
            {relevant.map((e, i) => (
              <tr key={i} className="border-t border-border/20">
                <td className="py-0.5 pr-3 font-medium">{e.exercise_name || e.exercise_id}</td>
                <td className="py-0.5 pr-3 text-muted-foreground">{e.slot_role}</td>
                <td className="py-0.5 pr-3 font-mono text-muted-foreground">{e.model}</td>
                <td className="py-0.5 pr-3 text-right font-mono">{e.week}</td>
                <td className="py-0.5 font-mono text-[10px] text-muted-foreground">
                  {Object.entries(e.output)
                    .map(([k, v]) => `${k}: ${v}`)
                    .join(' · ')}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

export function SessionsPanel({ weeks }: Props) {
  const [weekIdx, setWeekIdx] = useState(0)
  const [activeDay, setActiveDay] = useState<string | null>(null)

  const week = weeks[weekIdx]
  if (!week) return null

  const days = Object.keys(week.sessions).filter(d => week.sessions[d].length > 0)
  const currentDay = activeDay ?? days[0] ?? null

  return (
    <div className="space-y-4">
      {/* Week selector */}
      <div className="flex flex-wrap gap-1">
        {weeks.map((w, i) => (
          <button
            key={w.week_number}
            onClick={() => { setWeekIdx(i); setActiveDay(null) }}
            className={cn(
              'px-3 py-1 text-xs rounded-md border transition-colors',
              i === weekIdx
                ? 'bg-primary text-primary-foreground border-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            )}
          >
            W{w.week_number} · {w.phase}
          </button>
        ))}
      </div>

      {/* Day selector */}
      {days.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {days.map(day => (
            <button
              key={day}
              onClick={() => setActiveDay(day)}
              className={cn(
                'px-3 py-1 text-xs rounded-md border transition-colors',
                day === currentDay
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'border-border text-muted-foreground hover:bg-muted'
              )}
            >
              {day}
            </button>
          ))}
        </div>
      )}

      {/* Sessions for selected day */}
      {currentDay && (
        <div className="space-y-3">
          {week.sessions[currentDay]?.map((session, si) => (
            <Card key={si}>
              <CardHeader className="pb-2">
                <CardTitle className="flex flex-wrap items-center gap-2 text-sm">
                  <ModalityBadge modality={session.modality as ModalityId} />
                  <span className="font-mono text-xs text-muted-foreground">→</span>
                  <span className="text-xs font-mono">
                    {session.archetype.selected_id ?? (
                      <span className="text-destructive">no archetype</span>
                    )}
                  </span>
                  <span className="text-xs text-muted-foreground ml-auto">
                    {session.slots.filter(s => !s.meta).length} exercise slots
                  </span>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                {/* Archetype selection */}
                <div>
                  <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-2">
                    Archetype Selection
                  </p>
                  <ArchetypeSelectionBlock trace={session.archetype} />
                </div>

                {/* Exercise slots */}
                <div>
                  <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-1">
                    Exercise Selection — click to expand candidates
                  </p>
                  <div className="border border-border/30 rounded-md overflow-hidden">
                    {session.slots.map((slot, si) => (
                      <SlotRow key={si} slot={slot} />
                    ))}
                  </div>
                </div>

                {/* Progression */}
                <ProgressionBlock entries={session.progression} />
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
