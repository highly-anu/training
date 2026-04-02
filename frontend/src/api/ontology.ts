import { useMemo } from 'react'
import { usePhilosophies } from './philosophies'
import { useFrameworks } from './frameworks'
import { useModalities } from './modalities'
import { useArchetypes } from './archetypes'
import { useExercises } from './exercises'
import type { OntologyData } from './types'

export function useOntology() {
  const { data: philosophies, isLoading: lp } = usePhilosophies()
  const { data: frameworks, isLoading: lf } = useFrameworks()
  const { data: modalities, isLoading: lm } = useModalities()
  const { data: archetypes, isLoading: la } = useArchetypes()
  const { data: exercises, isLoading: le } = useExercises()

  const isLoading = lp || lf || lm || la || le

  const data = useMemo<OntologyData | undefined>(() => {
    if (!philosophies || !frameworks || !modalities || !archetypes || !exercises) return undefined
    return { philosophies, frameworks, modalities, archetypes, exercises }
  }, [philosophies, frameworks, modalities, archetypes, exercises])

  return { data, isLoading }
}
