import type { BuildAnswers, BuildRequest, MethodBuild, MethodsAnswer } from '@/api/methods'

/**
 * The words of the method builder (docs/roadmap.md 21.4): what a build is
 * doing, why one cannot start, and the request the describe form makes. Pure,
 * so the screens only lay them out.
 */

export const DESCRIPTION_LENGTH = [20, 8000] as const
export const NOTE_LENGTH = [5, 2000] as const
export const PASTED_MAX = 60000
export const MINUTES = [20, 30, 45, 60, 75, 90, 120] as const

/** The steps a build goes through, in order, as the athlete reads them. */
export const BUILD_STEPS: { stage: string; label: string }[] = [
  { stage: 'reading', label: 'Reading your description' },
  { stage: 'writing', label: 'Writing the method' },
  { stage: 'checking', label: 'Checking that it generates a program' },
  { stage: 'installing', label: 'Adding it to your methods' },
]

/** Where a build stands among BUILD_STEPS (research counts as reading, a fix as checking). */
export function stepIndex(build: Pick<MethodBuild, 'status' | 'progress'>): number {
  if (build.status === 'done') return BUILD_STEPS.length
  const stage = build.progress.stage
  const at = stage === 'researching' ? 'reading' : stage === 'fixing' ? 'checking' : stage
  const i = BUILD_STEPS.findIndex((s) => s.stage === at)
  return i < 0 ? 0 : i
}

/** One line for what the build is doing now. */
export function buildHeadline(build: Pick<MethodBuild, 'status' | 'progress'>): string {
  if (build.status === 'queued') return 'Waiting to start'
  switch (build.progress.stage) {
    case 'researching': return 'Reading about the method'
    case 'writing': return 'Writing the method'
    case 'checking': return 'Checking that it generates a program'
    case 'fixing': return 'Fixing what the checks found'
    case 'installing': return 'Adding it to your methods'
    default: return 'Reading your description'
  }
}

/** Why the describe form's text cannot be sent, or null. */
export function textProblem(text: string, [min, max]: readonly [number, number], what: string): string | null {
  const length = text.trim().length
  if (length < min) return `Say a little more: ${what} needs at least ${min} characters.`
  if (length > max) return `Shorten it: ${what} takes at most ${max.toLocaleString('en')} characters.`
  return null
}

/** Why a build cannot be started at all right now, or null. */
export function unavailableReason(methods: MethodsAnswer | undefined): string | null {
  if (!methods) return null
  if (!methods.available) {
    return methods.reason === 'no_model_key'
      ? 'Methods cannot be built right now.'
      : 'Building your own method is not turned on for this account.'
  }
  if (methods.limits.remaining <= 0) return "You have used today's builds. Try again tomorrow."
  return null
}

export interface DescribeForm {
  description: string
  pastedText: string
  webSearch: boolean
  answers: BuildAnswers
}

/** The request for a new method, or for a revision of `revises`. */
export function buildRequest(form: DescribeForm, revises?: string | null): BuildRequest {
  if (revises) {
    return { revise: { packageId: revises, note: form.description.trim() }, answers: form.answers, webSearch: form.webSearch }
  }
  const pasted = form.pastedText.trim()
  return {
    description: form.description.trim(),
    answers: form.answers,
    ...(pasted ? { pastedText: pasted } : {}),
    webSearch: form.webSearch,
  }
}

interface Refusal { status?: number; body?: { error?: string; detail?: string; build?: MethodBuild }; message?: string }

/**
 * A refused start, in the athlete's words — and the build already running,
 * when that is why (the screen goes to it instead of saying so).
 */
export function startRefusal(error: unknown): { message: string; running?: MethodBuild } {
  const e = (error ?? {}) as Refusal
  const code = e.body?.error
  if (code === 'build_running' && e.body?.build) return { message: 'A method is already being built.', running: e.body.build }
  if (code === 'not_enabled') return { message: 'Building your own method is not turned on for this account.' }
  if (code === 'not_found') return { message: 'That method is no longer among yours.' }
  if (e.body?.detail) return { message: e.body.detail }
  return { message: 'The build could not be started. Try again.' }
}

/** Why a method could not be deleted, in the athlete's words. */
export function deleteRefusal(error: unknown): string {
  const e = (error ?? {}) as Refusal
  if (e.body?.error === 'in_use') return 'Your program is built from this method. Start another program first.'
  return 'The method could not be deleted. Try again.'
}
