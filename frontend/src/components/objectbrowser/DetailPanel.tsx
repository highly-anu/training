import { ScrollArea } from '@/components/ui/scroll-area'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ExerciseDetail } from './detail/ExerciseDetail'
import { ArchetypeDetail } from './detail/ArchetypeDetail'
import { ModalityDetail } from './detail/ModalityDetail'
import { FrameworkDetail } from './detail/FrameworkDetail'
import { PhilosophyDetail } from './detail/PhilosophyDetail'
import { BenchmarkDetail } from './detail/BenchmarkDetail'
import { InjuryFlagDetail } from './detail/InjuryFlagDetail'
import { EquipmentProfileDetail } from './detail/EquipmentProfileDetail'
import type { ModelType, NavigateToFn, OpenInOntologyFn } from './types'
import type {
  Exercise, Archetype, Modality, Framework,
  Philosophy, BenchmarkStandard, InjuryFlag, EquipmentProfile,
} from '@/api/types'

interface AllData {
  exercises: Exercise[]
  archetypes: Archetype[]
  modalities: Modality[]
  frameworks: Framework[]
  philosophies: Philosophy[]
  benchmarks: BenchmarkStandard[]
  injuryFlags: InjuryFlag[]
  equipmentProfiles: EquipmentProfile[]
  isLoading: boolean
}

interface DetailPanelProps {
  type: ModelType
  selectedId: string | null
  data: AllData
  navigateTo: NavigateToFn
  onOpenInOntology?: OpenInOntologyFn
}

export function DetailPanel({ type, selectedId, data, navigateTo, onOpenInOntology }: DetailPanelProps) {
  if (!selectedId) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <EmptyState title="Select an item" description="Click any item in the list to inspect it." />
      </div>
    )
  }

  if (data.isLoading) {
    return (
      <div className="flex-1 p-6 space-y-3">
        <LoadingCard lines={5} />
        <LoadingCard lines={3} />
      </div>
    )
  }

  function renderContent() {
    switch (type) {
      case 'exercises': {
        const item = data.exercises.find(e => e.id === selectedId)
        if (!item) return null
        return <ExerciseDetail exercise={item} navigateTo={navigateTo} />
      }
      case 'archetypes': {
        const item = data.archetypes.find(a => a.id === selectedId)
        if (!item) return null
        return <ArchetypeDetail archetype={item} navigateTo={navigateTo} onOpenInOntology={onOpenInOntology} />
      }
      case 'modalities': {
        const item = data.modalities.find(m => m.id === selectedId)
        if (!item) return null
        return (
          <ModalityDetail
            modality={item}
            archetypes={data.archetypes}
            navigateTo={navigateTo}
            onOpenInOntology={onOpenInOntology}
          />
        )
      }
      case 'frameworks': {
        const item = data.frameworks.find(f => f.id === selectedId)
        if (!item) return null
        return <FrameworkDetail framework={item} navigateTo={navigateTo} onOpenInOntology={onOpenInOntology} />
      }
      case 'philosophies': {
        const item = data.philosophies.find(p => p.id === selectedId)
        if (!item) return null
        return <PhilosophyDetail philosophy={item} navigateTo={navigateTo} onOpenInOntology={onOpenInOntology} />
      }
      case 'benchmarks': {
        const item = data.benchmarks.find(b => b.id === selectedId)
        if (!item) return null
        return <BenchmarkDetail benchmark={item} />
      }
      case 'injuryFlags': {
        const item = data.injuryFlags.find(f => f.id === selectedId)
        if (!item) return null
        return <InjuryFlagDetail flag={item} navigateTo={navigateTo} />
      }
      case 'equipmentProfiles': {
        const item = data.equipmentProfiles.find(p => p.id === selectedId)
        if (!item) return null
        return <EquipmentProfileDetail profile={item} exercises={data.exercises} navigateTo={navigateTo} />
      }
      default:
        return null
    }
  }

  const content = renderContent()
  if (!content) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <EmptyState title="Not found" description={`No ${type} found with id "${selectedId}".`} />
      </div>
    )
  }

  return (
    <ScrollArea className="flex-1">
      <div className="p-5">{content}</div>
    </ScrollArea>
  )
}
