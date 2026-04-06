import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { User, X, LogOut } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { EquipmentPicker } from '@/components/builder/EquipmentPicker'
import { InjuryPicker } from '@/components/builder/InjuryPicker'
import { LevelBar } from '@/components/benchmarks/LevelBar'
import { useProfileStore } from '@/store/profileStore'
import { useAuthStore } from '@/store/authStore'
import { useBenchmarks } from '@/api/benchmarks'
import { LoadingCard } from '@/components/shared/LoadingCard'
import type { CustomInjuryFlag, EquipmentId, InjuryFlagId, TrainingLevel } from '@/api/types'

// ── PR input ──────────────────────────────────────────────────────────────────

interface PrInputProps {
  benchId: string
  unit: string
}

function PrInput({ benchId, unit }: PrInputProps) {
  const logs = useProfileStore((s) => s.performanceLogs)
  const logPerformance = useProfileStore((s) => s.logPerformance)
  const removePerformanceLog = useProfileStore((s) => s.removePerformanceLog)

  const stored = logs[benchId]?.at(-1)?.value
  const [draft, setDraft] = useState(stored !== undefined ? String(stored) : '')

  useEffect(() => {
    setDraft(stored !== undefined ? String(stored) : '')
  }, [stored])

  function commit() {
    const n = parseFloat(draft)
    if (!isNaN(n) && n > 0) {
      logPerformance(benchId, n)
    } else if (draft.trim() === '') {
      removePerformanceLog(benchId)
    }
  }

  return (
    <div className="flex items-center gap-1 shrink-0">
      <input
        type="number"
        min={0}
        step="any"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => { if (e.key === 'Enter') { commit(); (e.target as HTMLInputElement).blur() } }}
        placeholder="PR"
        className="w-14 h-6 rounded border border-transparent bg-transparent text-right text-xs text-foreground placeholder:text-muted-foreground/30 hover:border-input focus:border-input focus:bg-card focus:outline-none px-1 transition-colors"
      />
      <span className="text-[10px] text-muted-foreground whitespace-nowrap">{unit.trim()}</span>
      {stored !== undefined && (
        <button
          type="button"
          onClick={() => { removePerformanceLog(benchId); setDraft('') }}
          className="text-muted-foreground/40 hover:text-destructive transition-colors"
        >
          <X className="size-3" />
        </button>
      )}
    </div>
  )
}

// ── Benchmark card ─────────────────────────────────────────────────────────────

function BenchCard({ bench }: { bench: { id: string; name: string; unit: string; standards: Record<string, number>; lower_is_better?: boolean | null } }) {
  const logs = useProfileStore((s) => s.performanceLogs)
  const userValue = logs[bench.id]?.at(-1)?.value

  return (
    <div className="rounded-xl border bg-card p-4 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold truncate">{bench.name}</p>
        <PrInput benchId={bench.id} unit={bench.unit} />
      </div>
      <LevelBar
        standards={bench.standards as Record<'entry' | 'intermediate' | 'advanced' | 'elite', number>}
        unit={bench.unit}
        lowerIsBetter={bench.lower_is_better ?? false}
        userValue={userValue}
      />
    </div>
  )
}

// ── Page ───────────────────────────────────────────────────────────────────────

export function ProfileBenchmarks() {
  const navigate = useNavigate()
  const {
    trainingLevel, equipment, injuryFlags, customInjuryFlags,
    setTrainingLevel, setEquipment, toggleInjuryFlag,
    addCustomInjuryFlag, removeCustomInjuryFlag,
  } = useProfileStore()
  const { user, savedAccounts, signOutCurrent, switchToAccount } = useAuthStore()
  const { data: benchmarks = [], isLoading: benchmarksLoading } = useBenchmarks()
  const [activeTab, setActiveTab] = useState<'setup' | 'benchmarks'>('setup')
  const [switching, setSwitching] = useState(false)

  return (
    <motion.div
      key="profile"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <User className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Profile</h1>
        <div className="ml-4 flex gap-1">
          {(['setup', 'benchmarks'] as const).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={cn(
                'px-3 py-1 rounded text-xs border transition-colors capitalize',
                activeTab === tab
                  ? 'bg-primary/15 border-primary/40 text-primary'
                  : 'border-border text-muted-foreground hover:bg-muted'
              )}
            >
              {tab}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {activeTab === 'setup' && (
          <div className="p-6 space-y-8">
            {/* Account */}
            {user && (
              <section className="space-y-2">
                <Label className="text-sm font-semibold">Account</Label>
                <div className="flex items-center gap-2 max-w-sm">
                  {savedAccounts.length > 1 ? (
                    <Select
                      value={user.email ?? ''}
                      onValueChange={async (val) => {
                        if (val === '__add__') { navigate('/login'); return }
                        if (val === user.email) return
                        setSwitching(true)
                        try { await switchToAccount(val) } finally { setSwitching(false) }
                      }}
                      disabled={switching}
                    >
                      <SelectTrigger className="flex-1 text-sm font-mono">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {savedAccounts.map((a) => (
                          <SelectItem key={a.email} value={a.email} className="text-sm font-mono">
                            {a.email}
                          </SelectItem>
                        ))}
                        <SelectSeparator />
                        <SelectItem value="__add__" className="text-sm text-muted-foreground">
                          Add another account →
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  ) : (
                    <span className="flex-1 text-sm font-mono text-muted-foreground truncate px-3 py-2 rounded-md border border-transparent bg-muted/40">
                      {user.email}
                    </span>
                  )}
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={signOutCurrent}
                    className="text-muted-foreground hover:text-destructive shrink-0"
                  >
                    <LogOut className="size-4 mr-1.5" />
                    Log out
                  </Button>
                </div>
              </section>
            )}

            <Separator />

            {/* Training level */}
            <section className="space-y-2 max-w-xs">
              <Label className="text-sm font-semibold">Training Level</Label>
              <Select value={trainingLevel} onValueChange={(v) => setTrainingLevel(v as TrainingLevel)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="novice">Novice</SelectItem>
                  <SelectItem value="intermediate">Intermediate</SelectItem>
                  <SelectItem value="advanced">Advanced</SelectItem>
                  <SelectItem value="elite">Elite</SelectItem>
                </SelectContent>
              </Select>
            </section>

            <Separator />

            {/* Equipment */}
            <section className="space-y-2">
              <Label className="text-sm font-semibold">Equipment Available</Label>
              <p className="text-xs text-muted-foreground">This pre-fills the program builder</p>
              <EquipmentPicker selected={equipment as EquipmentId[]} onChange={setEquipment} />
            </section>

            <Separator />

            {/* Injuries */}
            <section className="space-y-2">
              <Label className="text-sm font-semibold">Injury Flags</Label>
              <p className="text-xs text-muted-foreground">Current injuries — saved to your profile</p>
              <InjuryPicker
                selected={injuryFlags as InjuryFlagId[]}
                onChange={(flags) => {
                  const current = injuryFlags as InjuryFlagId[]
                  flags.forEach((f) => { if (!current.includes(f)) toggleInjuryFlag(f) })
                  current.forEach((f) => { if (!flags.includes(f)) toggleInjuryFlag(f) })
                }}
                customInjuries={customInjuryFlags}
                onCustomInjuriesChange={(injuries: CustomInjuryFlag[]) => {
                  const added = injuries.find((i) => !customInjuryFlags.some((c) => c.id === i.id))
                  const removed = customInjuryFlags.find((c) => !injuries.some((i) => i.id === c.id))
                  if (added) addCustomInjuryFlag(added)
                  if (removed) removeCustomInjuryFlag(removed.id)
                }}
              />
            </section>
          </div>
        )}

        {activeTab === 'benchmarks' && (
          <div className="p-6 space-y-6">
            {benchmarksLoading ? (
              <LoadingCard />
            ) : (
              <>
                <div>
                  <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1">Strength Standards</h2>
                  <p className="text-xs text-muted-foreground mb-4">
                    Enter your current PR to see your level — saved to your profile
                  </p>
                  <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                    {benchmarks.filter((b) => b.category === 'strength').map((bench) => (
                      <BenchCard key={bench.id} bench={bench} />
                    ))}
                  </div>
                </div>

                <Separator />

                <div>
                  <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Conditioning Standards</h2>
                  <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                    {benchmarks.filter((b) => b.category === 'conditioning').map((bench) => (
                      <BenchCard key={bench.id} bench={bench} />
                    ))}
                  </div>
                </div>

                {(() => {
                  const CELL_DOMAIN_LABELS: Record<string, string> = {
                    hips:      'Hips & Lower Body',
                    push:      'Push',
                    pull:      'Pull & Hinge',
                    core:      'Core',
                    endurance: 'Endurance',
                    skill:     'Skill',
                  }
                  const cellBenchmarks = benchmarks.filter((b) => b.category === 'cell')
                  if (cellBenchmarks.length === 0) return null
                  const domainOrder = ['hips', 'push', 'pull', 'core', 'endurance', 'skill']
                  const byDomain = domainOrder
                    .map((d) => ({ domain: d, items: cellBenchmarks.filter((b) => b.domain === d) }))
                    .filter(({ items }) => items.length > 0)
                  return (
                    <>
                      <Separator />
                      <div>
                        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1">Cell Standards</h2>
                        <p className="text-xs text-muted-foreground mb-5">
                          Five-tier benchmark system (The Cell Fitness). Levels I–IV shown.
                        </p>
                        <div className="space-y-6">
                          {byDomain.map(({ domain, items }) => (
                            <div key={domain}>
                              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-3">
                                {CELL_DOMAIN_LABELS[domain] ?? domain}
                              </p>
                              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                {items.map((bench) => (
                                  <BenchCard key={bench.id} bench={bench} />
                                ))}
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>
                    </>
                  )
                })()}
              </>
            )}
          </div>
        )}
      </div>
    </motion.div>
  )
}
