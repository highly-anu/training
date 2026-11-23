// @vitest-environment jsdom
/**
 * A workout drawn as blocks: a round's movements inside their round, the
 * start and the finisher labelled, notes only on demand. The blocks are the
 * server's (mocks/fixtures/blocks.json, written by test_session_blocks.py).
 */
import { describe, it, expect, afterEach } from 'vitest'
import { render, screen, cleanup, fireEvent, within } from '@testing-library/react'
import fixture from '@/mocks/fixtures/blocks.json'
import type { SessionBlock } from '@/api/types'
import { blockRows, isLoop, stageRuns } from '@/lib/blocks'
import { BlockStrip, WorkoutBlocks } from './WorkoutBlocks'

afterEach(cleanup)

const blocks = fixture as unknown as Record<string, SessionBlock[]>
const block = (root: HTMLElement, id: string) => root.querySelector(`[data-block="${id}"]`) as HTMLElement

describe('WorkoutBlocks', () => {
  it('labels the start, the main work and the finisher', () => {
    render(<WorkoutBlocks blocks={blocks.complex} />)
    expect(screen.getAllByRole('heading').map((h) => h.textContent)).toEqual(['Start', 'Main work', 'Finisher'])
  })

  it('labels nothing when the session is one stage', () => {
    render(<WorkoutBlocks blocks={blocks.fran} />)
    expect(screen.queryByRole('heading')).toBeNull()
  })

  it("draws a round's movements inside the round, each with its own count", () => {
    const { container } = render(<WorkoutBlocks blocks={blocks.complex} />)
    const round = within(block(container, 'complex'))
    expect(round.getByText('6 rounds')).toBeTruthy()
    for (const name of ['Kettlebell bent-over row', 'Kettlebell clean', 'Kettlebell one-arm swing', 'Push-up']) {
      expect(round.getByText(name)).toBeTruthy()
    }
    expect(round.getAllByText('5')).toHaveLength(4)
    // The rest is said once, at the foot of the round, with the way back up.
    expect(round.getByText('2 min 30 s rest between rounds · 6 rounds in all')).toBeTruthy()
    // The finisher is its own block, outside the round.
    expect(within(block(container, 'swing_finisher')).getByText('3 × 20')).toBeTruthy()
    expect(round.queryByText('3 × 20')).toBeNull()
  })

  it('never tells a movement of a round to do as many as possible', () => {
    const { container } = render(<>{Object.values(blocks).map((b, i) => <WorkoutBlocks key={i} blocks={b} />)}</>)
    expect(container.textContent).not.toMatch(/as many as possible/i)
  })

  it('keeps notes behind a tap', () => {
    const { container } = render(<WorkoutBlocks blocks={blocks.complex} />)
    const note = 'One hand, without putting the bell down. Change hands every round.'
    expect(screen.queryByText(note)).toBeNull()
    fireEvent.click(within(block(container, 'complex')).getByRole('button', { name: /show notes/i }))
    expect(screen.getByText(note)).toBeTruthy()
  })

  it('draws a ladder and a pyramid as steps', () => {
    render(<><WorkoutBlocks blocks={blocks.ladders} /><WorkoutBlocks blocks={blocks.pyramid} /></>)
    expect(screen.getByRole('img', { name: '1-2-3-4-5' })).toBeTruthy()
    expect(screen.getByRole('img', { name: '3-4-5-4-3' })).toBeTruthy()
    expect(screen.getByText('10-15-20-15-10')).toBeTruthy()
  })

  it('brackets alternating sets', () => {
    render(<WorkoutBlocks blocks={blocks.ladders} />)
    expect(screen.getByText('Alternate sets')).toBeTruthy()
  })

  it('links a movement to its exercise', () => {
    const seen: string[] = []
    const { container } = render(<WorkoutBlocks blocks={blocks.complex} onExercise={(id) => seen.push(id)} />)
    fireEvent.click(within(block(container, 'complex')).getByRole('button', { name: /Push-up/ }))
    fireEvent.click(screen.getByRole('button', { name: 'Knee push-up' }))
    expect(seen).toEqual(['knee_push-up'])
  })

  it("hands a caller's rows the movements, a lone one without a header", () => {
    const { container } = render(
      <WorkoutBlocks blocks={blocks.complex} renderMovement={(m) => <div data-row={m.role}>{m.role}</div>} />)
    expect(Array.from(container.querySelectorAll('[data-row]')).map((n) => n.getAttribute('data-row')))
      .toEqual(blocks.complex.flatMap((b) => b.roles))
    expect(within(block(container, 'complex')).getByText('6 rounds')).toBeTruthy()
    expect(within(block(container, 'swing_finisher')).queryByText('3 × 20')).toBeNull()
  })
})

describe('BlockStrip', () => {
  it('is a segment a block, named by stage', () => {
    render(<BlockStrip blocks={blocks.complex} />)
    const strip = screen.getByRole('img', { name: 'Blocks: Start 1, Main work 1, Finisher 1' })
    expect(strip.children).toHaveLength(3)
  })
})

describe('lib/blocks', () => {
  it('knows a loop from a lone movement', () => {
    expect(blocks.complex.map(isLoop)).toEqual([false, true, false])
    expect(isLoop(blocks.emom[0])).toBe(true)
  })

  it('runs the stages in the order written', () => {
    expect(stageRuns(blocks.complex).map((r) => [r.stage, r.blocks.length]))
      .toEqual([['prep', 1], ['main', 1], ['finisher', 1]])
  })

  it('maps rows only when the blocks account for every exercise', () => {
    const exercises = blocks.fran.flatMap((b) => b.roles).map((slot_role) => ({ slot_role })) as never[]
    expect(blockRows({ blocks: blocks.fran, exercises })?.get('fran_2')).toBe(1)
    expect(blockRows({ blocks: blocks.fran, exercises: [...exercises, { slot_role: 'extra' } as never] })).toBeNull()
    expect(blockRows({ blocks: undefined, exercises })).toBeNull()
  })
})
