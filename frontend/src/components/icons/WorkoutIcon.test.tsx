// @vitest-environment jsdom
/**
 * A session's workout icon is drawn in its modality's colour, and a session
 * without one (or with an id this build does not know) draws nothing.
 */
import { describe, it, expect, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { MODALITY_COLORS } from '@/lib/modalityColors'

afterEach(cleanup)

describe('WorkoutIcon', () => {
  it('draws the kettlebell in the modality colour', () => {
    render(<WorkoutIcon icon="kettlebell" modality="power" />)
    const svg = screen.getByRole('img', { name: 'Kettlebell' })
    const hex = MODALITY_COLORS.power.hex
    const rgb = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(', ')
    expect((svg as unknown as SVGElement).style.color).toBe(`rgb(${rgb})`)
  })

  it('draws nothing without an icon, or for an unknown one', () => {
    const { container } = render(<><WorkoutIcon modality="power" /><WorkoutIcon icon="not.an.icon" modality="power" /></>)
    expect(container.querySelector('svg')).toBeNull()
  })
})
