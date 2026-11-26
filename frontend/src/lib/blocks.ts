import type { BlockMovement, BlockStage, Session, SessionBlock } from '@/api/types'

/**
 * Reading a session's blocks (src/session_blocks.py). The server groups the
 * slots and words them; these only walk the result.
 */

export const STAGE_ORDER: BlockStage[] = ['prep', 'main', 'finisher', 'cooldown']

/** A block whose movements are done one after another and then again. */
export function isLoop(block: SessionBlock): boolean {
  if (block.movements.length > 1) return true
  if (['rounds', 'amrap', 'emom'].includes(block.shape)) return true
  // One movement raced once ("500 m for time") is no round.
  return block.shape === 'for_time' && (block.repeat?.rounds ?? 1) > 1
}

export interface StageRun { stage: BlockStage; label: string; blocks: SessionBlock[] }

/** Consecutive blocks of one stage, in the order written. */
export function stageRuns(blocks: SessionBlock[]): StageRun[] {
  const runs: StageRun[] = []
  for (const b of blocks) {
    const last = runs[runs.length - 1]
    if (last && last.stage === b.stage) last.blocks.push(b)
    else runs.push({ stage: b.stage, label: b.stageLabel, blocks: [b] })
  }
  return runs
}

/** Each block's rows as indices into the session's exercises, or null when
 *  the blocks do not account for every exercise (an older server, an edit
 *  the blocks have not caught up with) — then the list is drawn flat. */
export function blockRows(session: Pick<Session, 'blocks' | 'exercises'>): Map<string, number> | null {
  const blocks = session.blocks ?? []
  if (blocks.length === 0) return null
  const byRole = new Map<string, number>()
  session.exercises.forEach((a, i) => {
    if (a.slot_role && !byRole.has(a.slot_role)) byRole.set(a.slot_role, i)
  })
  const roles = blocks.flatMap((b) => b.roles)
  if (roles.some((r) => !byRole.has(r))) return null
  if (new Set(roles.map((r) => byRole.get(r))).size !== session.exercises.length) return null
  return byRole
}

/** The width of a block's count column, in the count's own (monospace) characters: eight,
 *  or the longest count where that is longer ("10-15-20-15-10"), so none wraps. */
export function countColumn(movements: Pick<BlockMovement, 'count'>[]): string {
  const longest = Math.max(0, ...movements.map((m) => (m.count ?? '').length))
  return `${Math.max(8, longest)}ch`
}
