import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BookOpen, CircleHelp, ExternalLink, Library, Sparkles } from 'lucide-react'
import { useAnalyticsSpecs } from '@/api/analyticsSpecs'
import { useFrameworks } from '@/api/frameworks'
import { useMethods } from '@/api/methods'
import { usePhilosophies } from '@/api/philosophies'
import { usePhilosophyDescription } from '@/api/philosophyDescription'
import { useSimilarity } from '@/api/similarity'
import { nearestTo } from '@/components/explore/compare/compareIds'
import { useLinkIndex } from '@/components/explore/useLineage'
import { SubTabs } from '@/components/layout/SubTabs'
import { MethodEditProvider } from '@/components/methods/MethodEdit'
import { RenameMethodDialog } from '@/components/methods/RenameMethodDialog'
import { TabPanels } from '@/components/motion/TabPanels'
import { ShareButton } from '@/components/share/ShareButton'
import { FailedState, LoadingState } from '@/components/shared/states'
import { lineageOf } from '@/lib/exploreLinks'
import { useBuilderStore } from '@/store/builderStore'
import { InlinePanel, StatTile } from './Glance'
import { OverviewTab } from './OverviewTab'
import { BackToPhilosophies, PhilosophyHero } from './PhilosophyHero'
import { PhilosophyRules } from './PhilosophyRules'
import { PhilosophySessions } from './PhilosophySessions'
import { PhilosophyTracks } from './PhilosophyTracks'
import { SessionLinkContext } from './sessionLink'
import { PHILOSOPHY_VIEWS, type PhilosophyView } from './views'

type MethodPanel = 'rules' | 'sources' | 'inventions' | 'open'

const TABS_ID = 'philosophy-views'
const VIEW_ORDER = PHILOSOPHY_VIEWS.map((v) => v.id)

/**
 * Explore ▸ Philosophies' detail (docs/frontend-design.md §13.7): a hero that
 * says what the method is, then one thing at a time — Overview (the week, what
 * it builds, what it needs), Program (tracks and phases), Sessions (the
 * session browser) and Method (rules and sources). The caller owns the view
 * and the open session (the URL's `view` and `session`), so both can be
 * linked. Every number comes from the server's document
 * (GET /philosophies/<id>/describe); the page only lays it out.
 */
export function PhilosophyPage({ id, view, onView, sessionId, onSession, onSelect, onCompare, onBack }: {
  id: string
  view: PhilosophyView; onView: (view: PhilosophyView) => void
  sessionId: string | null; onSession: (id: string | null) => void
  onSelect: (id: string) => void; onCompare?: (ids: string[]) => void; onBack?: () => void
}) {
  const { data: doc, isLoading, error, refetch } = usePhilosophyDescription(id)
  const { data: philosophies = [] } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: specs } = useAnalyticsSpecs()
  const { data: matrix } = useSimilarity()
  const { index, names, colors } = useLinkIndex()
  const lineage = useMemo(() => (index ? lineageOf(index, 'philosophies', id, names, colors) : null),
    [index, id, names, colors])
  const navigate = useNavigate()
  const prefill = useBuilderStore((s) => s.prefillFromPhilosophy)
  const [method, setMethod] = useState<MethodPanel | null>('rules')
  // An athlete's own method: its words can be edited here, where they are read.
  const { data: methods } = useMethods()
  const [editing, setEditing] = useState(false)
  const [renaming, setRenaming] = useState(false)
  const sessions = doc?.sessions
  const sessionLink = useMemo(() => ({
    has: (sid: string) => Boolean(sessions?.[sid]),
    open: (sid: string) => onSession(sid),
  }), [sessions, onSession])

  if (isLoading) {
    return <LoadingState shape="cards" count={3} label="Reading the package" className="p-6" />
  }
  if (error || !doc) {
    return (
      <div className="space-y-3 p-6">
        {onBack && <BackToPhilosophies onBack={onBack} />}
        <FailedState
          title="Could not load this philosophy"
          error={error ?? new Error('Not found')}
          onRetry={() => { void refetch() }}
        />
      </div>
    )
  }

  const g = doc.glance
  const phil = philosophies.find((p) => p.id === id)
  const nameOf = (pid: string) => philosophies.find((p) => p.id === pid)?.name ?? pid
  // The builder's gate is the server's; an account it is not on for is offered nothing.
  const canEdit = Boolean(doc.own) && methods != null && methods.reason !== 'not_enabled'
  const tabs = PHILOSOPHY_VIEWS.map((v) => (v.id === 'sessions' ? { ...v, badge: g.counts.sessions } : v))
  const toggleMethod = (m: MethodPanel) => setMethod((cur) => (cur === m ? null : m))

  return (
    <MethodEditProvider id={canEdit && editing ? doc.id : null}>
      <SessionLinkContext.Provider value={sessionLink}>
        <div className="h-full overflow-y-auto">
          <div className="mx-auto max-w-5xl space-y-6 px-4 py-5 sm:px-6">
            {onBack && <BackToPhilosophies onBack={onBack} />}

            <PhilosophyHero doc={doc} editing={editing} canEdit={canEdit} onEditing={setEditing}
              onRename={() => setRenaming(true)}
              share={<ShareButton title={doc.name} request={{ kind: 'package', package_id: doc.id }} />}
              compareWith={nearestTo([doc.id], philosophies.map((p) => p.id), matrix?.['philosophies'])
                .map((pid) => ({ id: pid, name: nameOf(pid) }))}
              onCompare={onCompare && ((pid) => onCompare([doc.id, pid]))}
              onBuild={phil && (() => {
                prefill(phil, frameworks.filter((f) => f.source_philosophy === id))
                navigate('/program/new')
              })} />

            <div className="border-b border-border/60 pb-3">
              <SubTabs id={TABS_ID} label={`${doc.name} sections`} tabs={tabs} active={view} onChange={onView} />
            </div>

            <TabPanels active={view} order={VIEW_ORDER} tabsId={TABS_ID}>
              {view === 'overview' && (
                <OverviewTab doc={doc} spec={specs?.philosophies[doc.id]} vocabulary={specs?.vocabulary}
                  lineage={lineage} nameOf={nameOf} onSelect={onSelect}
                  onCompare={onCompare && ((pid) => onCompare([doc.id, pid]))} />
              )}

              {view === 'program' && <PhilosophyTracks doc={doc} />}

              {view === 'sessions' && <PhilosophySessions doc={doc} sessionId={sessionId} onSession={onSession} />}

              {view === 'method' && (
                <div className="space-y-3">
                  <div className="grid gap-2 grid-cols-[repeat(auto-fill,minmax(11rem,1fr))]">
                    <StatTile icon={BookOpen} value={g.counts.rules || doc.principles.length}
                      label={g.counts.rules ? 'rules from the source' : 'principles'}
                      active={method === 'rules'} onClick={() => toggleMethod('rules')} />
                    <StatTile icon={Library} value={g.counts.sources} label="sources"
                      active={method === 'sources'} onClick={() => toggleMethod('sources')} />
                    <StatTile icon={Sparkles} value={g.counts.inventions} label="app decisions"
                      active={method === 'inventions'} onClick={() => toggleMethod('inventions')} />
                    <StatTile icon={CircleHelp} value={g.counts.open} label="not modelled yet"
                      active={method === 'open'} onClick={() => toggleMethod('open')} />
                  </div>
                  {method && (
                    <InlinePanel key={method} onClose={() => setMethod(null)}
                      title={{ rules: g.counts.rules ? 'What it holds true' : 'Core principles', sources: 'Sources',
                        inventions: 'Where the app decides', open: 'Not modelled yet' }[method]}
                      subtitle={{ rules: g.counts.rules ? 'The method’s rules, each with the passage it rests on.' : undefined,
                        sources: undefined, inventions: 'What the sources leave open and the app had to settle.',
                        open: 'What the package does not program yet.' }[method]}>
                      {method === 'sources'
                        ? (
                          <ul className="max-w-3xl space-y-1">
                            {doc.sources.map((s) => (
                              <li key={s.id ?? s.title} className="text-xs text-muted-foreground">
                                {s.where?.startsWith('http')
                                  ? (
                                    <a href={s.where} target="_blank" rel="noreferrer"
                                      className="inline-flex items-center gap-1 hover:text-foreground hover:underline">
                                      {s.title} <ExternalLink className="size-2.5" />
                                    </a>
                                  )
                                  : s.title}
                                {s.published && <span className="text-muted-foreground/60"> ({s.published.slice(0, 4)})</span>}
                              </li>
                            ))}
                          </ul>
                        )
                        : <PhilosophyRules doc={doc} show={method} />}
                    </InlinePanel>
                  )}
                </div>
              )}
            </TabPanels>
          </div>
        </div>
        <RenameMethodDialog method={renaming ? { id: doc.id, name: doc.name } : null} onClose={() => setRenaming(false)} />
      </SessionLinkContext.Provider>
    </MethodEditProvider>
  )
}
