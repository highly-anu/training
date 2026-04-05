import { useState } from 'react'
import { Plus, Pencil } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ModelTypeNav } from './ModelTypeNav'
import { ObjectList } from './ObjectList'
import { DetailPanel } from './DetailPanel'
import { AddExerciseDialog } from './AddExerciseDialog'
import { EditExerciseDialog } from './EditExerciseDialog'
import { AddArchetypeDialog } from './AddArchetypeDialog'
import { EditArchetypeDialog } from './EditArchetypeDialog'
import { EditFrameworkDialog } from './EditFrameworkDialog'
import { AddModalityDialog } from './AddModalityDialog'
import { AddGoalDialog } from './AddGoalDialog'
import { useAllData } from './useAllData'
import type { ModelType, OpenInOntologyFn } from './types'
import type { Archetype, Exercise, Framework } from '@/api/types'

export function ObjectBrowser({ onOpenInOntology }: { onOpenInOntology?: OpenInOntologyFn }) {
  const [selectedType, setSelectedType] = useState<ModelType>('exercises')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [showAddExercise, setShowAddExercise] = useState(false)
  const [showAddArchetype, setShowAddArchetype] = useState(false)
  const [showAddModality, setShowAddModality] = useState(false)
  const [showAddGoal, setShowAddGoal] = useState(false)
  const [editingExercise, setEditingExercise] = useState<Exercise | null>(null)
  const [editingArchetype, setEditingArchetype] = useState<Archetype | null>(null)
  const [editingFramework, setEditingFramework] = useState<Framework | null>(null)

  const allData = useAllData()

  function navigateTo(type: ModelType, id: string) {
    setSelectedType(type)
    setSelectedId(id)
    setSearchQuery('')
  }

  function handleTypeSelect(type: ModelType) {
    setSelectedType(type)
    setSelectedId(null)
    setSearchQuery('')
  }

  function getItemsForType(type: ModelType): Array<{ id: string; name?: string }> {
    switch (type) {
      case 'exercises': return allData.exercises
      case 'archetypes': return allData.archetypes
      case 'modalities': return allData.modalities
      case 'goals': return allData.goals
      case 'frameworks': return allData.frameworks
      case 'philosophies': return allData.philosophies
      case 'benchmarks': return allData.benchmarks
      case 'injuryFlags': return allData.injuryFlags
      case 'equipmentProfiles': return allData.equipmentProfiles
      default: return []
    }
  }

  const counts: Record<ModelType, number> = {
    exercises: allData.exercises.length,
    archetypes: allData.archetypes.length,
    modalities: allData.modalities.length,
    goals: allData.goals.length,
    frameworks: allData.frameworks.length,
    philosophies: allData.philosophies.length,
    benchmarks: allData.benchmarks.length,
    injuryFlags: allData.injuryFlags.length,
    equipmentProfiles: allData.equipmentProfiles.length,
  }

  const items = getItemsForType(selectedType)

  return (
    <div className="flex h-full min-h-0">
      {/* Left: model type nav */}
      <div className="w-[220px] shrink-0 flex flex-col">
        <ModelTypeNav selected={selectedType} onSelect={handleTypeSelect} counts={counts} />

        {/* Add / Edit buttons */}
        <div className="border-r border-t p-2 space-y-1 bg-muted/10">
          {selectedType === 'exercises' && (
            <Button size="sm" className="w-full h-7 text-xs" onClick={() => setShowAddExercise(true)}>
              <Plus className="size-3 mr-1" /> Add Exercise
            </Button>
          )}
          {selectedType === 'exercises' && selectedId && (() => {
            const ex = allData.exercises.find(e => e.id === selectedId)
            return ex ? (
              <Button size="sm" variant="outline" className="w-full h-7 text-xs" onClick={() => setEditingExercise(ex as unknown as Exercise)}>
                <Pencil className="size-3 mr-1" /> Edit Exercise
              </Button>
            ) : null
          })()}
          {selectedType === 'archetypes' && (
            <Button size="sm" className="w-full h-7 text-xs" onClick={() => setShowAddArchetype(true)}>
              <Plus className="size-3 mr-1" /> Add Archetype
            </Button>
          )}
          {selectedType === 'modalities' && (
            <Button size="sm" className="w-full h-7 text-xs" onClick={() => setShowAddModality(true)}>
              <Plus className="size-3 mr-1" /> Add Modality
            </Button>
          )}
          {selectedType === 'goals' && (
            <Button size="sm" className="w-full h-7 text-xs" onClick={() => setShowAddGoal(true)}>
              <Plus className="size-3 mr-1" /> Add Goal
            </Button>
          )}
          {selectedType === 'archetypes' && selectedId && (() => {
            const arch = allData.archetypes.find(a => a.id === selectedId)
            return arch ? (
              <Button size="sm" variant="outline" className="w-full h-7 text-xs" onClick={() => setEditingArchetype(arch as unknown as Archetype)}>
                <Pencil className="size-3 mr-1" /> Edit Archetype
              </Button>
            ) : null
          })()}
          {selectedType === 'frameworks' && selectedId && (() => {
            const fw = allData.frameworks.find(f => f.id === selectedId)
            return fw ? (
              <Button size="sm" variant="outline" className="w-full h-7 text-xs" onClick={() => setEditingFramework(fw as unknown as Framework)}>
                <Pencil className="size-3 mr-1" /> Edit Framework
              </Button>
            ) : null
          })()}
        </div>
      </div>

      {/* Center: object list */}
      <div className="w-[300px] shrink-0 flex flex-col">
        <ObjectList
          type={selectedType}
          items={items as Parameters<typeof ObjectList>[0]['items']}
          selectedId={selectedId}
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          onSelect={setSelectedId}
        />
      </div>

      {/* Right: detail panel */}
      <div className="flex-1 flex flex-col min-w-0">
        {allData.archetypesError && selectedType === 'archetypes' && (
          <div className="px-4 pt-2">
            <p className="text-xs text-destructive">
              Failed to load archetypes. Is the API server running?
            </p>
          </div>
        )}
        <DetailPanel
          type={selectedType}
          selectedId={selectedId}
          data={allData}
          navigateTo={navigateTo}
          onOpenInOntology={onOpenInOntology}
        />
      </div>

      {/* Dialogs */}
      <AddExerciseDialog open={showAddExercise} onClose={() => setShowAddExercise(false)} />
      <AddModalityDialog open={showAddModality} onClose={() => setShowAddModality(false)} />
      <AddGoalDialog open={showAddGoal} onClose={() => setShowAddGoal(false)} />
      {editingExercise && (
        <EditExerciseDialog
          exercise={editingExercise}
          open={!!editingExercise}
          onClose={() => setEditingExercise(null)}
        />
      )}
      <AddArchetypeDialog open={showAddArchetype} onClose={() => setShowAddArchetype(false)} />
      {editingArchetype && (
        <EditArchetypeDialog
          archetype={editingArchetype}
          open={!!editingArchetype}
          onClose={() => setEditingArchetype(null)}
        />
      )}
      {editingFramework && (
        <EditFrameworkDialog
          framework={editingFramework}
          open={!!editingFramework}
          onClose={() => setEditingFramework(null)}
        />
      )}
    </div>
  )
}
