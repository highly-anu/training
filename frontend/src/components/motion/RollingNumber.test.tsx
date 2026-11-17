// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render } from '@testing-library/react'
import { MotionConfig } from 'framer-motion'
import { RollingNumber } from './RollingNumber'

afterEach(cleanup)

describe('<RollingNumber>', () => {
  it('shows its value at once on first paint', () => {
    const { container } = render(<RollingNumber value="3 of 5" order={3} />)
    expect(container.textContent).toBe('3 of 5')
  })

  it('shows the new value after a change, with motion reduced or not', () => {
    for (const reducedMotion of ['never', 'always'] as const) {
      const { container, rerender } = render(
        <MotionConfig reducedMotion={reducedMotion}><RollingNumber value={3} /></MotionConfig>,
      )
      rerender(<MotionConfig reducedMotion={reducedMotion}><RollingNumber value={4} /></MotionConfig>)
      expect(container.textContent).toContain('4')
      cleanup()
    }
  })
})
