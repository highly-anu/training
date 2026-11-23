// @vitest-environment jsdom
/**
 * The one mark for what kind of training something is: the session's own
 * workout icon when it has one, else its modality's, a flask for a test —
 * always named, and on a neutral tile where it leads a card.
 */
import { describe, it, expect, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { modalityHex } from '@/lib/modalityColors'
import { ModalityMark } from './ModalityMark'

afterEach(cleanup)

// jsdom reads a hex colour back as rgb().
const rgb = (hex: string) => {
  const n = parseInt(hex.slice(1), 16)
  return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`
}

describe('ModalityMark', () => {
  it("draws the modality's icon in its colour, named", () => {
    render(<ModalityMark modality="aerobic_base" />)
    const icon = screen.getByLabelText('Aerobic Base')
    expect((icon as unknown as SVGElement).style.color).toBe(rgb(modalityHex('aerobic_base')))
  })

  it("draws the session's workout icon when it has one, tinted the same way", () => {
    render(<ModalityMark modality="power" icon="kettlebell" />)
    const icon = screen.getByRole('img', { name: 'Kettlebell' })
    expect((icon as unknown as SVGElement).style.color).toBe(rgb(modalityHex('power')))
  })

  it("falls back to the modality's icon for an icon the web has no glyph for", () => {
    render(<ModalityMark modality="power" icon="barbell_not_drawn_yet" />)
    expect(screen.getByLabelText('Power')).toBeTruthy()
  })

  it('marks a test with a flask and no colour', () => {
    render(<ModalityMark modality="aerobic_base" test />)
    const icon = screen.getByLabelText('Test')
    expect((icon as unknown as SVGElement).style.color).toBe('')
  })

  it('sits on a neutral tile when asked, the colour on the icon alone', () => {
    const { container } = render(<ModalityMark modality="power" tile size="lg" />)
    const tile = container.firstElementChild as HTMLElement
    expect(tile.className).toContain('bg-muted')
    expect(tile.style.backgroundColor).toBe('')
    expect(tile.querySelector('svg')).toBeTruthy()
  })
})
