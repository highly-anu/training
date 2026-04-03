import { useState } from 'react'
import { motion } from 'framer-motion'
import { BookOpen } from 'lucide-react'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Separator } from '@/components/ui/separator'
import { Badge } from '@/components/ui/badge'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { usePhilosophies } from '@/api/philosophies'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import type { Philosophy, ModalityId } from '@/api/types'

const containerVariants = {
  animate: { transition: { staggerChildren: 0.04 } },
}
const itemVariants = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.2 } },
}

function prettify(id: string) {
  return id.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function BiasChip({ id }: { id: string }) {
  const color = MODALITY_COLORS[id as ModalityId]
  return (
    <span className={cn(
      'inline-block px-1.5 py-0.5 rounded text-[10px] font-medium',
      color ? `${color.bg} ${color.text}` : 'bg-muted/50 text-muted-foreground'
    )}>
      {color?.label ?? prettify(id)}
    </span>
  )
}

function ConnectionCount({ connections }: { connections: Philosophy['system_connections'] }) {
  const parts: string[] = []
  const frameworks = connections?.frameworks ?? []
  const goals = connections?.goals ?? []
  if (frameworks.length)
    parts.push(`${frameworks.length} framework${frameworks.length > 1 ? 's' : ''}`)
  if (goals.length)
    parts.push(`${goals.length} goal${goals.length > 1 ? 's' : ''}`)
  if (!parts.length) return null
  return <span className="text-[10px] text-muted-foreground">{parts.join(' · ')}</span>
}

export function Philosophies() {
  const { data: philosophies = [], isLoading, error } = usePhilosophies()
  const [selected, setSelected] = useState<Philosophy | null>(null)

  return (
    <motion.div
      key="philosophies"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <BookOpen className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Philosophies</h1>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        {isLoading ? (
          <LoadingCard />
        ) : error ? (
          <ErrorBanner error={error as Error} />
        ) : (
          <motion.div
            variants={containerVariants}
            initial="initial"
            animate="animate"
            className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            {philosophies.map((phil) => {
              const accentColor = MODALITY_COLORS[phil.bias[0] as ModalityId]?.hex ?? '#6366f1'
              const firstSentence = phil.notes.trim().split('. ')[0]
              return (
                <motion.div key={phil.id} variants={itemVariants}>
                  <button
                    type="button"
                    onClick={() => setSelected(phil)}
                    className="w-full text-left rounded-xl border bg-card p-4 space-y-2.5 hover:border-primary/40 transition-colors"
                    style={{ borderLeftColor: accentColor, borderLeftWidth: 3 }}
                  >
                    <div>
                      <p className="text-sm font-semibold leading-tight">{phil.name}</p>
                      <div className="flex flex-wrap gap-1 mt-1.5">
                        {phil.bias.map((b) => <BiasChip key={b} id={b} />)}
                      </div>
                    </div>
                    <p className="text-xs text-muted-foreground leading-relaxed line-clamp-2">
                      {firstSentence}.
                    </p>
                    <div className="flex items-center justify-between pt-0.5">
                      <span className="text-[10px] text-muted-foreground capitalize">
                        {phil.intensity_model.replace(/_/g, ' ')}
                      </span>
                      <ConnectionCount connections={phil.system_connections} />
                    </div>
                  </button>
                </motion.div>
              )
            })}
          </motion.div>
        )}
      </div>

      <Sheet open={!!selected} onOpenChange={(v) => !v && setSelected(null)}>
        <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
          {selected && (
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0, transition: { delay: 0.1, duration: 0.25 } }}
              className="space-y-5"
            >
              <SheetHeader>
                <SheetTitle className="text-left leading-snug">{selected.name}</SheetTitle>
                <div className="flex flex-wrap gap-1 pt-1">
                  {selected.bias.map((b) => <BiasChip key={b} id={b} />)}
                </div>
              </SheetHeader>

              <Separator />

              {/* Notes */}
              <p className="text-sm text-muted-foreground leading-relaxed">{selected.notes.trim()}</p>

              <Separator />

              {/* Core principles */}
              <div>
                <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Core Principles</h3>
                <ul className="space-y-1.5">
                  {selected.core_principles.map((p) => (
                    <li key={p} className="text-xs text-muted-foreground flex gap-2 items-start">
                      <span className="mt-1.5 size-1 rounded-full bg-muted-foreground shrink-0" />
                      {p.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase())}
                    </li>
                  ))}
                </ul>
              </div>

              <Separator />

              {/* Domain */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Scope</h3>
                  <div className="flex flex-wrap gap-1">
                    {selected.scope.map((s) => (
                      <span key={s} className="text-[10px] bg-muted/50 text-muted-foreground px-1.5 py-0.5 rounded">
                        {prettify(s)}
                      </span>
                    ))}
                  </div>
                </div>
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Primary Bias</h3>
                  <div className="flex flex-wrap gap-1">
                    {selected.bias.map((b) => <BiasChip key={b} id={b} />)}
                  </div>
                </div>
              </div>

              {/* Training model */}
              <div className="grid grid-cols-2 gap-4 text-xs">
                <div>
                  <dt className="font-semibold uppercase tracking-wide text-[10px] text-muted-foreground mb-0.5">
                    Intensity Model
                  </dt>
                  <dd className="capitalize">{selected.intensity_model.replace(/_/g, ' ')}</dd>
                </div>
                <div>
                  <dt className="font-semibold uppercase tracking-wide text-[10px] text-muted-foreground mb-0.5">
                    Progression
                  </dt>
                  <dd className="capitalize">{selected.progression_philosophy.replace(/_/g, ' ')}</dd>
                </div>
              </div>

              {/* Equipment */}
              {selected.required_equipment.length > 0 && (
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Required Equipment</h3>
                  <div className="flex flex-wrap gap-1">
                    {selected.required_equipment.map((e) => (
                      <span key={e} className="text-[10px] bg-muted/50 text-muted-foreground px-1.5 py-0.5 rounded capitalize">
                        {e.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Conflicts with */}
              {selected.avoid_with.length > 0 && (
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Conflicts With</h3>
                  <div className="flex flex-wrap gap-1">
                    {selected.avoid_with.map((id) => {
                      const other = philosophies.find((p) => p.id === id)
                      return (
                        <button
                          key={id}
                          type="button"
                          onClick={() => setSelected(other ?? null)}
                          className="text-[10px] bg-destructive/10 text-destructive px-1.5 py-0.5 rounded hover:bg-destructive/20 transition-colors"
                        >
                          {other?.name ?? prettify(id)}
                        </button>
                      )
                    })}
                  </div>
                </div>
              )}

              {/* System connections */}
              {((selected.system_connections?.frameworks?.length ?? 0) > 0 || (selected.system_connections?.goals?.length ?? 0) > 0) && (
                <>
                  <Separator />
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide mb-3">Shows Up As</h3>
                    <div className="space-y-2">
                      {(selected.system_connections?.frameworks?.length ?? 0) > 0 && (
                        <div>
                          <p className="text-[10px] text-muted-foreground mb-1.5">Frameworks</p>
                          <div className="flex flex-wrap gap-1">
                            {selected.system_connections.frameworks.map((id) => (
                              <Badge key={id} variant="secondary" className="text-[10px]">
                                {prettify(id)}
                              </Badge>
                            ))}
                          </div>
                        </div>
                      )}
                      {(selected.system_connections?.goals?.length ?? 0) > 0 && (
                        <div>
                          <p className="text-[10px] text-muted-foreground mb-1.5">Goal Profiles</p>
                          <div className="flex flex-wrap gap-1">
                            {selected.system_connections.goals.map((id) => (
                              <Badge key={id} variant="outline" className="text-[10px]">
                                {prettify(id)}
                              </Badge>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                </>
              )}

              {/* Sources */}
              {selected.sources.length > 0 && (
                <>
                  <Separator />
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide mb-2">Sources</h3>
                    <ul className="space-y-1">
                      {selected.sources.map((s) => (
                        <li key={s} className="text-[10px] text-muted-foreground">{s}</li>
                      ))}
                    </ul>
                  </div>
                </>
              )}
            </motion.div>
          )}
        </SheetContent>
      </Sheet>
    </motion.div>
  )
}
