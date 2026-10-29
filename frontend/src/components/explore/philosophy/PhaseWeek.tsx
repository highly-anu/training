import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import type { DescribedItem, DescribedModule, DescribedTemplateDay, DescribedWeek } from '@/api/types'
import { SessionsPerWeekRows } from '@/components/explore/SessionsPerWeekRows'
import { useExploreNavigate } from '@/components/explore/topics'
import { cn } from '@/lib/utils'
import { Advice } from './Advice'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'

/** A stripe in the colours of what the session holds, like a calendar card's. */
function Stripe({ modalities }: { modalities: (string | null)[] }) {
  return (
    <div className="flex h-1 w-full">
      {modalities.map((m, i) => <div key={i} className="flex-1" style={{ backgroundColor: modalityHex(m) }} />)}
    </div>
  )
}

function TemplateDay({ day }: { day: DescribedTemplateDay }) {
  if (day.rest) {
    return (
      <div className="rounded-md border border-dashed border-border/50 px-2 py-2 text-[11px] text-muted-foreground/60 min-h-16">
        <p className="text-[10px] font-medium uppercase tracking-wider">{day.day.slice(0, 3)}</p>
        <p className="mt-1">Rest</p>
      </div>
    )
  }
  return (
    <div className="rounded-md border border-border/50 bg-card/60 overflow-hidden min-h-16">
      <Stripe modalities={day.pieces.map((p) => p.modality)} />
      <div className="px-2 py-1.5 space-y-1">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">{day.day.slice(0, 3)}</p>
        {day.pieces.map((p) => (
          <p key={p.category} className="text-[11px] font-medium leading-tight" title={modalityLabel(p.modality)}>{p.name}</p>
        ))}
        <div className="flex flex-wrap gap-1">
          {day.warmUp && <span className="text-[9px] text-muted-foreground">+ warm-up</span>}
          {day.light && <span className="text-[9px] rounded bg-muted px-1 text-muted-foreground">light</span>}
        </div>
      </div>
    </div>
  )
}

function TemplateWeeks({ week }: { week: Extract<DescribedWeek, { kind: 'template' }> }) {
  const [index, setIndex] = useState(0)
  const days = week.weeks[Math.min(index, week.weeks.length - 1)] ?? []
  const many = week.weeks.length > 1
  return (
    <div className="space-y-2">
      {many && (
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
          <button type="button" aria-label="Previous week" disabled={index === 0}
            onClick={() => setIndex((i) => i - 1)} className="rounded p-0.5 hover:bg-muted disabled:opacity-30">
            <ChevronLeft className="size-3.5" />
          </button>
          <span>Week {index + 1} of {week.weeks.length} — the source writes each week of the phase</span>
          <button type="button" aria-label="Next week" disabled={index === week.weeks.length - 1}
            onClick={() => setIndex((i) => i + 1)} className="rounded p-0.5 hover:bg-muted disabled:opacity-30">
            <ChevronRight className="size-3.5" />
          </button>
        </div>
      )}
      <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4 lg:grid-cols-7">
        {days.map((d) => <TemplateDay key={d.day} day={d} />)}
      </div>
      {(week.warmUp || week.dropOrder.length > 0) && (
        <p className="text-[10px] text-muted-foreground leading-relaxed">
          {week.warmUp && <>A day opens with a workout from {week.warmUp}. </>}
          {week.dropOrder.length > 0 && <>With fewer days, these go first: {week.dropOrder.slice(0, 4).join(', ')}{week.dropOrder.length > 4 ? '…' : ''}.</>}
        </p>
      )}
    </div>
  )
}

function Items({ items }: { items: DescribedItem[] }) {
  const open = useExploreNavigate()
  return (
    <ul className="space-y-1">
      {items.map((it, i) => (
        <li key={`${it.exercise}-${i}`} className="text-[11px] leading-snug">
          <button type="button" onClick={() => open('exercises', it.exercise)}
            className="font-medium text-foreground/90 hover:underline text-left">{it.name}</button>
          {it.prescription && <span className="font-mono text-[10px] text-muted-foreground"> {it.prescription}</span>}
          {it.optional && <span className="text-[9px] text-muted-foreground"> · optional</span>}
          {it.alternatives.length > 0 && (
            <span className="text-[10px] text-muted-foreground/70"> · or {it.alternatives.join(', ')}</span>
          )}
          {it.note && <p className="text-[10px] text-muted-foreground/80 line-clamp-2" title={it.note}>{it.note}</p>}
        </li>
      ))}
    </ul>
  )
}

const perWeekText = (m: DescribedModule) => {
  if (m.perWeekByDays) {
    const rows = Object.entries(m.perWeekByDays).filter(([, n]) => n > 0)
    return rows.length ? `${Math.min(...rows.map(([, n]) => n))}–${Math.max(...rows.map(([, n]) => n))}×/wk by days` : null
  }
  return m.perWeek ? `${m.perWeek}×/wk` : null
}

function ModuleCard({ module: m }: { module: DescribedModule }) {
  const [variant, setVariant] = useState(0)
  const v = m.variants[Math.min(variant, m.variants.length - 1)]
  return (
    <div className={cn('rounded-md border bg-card/60 overflow-hidden', m.optional || m.whenMastered ? 'border-dashed border-border/60' : 'border-border/50')}>
      <Stripe modalities={[m.modality]} />
      <div className="px-3 py-2 space-y-1.5">
        <div className="flex items-baseline justify-between gap-2 flex-wrap">
          <p className="text-xs font-semibold">{m.name}</p>
          <span className="text-[10px] font-mono text-muted-foreground">{perWeekText(m)}</span>
        </div>
        <div className="flex flex-wrap gap-1 text-[9px]">
          <span className="rounded px-1 py-0.5" style={{ color: modalityHex(m.modality), backgroundColor: `${modalityHex(m.modality)}18` }}>
            {modalityLabel(m.modality)}
          </span>
          {m.optional && <span className="rounded bg-muted px-1 py-0.5 text-muted-foreground">optional</span>}
          {m.whenMastered && (
            <span className="rounded bg-muted px-1 py-0.5 text-muted-foreground">once {m.requires.join(', ') || 'mastered'} is confirmed</span>
          )}
          {m.maxRpe != null && <span className="rounded bg-muted px-1 py-0.5 text-muted-foreground">RPE ≤ {m.maxRpe}</span>}
        </div>
        <p className="text-[10px] text-muted-foreground">Progresses by {m.progression}.</p>
        {m.periods.length > 0 && (
          <p className="text-[10px] text-muted-foreground">
            Cycles: {m.periods.map((p) => `${p.name} ${p.weeks} wk`).join(' · ')}
          </p>
        )}
        {m.variants.length > 0 && v && (
          <div className="space-y-1.5">
            {m.variants.length > 1 && (
              <div className="flex flex-wrap gap-1">
                {m.variants.map((x, i) => (
                  <button key={x.id} type="button" onClick={() => setVariant(i)}
                    className={cn('rounded border px-1.5 py-0.5 text-[10px] transition-colors',
                      i === variant ? 'border-primary/40 bg-primary/10 text-foreground' : 'border-border/50 text-muted-foreground hover:bg-muted')}>
                    {x.name}
                  </button>
                ))}
              </div>
            )}
            <Items items={v.items} />
          </div>
        )}
        {m.items.length > 0 && <Items items={m.items} />}
        <Advice advice={m.advice} byLevel={m.adviceByLevel} className="text-[10px]" />
      </div>
    </div>
  )
}

/** What a phase's week holds, from what builds it: the source's own days,
 *  a training contract's modules, or the framework's sessions per week. */
export function PhaseWeek({ week }: { week: DescribedWeek }) {
  if (week.kind === 'template') return <TemplateWeeks week={week} />
  if (week.kind === 'contract') {
    return (
      <div className="grid gap-2 sm:grid-cols-2">
        {week.modules.map((m) => <ModuleCard key={m.id} module={m} />)}
      </div>
    )
  }
  return (
    <SessionsPerWeekRows sessionsPerWeek={Object.fromEntries(week.sessions.map((s) => [s.modality, s.perWeek]))} />
  )
}
