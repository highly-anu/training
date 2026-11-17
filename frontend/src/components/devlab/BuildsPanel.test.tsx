// @vitest-environment jsdom
/**
 * Dev Lab ▸ Builds renders the server's own answers
 * (src/mocks/fixtures/builds.json, recorded by test_package_builder.py --write,
 * which fails when /api/dev/builds no longer has the recording's shape): a
 * build that fixed what its first check found, and one that ran out of turns.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, within } from '@testing-library/react'
import recorded from '@/mocks/fixtures/builds.json'
import type { BuildDetail, BuildsList } from '@/api/devlab'
import { BuildReport, BuildsTable } from './BuildsPanel'

const list = recorded.list as unknown as BuildsList
const done = recorded.done.build as unknown as BuildDetail
const failed = recorded.failed.build as unknown as BuildDetail

afterEach(cleanup)

describe('Builds', () => {
  it('lists each build with what it spent, and the totals', () => {
    const onSelect = vi.fn()
    render(<BuildsTable list={list} selected={done.id} onSelect={onSelect} />)
    expect(screen.getByText(`$${list.totals.costUsd.toFixed(2)}`)).toBeTruthy()
    expect(screen.getByText('50%')).toBeTruthy()
    const rows = screen.getAllByRole('row').slice(1)
    expect(rows).toHaveLength(list.builds.length)
    const row = rows[list.builds.findIndex((b) => b.id === done.id)]
    expect(row.getAttribute('aria-selected')).toBe('true')
    expect(within(row).getByText(done.result!.name)).toBeTruthy()
    expect(within(row).getByText(done.usage.outputTokens.toLocaleString('en-US'))).toBeTruthy()
    const other = rows[list.builds.findIndex((b) => b.id === failed.id)]
    expect(within(other).getByText('budget')).toBeTruthy()
    expect(within(other).getByText(/web search/)).toBeTruthy()
    fireEvent.click(within(other).getByRole('button'))
    expect(onSelect).toHaveBeenCalledWith(failed.id)
  })

  it('shows a build\'s checks with their problems, then the pass', () => {
    render(<BuildReport build={done} />)
    expect(screen.getByText('Check 1')).toBeTruthy()
    expect(screen.getAllByText(`${done.checks[0].problems.length} to fix`).length).toBeGreaterThan(0)
    for (const p of done.checks[0].problems) expect(screen.getAllByText(p.message!).length).toBeGreaterThan(0)
    expect(screen.getByText(new RegExp(`unfilled_slot ×${done.problemCounts[0].count}`))).toBeTruthy()
    expect(screen.getAllByText(/^The program the model was shown — /).length).toBe(done.checks.filter((c) => c.athlete?.program).length)
    expect(screen.getByText(done.result!.summary)).toBeTruthy()
  })

  it('shows every turn with its calls and tokens, and the files as installed', () => {
    render(<BuildReport build={done} />)
    for (const t of done.turns) expect(screen.getByText(`Turn ${t.n}`)).toBeTruthy()
    expect(screen.getByText(done.turns[0].said!)).toBeTruthy()
    expect(screen.getByText(/^4,000 out · 9,000 in · 0 cached · 30,000 written$/)).toBeTruthy()
    expect(screen.getByText(`${done.usage.turns} of ${done.limits.turns}`)).toBeTruthy()
    expect(screen.getByText('of 25 min 0 s')).toBeTruthy()
    expect(screen.getByText('Files — as installed')).toBeTruthy()
    for (const f of done.files) expect(screen.getAllByText(f.path).length).toBeGreaterThan(0)
  })

  it('says why a build failed and what was thrown away', () => {
    render(<BuildReport build={failed} />)
    expect(screen.getByText(new RegExp(failed.error!.message.slice(0, 30)))).toBeTruthy()
    expect(screen.getByText(/1 reply was cut off at the output limit and thrown away \(32,000 output tokens\)/)).toBeTruthy()
    expect(screen.getByText('Files — the draft as it was left')).toBeTruthy()
    expect(screen.getByText(/^Pasted text — 21 characters$/)).toBeTruthy()
  })
})
