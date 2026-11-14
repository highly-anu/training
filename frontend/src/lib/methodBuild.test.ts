import { describe, it, expect } from 'vitest'
import recorded from '@/mocks/fixtures/methods.json'
import type { MethodBuild, MethodsAnswer } from '@/api/methods'
import {
  BUILD_STEPS, DESCRIPTION_LENGTH, buildHeadline, buildRequest, deleteRefusal, startRefusal, stepIndex, textProblem,
  unavailableReason,
} from './methodBuild'

const running = recorded.running.build as unknown as MethodBuild
const methods = recorded.methods as unknown as MethodsAnswer

describe('what a build is doing', () => {
  it('names each stage the server reports', () => {
    expect(buildHeadline(running)).toBe('Writing the method')
    expect(buildHeadline({ status: 'queued', progress: {} })).toBe('Waiting to start')
    expect(buildHeadline({ status: 'running', progress: { stage: 'researching' } })).toBe('Reading about the method')
    expect(buildHeadline({ status: 'running', progress: { stage: 'fixing' } })).toBe('Fixing what the checks found')
    expect(buildHeadline({ status: 'running', progress: {} })).toBe('Reading your description')
  })

  it('places it among the steps: research is reading, a fix is checking, done is past the last', () => {
    expect(stepIndex(running)).toBe(1)
    expect(stepIndex({ status: 'running', progress: { stage: 'researching' } })).toBe(0)
    expect(stepIndex({ status: 'running', progress: { stage: 'fixing' } })).toBe(2)
    expect(stepIndex(recorded.done.build as unknown as MethodBuild)).toBe(BUILD_STEPS.length)
  })
})

describe('whether a build can start', () => {
  it('says nothing when it can', () => {
    expect(unavailableReason(methods)).toBeNull()
    expect(unavailableReason(undefined)).toBeNull()
  })
  it('says why when it cannot', () => {
    expect(unavailableReason(recorded.unavailable as unknown as MethodsAnswer)).toBe('Methods cannot be built right now.')
    expect(unavailableReason({ ...methods, available: false, reason: 'not_enabled' })).toMatch(/not turned on/)
    expect(unavailableReason({ ...methods, limits: { ...methods.limits, remaining: 0 } })).toMatch(/Try again tomorrow/)
  })
})

describe('the describe form', () => {
  it('holds the text to the server\'s lengths', () => {
    expect(textProblem('too short', DESCRIPTION_LENGTH, 'a description')).toMatch(/at least 20/)
    expect(textProblem('x'.repeat(8001), DESCRIPTION_LENGTH, 'a description')).toMatch(/at most 8,000/)
    expect(textProblem('Three strength days and two runs.', DESCRIPTION_LENGTH, 'a description')).toBeNull()
  })

  const form = { description: '  Three strength days and two runs.  ', pastedText: '  ', webSearch: true,
    answers: { days: 4, minutes: 60, level: 'novice', equipment: ['barbell'] } }

  it('sends a new method as its description and the athlete\'s answers', () => {
    expect(buildRequest(form)).toEqual({ description: 'Three strength days and two runs.', webSearch: true,
      answers: { days: 4, minutes: 60, level: 'novice', equipment: ['barbell'] } })
    expect(buildRequest({ ...form, pastedText: ' A plan. ' })).toMatchObject({ pastedText: 'A plan.' })
  })

  it('sends a revision as the method and the note', () => {
    expect(buildRequest(form, 'u1_mine')).toEqual({ revise: { packageId: 'u1_mine', note: 'Three strength days and two runs.' },
      answers: form.answers, webSearch: true })
  })
})

describe('refusals', () => {
  it('hands back the build already running', () => {
    const refusal = startRefusal({ status: 409, body: { error: 'build_running', detail: 'A method is already being built.', build: running } })
    expect(refusal.running?.id).toBe('build-1')
  })
  it('says the server\'s sentence, or a plain one', () => {
    expect(startRefusal({ status: 429, body: { error: 'daily_limit', detail: "You have used today's builds. Try again tomorrow." } }).message)
      .toBe("You have used today's builds. Try again tomorrow.")
    expect(startRefusal(new Error('Network Error')).message).toBe('The build could not be started. Try again.')
  })
  it('says why a method in use is not deleted', () => {
    expect(deleteRefusal({ status: 409, body: { error: 'in_use' } })).toMatch(/Start another program first/)
    expect(deleteRefusal(new Error('boom'))).toMatch(/could not be deleted/)
  })
})
