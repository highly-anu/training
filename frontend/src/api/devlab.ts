import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { ModelMap, PortabilityReport } from '@/api/types'
import { isOpen, type BuildProblem, type MethodBuild } from './methods'

/**
 * What each package brings in its own folder and what it still needs outside
 * it, with the gaps no package can close yet (src/portability.py). Local dev
 * or AUTHORING_ENABLED only; package files change only between deploys.
 */
export function usePortability() {
  return useQuery({
    queryKey: queryKeys.dev.portability,
    queryFn: () => apiClient.get('/dev/portability') as unknown as Promise<PortabilityReport>,
    staleTime: Infinity,
    retry: false,
  })
}

/**
 * How the model's parts act on each other, each interaction anchored in the
 * code, and which engine each track runs on (src/model_map.py,
 * tools/model_map.json). Local dev or AUTHORING_ENABLED only.
 */
export function useModelMap() {
  return useQuery({
    queryKey: queryKeys.dev.modelMap,
    queryFn: () => apiClient.get('/dev/model-map') as unknown as Promise<ModelMap>,
    staleTime: Infinity,
    retry: false,
  })
}

// ── Dev Lab ▸ Builds (src/build_report.py) ───────────────────────────────────

export interface BuildUsage {
  turns: number
  checks: number
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
  webSearches: number
  webFetches: number
  seconds: number
  model: string | null
}

/** One build as the list shows it: how it ended and what it spent. */
export interface BuildSummary extends MethodBuild {
  attempts: number
  usage: BuildUsage
  /** The tokens at the builder model's list price; web searches are billed apart. */
  costUsd: number
  webSearch: boolean
  pastedChars: number
}

export interface BuildTotals {
  builds: number
  byStatus: Record<string, number>
  /** Done of the builds that ran to an end (done or failed); null with none. */
  doneShare: number | null
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
  seconds: number
  costUsd: number
}

export interface TurnTokens { input: number; output: number; cacheRead: number; cacheWrite: number }

export interface BuildCall {
  tool: string
  path: string | null
  kind: string | null
  bytes: number | null
  /** A web search's query or a fetch's address. */
  query: string | null
  error: boolean
  result: string | null
  /** Index into the build's `checks` when the call answered with the gate's verdict. */
  check: number | null
}

export interface BuildTurn {
  n: number
  said: string | null
  thought: boolean
  calls: BuildCall[]
  /** What the loop itself told the model after the turn. */
  note: string | null
  tokens: TurnTokens | null
}

export interface BuildCheck {
  turn: number
  tool: string
  ok: boolean
  problems: BuildProblem[]
  moreProblems: number
  warnings: string[]
  skipped: string[]
  checksLeft: number | null
  /** The program generated with the athlete's own answers, as the model was shown it. */
  athlete: {
    as: Record<string, unknown> | null
    feasible: boolean | null
    error: string | null
    errors: Array<{ code: string; message: string }>
    weeks: { shown: number; of: number } | null
    checkThese: string[]
    program: string | null
    moreTracks: number
  } | null
}

export interface BuildDetail extends BuildSummary {
  request: {
    description: string
    answers: { days?: number; minutes?: number; level?: string; equipment?: string[] }
    pastedText: string
    webSearch: boolean
    revise: { packageId: string; note: string } | null
  }
  turns: BuildTurn[]
  /** Replies cut off at the output limit: counted and paid for, nothing of them kept. */
  droppedTurns: Array<{ stop: string | null; tokens: TurnTokens | null }>
  checks: BuildCheck[]
  problemCounts: Array<{ stage: string | null; code: string | null; count: number }>
  files: Array<{ path: string; bytes: number; content: string }>
  limits: { turns: number; checks: number; outputTokens: number; seconds: number }
  effort: string
  priceModel: string
}

export interface BuildsList { builds: BuildSummary[]; totals: BuildTotals }

/** The signed-in athlete's last builds with what each spent; asked again while one runs. */
export function useDevBuilds() {
  return useQuery({
    queryKey: queryKeys.dev.builds,
    queryFn: () => apiClient.get('/dev/builds') as unknown as Promise<BuildsList>,
    retry: false,
    refetchInterval: (query) => (query.state.data?.builds.some(isOpen) ? 5000 : false),
  })
}

/** One build in full: turns, checks, problems, files. */
export function useDevBuild(id: string | null) {
  return useQuery({
    queryKey: queryKeys.dev.build(id ?? ''),
    enabled: !!id,
    queryFn: async () =>
      ((await apiClient.get(`/dev/builds/${encodeURIComponent(id!)}`)) as unknown as { build: BuildDetail }).build,
    retry: false,
    refetchInterval: (query) => (query.state.data && isOpen(query.state.data) ? 5000 : false),
  })
}
