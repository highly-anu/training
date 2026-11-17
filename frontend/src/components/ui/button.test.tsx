// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { Save } from 'lucide-react'
import { Button } from './button'

afterEach(cleanup)

describe('Button loading', () => {
  it('keeps its label, shows the spinner and cannot be pressed again', () => {
    const onClick = vi.fn()
    render(<Button loading onClick={onClick}><Save /> Save changes</Button>)
    const button = screen.getByRole('button', { name: /save changes/i })
    expect(button).toBeDisabled()
    expect(button).toHaveAttribute('aria-busy', 'true')
    expect(button.querySelector('[data-slot="spinner"]')).not.toBeNull()
    button.click()
    expect(onClick).not.toHaveBeenCalled()
  })

  it('is an ordinary button otherwise', () => {
    render(<Button>Save changes</Button>)
    const button = screen.getByRole('button', { name: 'Save changes' })
    expect(button).not.toBeDisabled()
    expect(button).not.toHaveAttribute('aria-busy')
    expect(button.querySelector('[data-slot="spinner"]')).toBeNull()
  })
})
