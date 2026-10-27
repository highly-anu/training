import { useState } from 'react'
import { CalendarDays, CalendarRange, FlaskConical, Info, Repeat, Timer } from 'lucide-react'
import type { DescribedPhase, DescribedTrack, GlancePhase, GlanceTrack, PhilosophyDescription } from '@/api/types'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { cn } from '@/lib/utils'
import { InlinePanel, IntensityBar, LevelPips, MixLegend, PhaseBar, WeekGlyph } from './Glance'
import { PhaseWeek } from './PhaseWeek'

const LEVEL_WORDS: Record<string, string> = {
  novice: 'novices', intermediate: 'intermediates', advanced: 'advanced', elite: 'elite',
}

const span = (r: { min: number; max: number } | null, unit = '') =>
  !r ? '—' : r.min === r.max ? `${r.min}${unit}` : `${r.min}–${r.max}${unit}`

/** One track as a row: the same columns for every track, the phase bar on a
 *  scale shared by all of them, so tracks read — and later compare — at a glance. */
function TrackRow({ track, scale, selected, onSelect }: {
  track: GlanceTrack; scale: number; selected: boolean; onSelect: () => void
}) {
  return (
    <button type="button" onClick={onSelect} aria-pressed={selected}
      className={cn('grid w-full grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1.5 px-3 py-2 text-left transition-colors',
        'sm:grid-cols-[minmax(9rem,1.1fr)_auto_3.5rem_minmax(8rem,2fr)_4.5rem_auto]',
        selected ? 'bg-primary/10' : 'hover:bg-muted/30')}>
      <div className="min-w-0">
        <p className="truncate text-xs font-semibold">{track.name}</p>
        <p className="truncate text-[9px] text-muted-foreground">
          {track.primary ? 'main' : ''}{track.forLevels.length > 0 && `${track.primary ? ' · ' : ''}for ${track.forLevels.map((l) => LEVEL_WORDS[l]).join(', ')}`}
        </p>
      </div>
      <LevelPips levels={track.levels} />
      <span className="hidden text-right font-mono text-[11px] tabular-nums sm:block">
        {track.weeks}<span className="text-muted-foreground"> wk</span>{track.repeatable && <Repeat className="ml-0.5 inline size-2.5 text-muted-foreground" />}
      </span>
      <div className="col-span-2 sm:col-span-1">
        <PhaseBar phases={track.phases} scaleWeeks={scale} />
      </div>
      <span className="hidden font-mono text-[10px] text-muted-foreground sm:block">
        {span(track.daysPerWeek)} d · {span(track.minutes)}′
      </span>
      <div className="col-span-2 sm:col-span-1"><MixLegend mix={track.mix} max={4} /></div>
    </button>
  )
}

/** One phase as a card: its kind's colour, its weeks, its week as a glyph,
 *  how hard. The words open under the cards. */
function PhaseCard({ phase, selected, onOpen }: { phase: GlancePhase; selected: boolean; onOpen: () => void }) {
  const c = PHASE_COLORS[phase.kind]
  return (
    <button type="button" onClick={onOpen} aria-expanded={selected}
      className={cn('group flex flex-col items-stretch overflow-hidden rounded-md border bg-card/60 text-left transition-colors hover:border-primary/40',
        selected ? 'border-primary/60 ring-1 ring-primary/30' : 'border-border/50')}>
      <div className="h-1" style={{ backgroundColor: c?.hex }} />
      <div className="flex flex-1 flex-col gap-2 p-2.5">
        <div className="flex items-baseline justify-between gap-2">
          <p className={cn('truncate text-xs font-semibold', c?.text)}>{phase.name}</p>
          <span className="shrink-0 font-mono text-[10px] text-muted-foreground">
            {phase.weeks}wk{phase.repeatable ? ' ↻' : ''}
          </span>
        </div>
        <WeekGlyph phase={phase} />
        <IntensityBar split={phase.intensitySplit} />
        <div className="mt-auto flex items-center gap-2.5 text-[10px] text-muted-foreground">
          {phase.daysPerWeek != null && (
            <span className="inline-flex items-center gap-0.5" title="Training days a week">
              <CalendarDays className="size-3" />{phase.daysPerWeek}
            </span>
          )}
          {phase.minutes != null && (
            <span className="inline-flex items-center gap-0.5" title="Minutes a session">
              <Timer className="size-3" />{phase.minutes}
            </span>
          )}
          {phase.tests > 0 && (
            <span className="inline-flex items-center gap-0.5" title="Tests in this phase">
              <FlaskConical className="size-3" />{phase.tests}
            </span>
          )}
          <Info className="ml-auto size-3 opacity-0 transition-opacity group-hover:opacity-60" />
        </div>
      </div>
    </button>
  )
}

function IntensityLegend({ split }: { split: Record<string, number> }) {
  const rows = INTENSITY_BUCKETS.map((b) => ({ ...b, pct: split[b.key] ?? 0 })).filter((b) => b.pct > 0)
  return (
    <div className="flex flex-wrap gap-x-3">
      {rows.map((b) => (
        <span key={b.key} className="flex items-center gap-1 text-[10px] text-muted-foreground">
          <span className="size-1.5 rounded-full" style={{ backgroundColor: b.color }} />
          {b.label} {Math.round(b.pct * 100)}%
        </span>
      ))}
    </div>
  )
}

/** A phase in words, and its full week — opened in place under the cards. */
function PhaseDetail({ phase, track, onClose }: { phase: DescribedPhase; track: DescribedTrack; onClose: () => void }) {
  const c = PHASE_COLORS[phase.kind]
  return (
    <InlinePanel accent={c?.hex} onClose={onClose}
      title={<span className={cn('flex items-baseline gap-2', c?.text)}>
        {phase.name}
        <span className="font-mono text-xs font-normal text-muted-foreground">{phase.weeks} weeks{phase.repeatable ? ', repeated' : ''}</span>
      </span>}
      subtitle={`${track.name}${phase.focus ? ` — ${phase.focus}` : ''}`}>
      <div className="space-y-5">
        <PhaseWeek key={phase.id} week={phase.week} />
        {phase.description && <p className="max-w-3xl text-xs leading-relaxed text-muted-foreground">{phase.description}</p>}
        <div className="grid gap-4 sm:grid-cols-2">
          {phase.adaptations.length > 0 && (
            <div className="space-y-1">
              <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">What it builds</p>
              <ul className="space-y-0.5">
                {phase.adaptations.map((a) => (
                  <li key={a} className="flex gap-1.5 text-[11px] text-muted-foreground"><span style={{ color: c?.hex }}>·</span>{a}</li>
                ))}
              </ul>
            </div>
          )}
          <div className="space-y-1.5">
            <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">How hard</p>
            {phase.intensity && <p className="text-[11px] text-muted-foreground">{phase.intensity}</p>}
            <IntensityBar split={phase.intensitySplit} />
            <IntensityLegend split={phase.intensitySplit} />
            {phase.deload && <p className="text-[10px] text-muted-foreground">{phase.deload}</p>}
          </div>
        </div>
        {(phase.tests.length > 0 || phase.notYet.length > 0) && (
          <div className="space-y-1 text-[11px] text-muted-foreground">
            {phase.tests.map((t, i) => (
              <p key={i} className="flex gap-1.5">
                <FlaskConical className="mt-0.5 size-3 shrink-0" />
                <span><span className="font-medium text-foreground/90">{t.when}:</span> {t.sessions.join(', ')}
                  {t.standards.length > 0 && <> — {t.standards.join(', ')}</>}</span>
              </p>
            ))}
            {phase.notYet.length > 0 && <p>Not yet in this phase: {phase.notYet.join(', ')}.</p>}
          </div>
        )}
      </div>
    </InlinePanel>
  )
}

/** How the philosophy runs: every track as a row on one week scale, the
 *  chosen track's phases as cards; a phase's words and week open in place
 *  under the cards, the track's own words under its header. */
export function PhilosophyTracks({ doc }: { doc: PhilosophyDescription }) {
  const tracks = doc.glance.tracks
  const [trackId, setTrackId] = useState(doc.glance.primaryTrackId ?? tracks[0]?.id)
  const [phaseId, setPhaseId] = useState<string | null>(null)
  const [aboutTrack, setAboutTrack] = useState(false)
  const track = tracks.find((t) => t.id === trackId) ?? tracks[0]
  const detail = doc.tracks.find((t) => t.id === track?.id)
  if (!track || !detail) return null
  const scale = Math.max(...tracks.map((t) => t.weeks), 1)
  const openPhase = detail.phases.find((p) => p.id === phaseId)

  return (
    <div className="space-y-3">
      <div className="overflow-hidden rounded-lg border border-border/50 divide-y divide-border/40">
        <div className="hidden grid-cols-[minmax(9rem,1.1fr)_auto_3.5rem_minmax(8rem,2fr)_4.5rem_auto] items-center gap-x-3 px-3 py-1 text-[9px] uppercase tracking-wider text-muted-foreground/60 sm:grid">
          <span>Track</span><span>Level</span>
          <span className="inline-flex items-center justify-end gap-1"><CalendarRange className="size-3" />Length</span>
          <span>Phases</span>
          <span className="inline-flex items-center gap-1"><CalendarDays className="size-3" />Week</span>
          <span>Sessions / wk</span>
        </div>
        {tracks.map((t) => (
          <TrackRow key={t.id} track={t} scale={scale} selected={t.id === track.id}
            onSelect={() => { setTrackId(t.id); setPhaseId(null); setAboutTrack(false) }} />
        ))}
      </div>

      <div className="flex items-center justify-between gap-2">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground/70">
          {track.name} — {track.phases.length > 1 ? `${track.phases.length} phases` : 'one phase'}
        </p>
        {(detail.description || detail.notes) && (
          <button type="button" onClick={() => setAboutTrack((o) => !o)} aria-expanded={aboutTrack}
            className={cn('inline-flex items-center gap-1 text-[11px] hover:text-foreground',
              aboutTrack ? 'text-foreground' : 'text-muted-foreground')}>
            <Info className="size-3" /> About this track
          </button>
        )}
      </div>
      {aboutTrack && (
        <InlinePanel title={detail.name} subtitle={`${detail.weeks} weeks · ${detail.phases.length} phase${detail.phases.length === 1 ? '' : 's'}`}
          onClose={() => setAboutTrack(false)}>
          <div className="max-w-3xl space-y-3 text-xs leading-relaxed text-muted-foreground">
            {detail.description && <p>{detail.description}</p>}
            {detail.notes && <p className="rounded-md border border-border/40 bg-muted/30 px-3 py-2">{detail.notes}</p>}
          </div>
        </InlinePanel>
      )}
      <div className="grid gap-2 grid-cols-[repeat(auto-fill,minmax(10.5rem,1fr))]">
        {track.phases.map((p) => (
          <PhaseCard key={p.id} phase={p} selected={p.id === phaseId}
            onOpen={() => setPhaseId((cur) => (cur === p.id ? null : p.id))} />
        ))}
      </div>

      {openPhase && <PhaseDetail phase={openPhase} track={detail} onClose={() => setPhaseId(null)} />}
    </div>
  )
}
