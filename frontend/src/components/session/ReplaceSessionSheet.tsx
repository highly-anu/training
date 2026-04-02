import { useEffect, useMemo, useRef, useState } from 'react'
import { CheckCircle2, ChevronDown, ChevronUp, Clock, Loader2, RefreshCw } from 'lucide-react'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Slider } from '@/components/ui/slider'
import { Checkbox } from '@/components/ui/checkbox'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'
import { Badge } from '@/components/ui/badge'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { EquipmentPicker } from '@/components/builder/EquipmentPicker'
import { InjuryPicker } from '@/components/builder/InjuryPicker'
import { useArchetypes } from '@/api/archetypes'
import { useGenerateSession } from '@/api/programs'
import { useProgramStore } from '@/store/programStore'
import { cn } from '@/lib/utils'
import type { Archetype, EquipmentId, FatigueState, GeneratedProgram, InjuryFlagId, Session, WeekData } from '@/api/types'

interface ReplaceSessionSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  session: Session
  weekIndex: number
  weekData: WeekData
  day: string
  sessionIndex: number
  program: GeneratedProgram
}

export function ReplaceSessionSheet({
  open,
  onOpenChange,
  session,
  weekIndex,
  weekData,
  day,
  sessionIndex,
  program,
}: ReplaceSessionSheetProps) {
  const replaceSession = useProgramStore((s) => s.replaceSession)
  const generateSession = useGenerateSession()
  const { data: archetypes } = useArchetypes()

  // Browse tab state
  const [searchQuery, setSearchQuery] = useState('')
  const [sameModalityOnly, setSameModalityOnly] = useState(true)
  const [selectedArchId, setSelectedArchId] = useState<string | null>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  // Generate tab state
  const [showConstraints, setShowConstraints] = useState(false)
  const [timeOverride, setTimeOverride] = useState<number | null>(null)
  const [equipOverride, setEquipOverride] = useState<EquipmentId[] | null>(null)
  const [injuryOverride, setInjuryOverride] = useState<InjuryFlagId[] | null>(null)
  const [fatigueOverride, setFatigueOverride] = useState<FatigueState | null>(null)

  // Shared: pending session preview
  const [pendingSession, setPendingSession] = useState<Session | null>(null)

  // Reset on close
  useEffect(() => {
    if (!open) {
      setPendingSession(null)
      setSelectedArchId(null)
      setSearchQuery('')
      setShowConstraints(false)
      setTimeOverride(null)
      setEquipOverride(null)
      setInjuryOverride(null)
      setFatigueOverride(null)
      generateSession.reset()
    }
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  // Auto-focus search on open
  useEffect(() => {
    if (open) {
      setTimeout(() => searchRef.current?.focus(), 100)
    }
  }, [open])

  const filtered = useMemo(() => {
    const q = searchQuery.toLowerCase()
    return (archetypes ?? [])
      .filter((a) => !sameModalityOnly || a.modality === session.modality)
      .filter((a) => !q || a.name.toLowerCase().includes(q) || a.category.toLowerCase().includes(q))
      .sort((a, b) => {
        const aMatch = a.modality === session.modality ? 0 : 1
        const bMatch = b.modality === session.modality ? 0 : 1
        return aMatch - bMatch || a.name.localeCompare(b.name)
      })
  }, [archetypes, searchQuery, sameModalityOnly, session.modality])

  const effectiveConstraints = {
    session_time_minutes: timeOverride ?? program.constraints.session_time_minutes ?? 60,
    equipment: equipOverride ?? program.constraints.equipment ?? [],
    injury_flags: injuryOverride ?? program.constraints.injury_flags ?? [],
    training_level: program.constraints.training_level ?? 'intermediate',
    fatigue_state: fatigueOverride ?? program.constraints.fatigue_state ?? 'normal',
  }

  const overrideCount = [timeOverride, equipOverride, injuryOverride, fatigueOverride].filter(
    (v) => v !== null
  ).length

  const baseParams = {
    goalId: program.goal.id,
    modality: session.modality,
    phase: weekData.phase,
    weekInPhase: weekData.week_in_phase,
    isDeload: weekData.is_deload,
    constraints: effectiveConstraints,
  }

  function handleArchetypeClick(arch: Archetype) {
    setSelectedArchId(arch.id)
    setPendingSession(null)
    generateSession.mutate(
      { ...baseParams, archetypeId: arch.id },
      { onSuccess: (data) => setPendingSession(data) }
    )
  }

  function handleGenerate() {
    setPendingSession(null)
    generateSession.mutate(baseParams, {
      onSuccess: (data) => setPendingSession(data),
    })
  }

  function handleConfirm() {
    if (!pendingSession) return
    replaceSession(weekIndex, day, sessionIndex, pendingSession)
    onOpenChange(false)
  }

  function handleTryAgain() {
    setPendingSession(null)
    setSelectedArchId(null)
    generateSession.reset()
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="sm:max-w-md flex flex-col p-0">
        <SheetHeader className="px-5 py-4 border-b shrink-0">
          <SheetTitle className="flex items-center gap-2">
            <RefreshCw className="size-4" />
            Replace Session
          </SheetTitle>
          <div className="flex items-center gap-2 mt-1">
            <ModalityBadge modality={session.modality} size="sm" />
            <span className="text-xs text-muted-foreground truncate">
              {session.archetype?.name}
            </span>
          </div>
        </SheetHeader>

        <div className="flex-1 flex flex-col overflow-hidden">
          <Tabs defaultValue="browse" className="flex-1 flex flex-col overflow-hidden">
            <TabsList className="mx-5 mt-4 shrink-0">
              <TabsTrigger value="browse" className="flex-1">Browse</TabsTrigger>
              <TabsTrigger value="generate" className="flex-1">Generate</TabsTrigger>
            </TabsList>

            {/* Browse Tab */}
            <TabsContent value="browse" className="flex-1 flex flex-col overflow-hidden mt-0 px-5 pt-4">
              <div className="space-y-3 shrink-0">
                <Input
                  ref={searchRef}
                  placeholder="Search archetypes…"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                />
                <div
                  className="flex items-center gap-2 cursor-pointer"
                  onClick={() => setSameModalityOnly((v) => !v)}
                >
                  <Checkbox
                    id="same-modality"
                    checked={sameModalityOnly}
                    onCheckedChange={(v) => setSameModalityOnly(Boolean(v))}
                    className="pointer-events-none"
                  />
                  <Label htmlFor="same-modality" className="text-xs cursor-pointer">
                    Same modality only
                  </Label>
                </div>
              </div>

              <ScrollArea className="flex-1 mt-3 -mx-1 px-1">
                <div className="space-y-1.5 pb-2">
                  {filtered.length === 0 ? (
                    <p className="text-xs text-muted-foreground text-center py-8">No archetypes match</p>
                  ) : (
                    filtered.map((arch) => {
                      const isSelected = selectedArchId === arch.id
                      const isLoading = isSelected && generateSession.isPending
                      return (
                        <button
                          key={arch.id}
                          type="button"
                          onClick={() => handleArchetypeClick(arch)}
                          disabled={generateSession.isPending}
                          className={cn(
                            'w-full text-left rounded-lg border px-3 py-2.5 transition-colors relative',
                            isSelected
                              ? 'border-primary/60 bg-primary/5'
                              : 'border-border hover:border-primary/40 hover:bg-muted/30',
                            generateSession.isPending && !isSelected && 'opacity-50 cursor-not-allowed'
                          )}
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <p className="text-xs font-semibold truncate">{arch.name}</p>
                              <div className="flex items-center gap-2 mt-1 flex-wrap">
                                <ModalityBadge modality={arch.modality} size="sm" />
                                <span className="text-[10px] text-muted-foreground capitalize">
                                  {arch.category.replace(/_/g, ' ')}
                                </span>
                              </div>
                            </div>
                            <div className="shrink-0 flex items-center gap-1.5 text-[10px] text-muted-foreground mt-0.5">
                              {isLoading ? (
                                <Loader2 className="size-3.5 animate-spin text-primary" />
                              ) : (
                                <>
                                  <Clock className="size-3" />
                                  {arch.duration_estimate_minutes}m
                                </>
                              )}
                            </div>
                          </div>
                        </button>
                      )
                    })
                  )}
                </div>
              </ScrollArea>
            </TabsContent>

            {/* Generate Tab */}
            <TabsContent value="generate" className="flex-1 flex flex-col overflow-hidden mt-0">
              <ScrollArea className="flex-1 px-5 pt-4">
                <div className="space-y-5 pb-4">
                  {/* Fatigue state */}
                  <div className="space-y-1.5">
                    <Label className="text-xs">Fatigue state</Label>
                    <Select
                      value={fatigueOverride ?? effectiveConstraints.fatigue_state}
                      onValueChange={(v) => setFatigueOverride(v as FatigueState)}
                    >
                      <SelectTrigger className="h-9 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="fresh">Fresh</SelectItem>
                        <SelectItem value="normal">Normal</SelectItem>
                        <SelectItem value="accumulated">Accumulated</SelectItem>
                        <SelectItem value="overreached">Overreached</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  {/* Customize constraints toggle */}
                  <div>
                    <button
                      type="button"
                      onClick={() => setShowConstraints((v) => !v)}
                      className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                    >
                      {showConstraints ? (
                        <ChevronUp className="size-3.5" />
                      ) : (
                        <ChevronDown className="size-3.5" />
                      )}
                      Customize constraints
                      {overrideCount > 0 && (
                        <Badge variant="secondary" className="ml-1 text-[10px] px-1.5 py-0">
                          {overrideCount} override{overrideCount !== 1 ? 's' : ''}
                        </Badge>
                      )}
                    </button>

                    {showConstraints && (
                      <div className="mt-4 space-y-5">
                        {/* Session time */}
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <Label className="text-xs">Session time</Label>
                            <span className="text-xs font-medium">
                              {effectiveConstraints.session_time_minutes} min
                            </span>
                          </div>
                          <Slider
                            min={15}
                            max={120}
                            step={5}
                            value={[effectiveConstraints.session_time_minutes]}
                            onValueChange={([v]) => setTimeOverride(v)}
                            className="w-full"
                          />
                        </div>

                        <Separator />

                        {/* Equipment */}
                        <div className="space-y-2">
                          <Label className="text-xs">Equipment</Label>
                          <EquipmentPicker
                            selected={effectiveConstraints.equipment as EquipmentId[]}
                            onChange={(eq) => setEquipOverride(eq)}
                          />
                        </div>

                        <Separator />

                        {/* Injury flags */}
                        <div className="space-y-2">
                          <Label className="text-xs">Injury flags</Label>
                          <InjuryPicker
                            selected={effectiveConstraints.injury_flags as InjuryFlagId[]}
                            onChange={(flags) => setInjuryOverride(flags)}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </ScrollArea>

              {/* Generate button */}
              <div className="px-5 py-4 border-t shrink-0">
                <Button
                  className="w-full"
                  onClick={handleGenerate}
                  disabled={generateSession.isPending}
                >
                  {generateSession.isPending ? (
                    <><Loader2 className="size-4 mr-2 animate-spin" /> Generating…</>
                  ) : (
                    <><RefreshCw className="size-4 mr-2" /> Generate Session</>
                  )}
                </Button>
              </div>
            </TabsContent>
          </Tabs>

          {/* Error state */}
          {generateSession.isError && !pendingSession && (
            <div className="mx-5 mb-4 rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2.5 text-xs text-destructive">
              Failed to generate session. Check API connection and try again.
            </div>
          )}

          {/* Pending session preview */}
          {pendingSession && (
            <div className="border-t shrink-0">
              <div className="px-5 py-4 space-y-3">
                <div className="flex items-start gap-2">
                  <CheckCircle2 className="size-4 text-emerald-500 mt-0.5 shrink-0" />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold truncate">
                      {pendingSession.archetype?.name}
                    </p>
                    <div className="flex items-center gap-2 mt-1 flex-wrap">
                      <ModalityBadge modality={pendingSession.modality} size="sm" />
                      {pendingSession.archetype?.duration_estimate_minutes && (
                        <span className="text-[10px] text-muted-foreground flex items-center gap-1">
                          <Clock className="size-3" />
                          ~{pendingSession.archetype.duration_estimate_minutes} min
                        </span>
                      )}
                      <span className="text-[10px] text-muted-foreground">
                        {pendingSession.exercises.filter((e) => e.exercise).length || 'Coach-led'} {pendingSession.exercises.filter((e) => e.exercise).length ? 'exercises' : ''}
                      </span>
                    </div>
                    <p className="text-[10px] text-muted-foreground mt-1 truncate">
                      {pendingSession.exercises
                        .filter((e) => e.exercise)
                        .slice(0, 4)
                        .map((e) => e.exercise?.name)
                        .join(', ')}
                      {pendingSession.exercises.filter((e) => e.exercise).length > 4 && '…'}
                    </p>
                  </div>
                </div>

                <div className="flex gap-2">
                  <Button variant="outline" size="sm" className="flex-1" onClick={handleTryAgain}>
                    Try Again
                  </Button>
                  <Button size="sm" className="flex-1" onClick={handleConfirm}>
                    Confirm Replace
                  </Button>
                </div>
              </div>
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  )
}
