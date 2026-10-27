import { useState } from 'react'
import type { DescribedPhase, DescribedTrack } from '@/api/types'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { INTENSITY_BUCKETS } from '@/lib/hrZones'
import { cn } from '@/lib/utils'
import { ModalityMix } from './ModalityMix'
import { PhaseWeek } from './PhaseWeek'

const phaseHex = (p: DescribedPhase) => PHASE_COLORS[p.kind]?.hex ?? '#94a3b8'

const LEVEL_WORDS: Record<string, string> = {
  novice: 'novices', intermediate: 'intermediates', advanced: 'advanced athletes', elite: 'elite athletes',
}

/** The track's phases as one bar, each as wide as its weeks and in its kind's
 *  colour (frontend-design §8.2); a segment picks the phase shown below. */
function Timeline({ phases, selected, onSelect }: {
  phases: DescribedPhase[]; selected: number; onSelect: (i: number) => void
}) {
  const total = phases.reduce((n, p) => n + (p.weeks || 0), 0) || 1
  return (
    <div className="flex w-full gap-0.5" role="tablist" aria-label="Phases">
      {phases.map((p, i) => {
        const on = i === selected
        return (
          <button key={p.id} type="button" role="tab" aria-selected={on} onClick={() => onSelect(i)}
            className="group min-w-0 text-left" style={{ width: `${Math.max((p.weeks / total) * 100, 8)}%` }}>
            <div className={cn('h-2.5 rounded-sm transition-opacity', on ? 'opacity-100' : 'opacity-40 group-hover:opacity-70')}
              style={{ backgroundColor: phaseHex(p) }} />
            <p className={cn('mt-1 truncate text-[10px]', on ? 'font-semibold text-foreground' : 'text-muted-foreground')}>
              {p.name}
            </p>
            <p className="truncate font-mono text-[9px] text-muted-foreground/70">{p.weeks} wk{p.repeatable ? ' ↻' : ''}</p>
          </button>
        )
      })}
    </div>
  )
}

function IntensitySplit({ split }: { split: Record<string, number> }) {
  const rows = INTENSITY_BUCKETS.map((b) => ({ ...b, pct: split[b.key] ?? 0 })).filter((b) => b.pct > 0)
  if (!rows.length) return null
  return (
    <div className="space-y-1">
      <div className="flex h-1.5 w-full overflow-hidden rounded-full bg-muted gap-px">
        {rows.map((b) => <div key={b.key} style={{ width: `${b.pct * 100}%`, backgroundColor: b.color }} />)}
      </div>
      <div className="flex flex-wrap gap-x-3">
        {rows.map((b) => (
          <span key={b.key} className="flex items-center gap-1 text-[9px] text-muted-foreground">
            <span className="size-1.5 rounded-full" style={{ backgroundColor: b.color }} />
            {b.label} {Math.round(b.pct * 100)}%
          </span>
        ))}
      </div>
    </div>
  )
}

function PhaseDetail({ phase }: { phase: DescribedPhase }) {
  const c = PHASE_COLORS[phase.kind]
  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <div className="flex items-baseline gap-2 flex-wrap">
          <h4 className={cn('text-sm font-semibold', c?.text)}>{phase.name}</h4>
          <span className="text-[10px] font-mono text-muted-foreground">
            {phase.weeks} weeks{phase.repeatable ? ', repeated' : ''}
          </span>
        </div>
        {phase.focus && <p className="text-xs text-foreground/90">{phase.focus}</p>}
        {phase.description && <p className="text-[11px] text-muted-foreground leading-relaxed">{phase.description}</p>}
      </div>

      <PhaseWeek key={phase.id} week={phase.week} />

      <div className="grid gap-3 sm:grid-cols-2">
        {phase.adaptations.length > 0 && (
          <div className="space-y-1">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">What it builds</p>
            <ul className="space-y-0.5">
              {phase.adaptations.map((a) => (
                <li key={a} className="flex gap-1.5 text-[11px] text-muted-foreground">
                  <span style={{ color: c?.hex }}>·</span>{a}
                </li>
              ))}
            </ul>
          </div>
        )}
        <div className="space-y-1.5">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">How hard</p>
          {phase.intensity && <p className="text-[11px] text-muted-foreground">{phase.intensity}</p>}
          <IntensitySplit split={phase.intensitySplit} />
          {phase.deload && <p className="text-[10px] text-muted-foreground">{phase.deload}</p>}
        </div>
      </div>

      {(phase.tests.length > 0 || phase.notYet.length > 0) && (
        <div className="space-y-1 text-[11px] text-muted-foreground">
          {phase.tests.map((t, i) => (
            <p key={i}>
              <span className="font-medium text-foreground/90">Test, {t.when}:</span> {t.sessions.join(', ')}
              {t.standards.length > 0 && <> — measures {t.standards.join(', ')}</>}
            </p>
          ))}
          {phase.notYet.length > 0 && <p>Not yet in this phase: {phase.notYet.join(', ')}.</p>}
        </div>
      )}
    </div>
  )
}

/** How the philosophy runs: its tracks, each track's phases over time, and
 *  each phase's week as the package writes it. */
export function PhilosophyTracks({ tracks }: { tracks: DescribedTrack[] }) {
  const [trackIndex, setTrackIndex] = useState(() => Math.max(0, tracks.findIndex((t) => t.primary)))
  const [phaseIndex, setPhaseIndex] = useState(0)
  const track = tracks[trackIndex] ?? tracks[0]
  if (!track) return null
  const phase = track.phases[Math.min(phaseIndex, track.phases.length - 1)]

  return (
    <div className="space-y-4">
      {tracks.length > 1 && (
        <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="Tracks">
          {tracks.map((t, i) => (
            <button key={t.id} type="button" role="tab" aria-selected={i === trackIndex}
              onClick={() => { setTrackIndex(i); setPhaseIndex(0) }}
              className={cn('rounded-md border px-2.5 py-1 text-left transition-colors',
                i === trackIndex ? 'border-primary/40 bg-primary/10' : 'border-border/50 hover:bg-muted')}>
              <p className="text-xs font-medium">{t.name}</p>
              <p className="text-[9px] text-muted-foreground">
                {t.weeks} weeks{t.primary ? ' · main' : ''}
                {t.forLevels.length > 0 && ` · for ${t.forLevels.map((l) => LEVEL_WORDS[l] ?? l).join(', ')}`}
              </p>
            </button>
          ))}
        </div>
      )}

      <div className="space-y-2">
        {track.description && <p className="text-[11px] text-muted-foreground leading-relaxed">{track.description}</p>}
        {/* One track: the header's strip is this one. */}
        {tracks.length > 1 && <ModalityMix mix={track.mix} />}
        <p className="text-[10px] text-muted-foreground/80">
          {track.levels.length > 0 && <>For {track.levels.map((l) => LEVEL_WORDS[l] ?? l).join(', ')}. </>}
          {track.kettlebellPair && 'Needs a pair of kettlebells. '}
          {track.builtBy === 'template' && 'Each day is a workout the source names, in its order.'}
          {track.builtBy === 'contract' && 'Each session progresses on its own, by what you log.'}
        </p>
        {track.notes && (
          <p className="rounded-md border border-border/40 bg-muted/30 px-3 py-2 text-[11px] text-muted-foreground leading-relaxed">
            {track.notes}
          </p>
        )}
      </div>

      {track.phases.length > 1 && <Timeline phases={track.phases} selected={phaseIndex} onSelect={setPhaseIndex} />}
      {phase && <PhaseDetail phase={phase} />}
    </div>
  )
}
