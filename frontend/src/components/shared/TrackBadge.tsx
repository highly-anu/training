import { usePhilosophies } from '@/api/philosophies'
import type { Session } from '@/api/types'

/**
 * Which track of a composed program a session is (src/composition.py): its
 * philosophy, and the track when the philosophy offers several. Nothing for
 * a session of a one-track program.
 */
export function TrackBadge({ session, size = 'sm' }: { session: Pick<Session, 'lane_key'>; size?: 'sm' | 'md' }) {
  const { data: philosophies } = usePhilosophies()
  if (!session.lane_key) return null
  const [philosophyId, trackId] = session.lane_key.split('/')
  const phil = philosophies?.find((p) => p.id === philosophyId)
  const name = phil?.name.split(' /')[0].split(' —')[0] ?? philosophyId.replace(/_/g, ' ')
  const track = (phil?.tracks?.length ?? 0) > 1 ? phil?.tracks.find((t) => t.id === trackId)?.name : undefined
  return (
    <span title={track ? `${name} — ${track}` : name}
          className={size === 'sm'
            ? 'rounded-full border border-border px-1.5 py-0.5 text-[9px] font-medium text-muted-foreground'
            : 'rounded-full border border-border px-2 py-0.5 text-[10px] font-medium text-muted-foreground'}>
      {track ? `${name} · ${track}` : name}
    </span>
  )
}
