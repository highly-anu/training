import { useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { BookOpen, Dumbbell, Layers, Network, PersonStanding, Trophy, Wrench, Zap } from 'lucide-react'
import type { ExploreTopic } from '@/lib/exploreLinks'

export interface TopicTab {
  id: ExploreTopic
  label: string
  Icon: React.ElementType
}

/** Explore's topics, in the order the levels run, Standards last. */
export const TOPICS: TopicTab[] = [
  { id: 'philosophies', label: 'Philosophies', Icon: BookOpen },
  { id: 'frameworks',   label: 'Frameworks',   Icon: Network },
  { id: 'modalities',   label: 'Modalities',   Icon: Zap },
  { id: 'archetypes',   label: 'Archetypes',   Icon: Layers },
  { id: 'exercises',    label: 'Exercises',    Icon: Dumbbell },
  { id: 'movements',    label: 'Movements',    Icon: PersonStanding },
  { id: 'equipment',    label: 'Equipment',    Icon: Wrench },
  { id: 'standards',    label: 'Standards',    Icon: Trophy },
]

export const TOPIC_ICONS = Object.fromEntries(TOPICS.map((t) => [t.id, t.Icon])) as Record<ExploreTopic, React.ElementType>

/** Open an entity's detail in Explore: `?topic=&id=`, pushed so Back steps
 *  back along the trail. */
export function useExploreNavigate() {
  const [, setSearchParams] = useSearchParams()
  return useCallback((topic: ExploreTopic, id: string) => {
    setSearchParams({ topic, id })
  }, [setSearchParams])
}
