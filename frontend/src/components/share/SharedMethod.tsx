import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Wand2 } from 'lucide-react'
import type { ShareDocument } from '@/api/shares'
import { OverviewTab } from '@/components/explore/philosophy/OverviewTab'
import { PhilosophyHero } from '@/components/explore/philosophy/PhilosophyHero'
import { PhilosophyRules } from '@/components/explore/philosophy/PhilosophyRules'
import { PhilosophyTracks } from '@/components/explore/philosophy/PhilosophyTracks'
import { PHILOSOPHY_VIEWS, type PhilosophyView } from '@/components/explore/philosophy/views'
import { SubTabs } from '@/components/layout/SubTabs'
import { TabPanels } from '@/components/motion/TabPanels'
import { SessionBrowser } from '@/components/sessions/SessionBrowser'
import { Button } from '@/components/ui/button'
import { MethodsNeeded } from './MethodsNeeded'

const TABS_ID = 'shared-method-views'
const ORDER = PHILOSOPHY_VIEWS.map((v) => v.id)

/**
 * A shared method: what its reader can do with it first — save it, then build
 * from it — and below that the method as Explore lays one out, from the
 * document the link carries (the reader cannot load the sharer's package).
 * The same sections as Explore's page, with nothing that leads into the
 * reader's library: no comparison, no lineage, no editing.
 */
export function SharedMethod({ doc }: { doc: ShareDocument }) {
  const navigate = useNavigate()
  const [view, setView] = useState<PhilosophyView>('overview')
  const [sessionId, setSessionId] = useState<string | null>(null)
  const describe = doc.method?.describe
  const a = doc.availability
  const mine = a?.methods.find((m) => m.savable) ?? a?.methods[a.methods.length - 1]
  const ready = !!a?.ready

  return (
    <div className="space-y-5">
      <MethodsNeeded doc={doc} saveLabel="Save to your methods" />
      {ready && mine && (
        <Button size="sm" onClick={() => navigate(`/explore?topic=philosophies&id=${encodeURIComponent(mine.id)}`)}>
          <Wand2 className="mr-1.5 size-3.5" /> Open it in your library
        </Button>
      )}

      {describe && (
        <div className="space-y-5 border-t border-border/40 pt-5">
          <PhilosophyHero doc={describe} editing={false} canEdit={false} onEditing={() => {}} onRename={() => {}} compareWith={[]} />
          <div className="border-b border-border/60 pb-3">
            <SubTabs id={TABS_ID} label={`${describe.name} sections`} active={view} onChange={setView}
              tabs={PHILOSOPHY_VIEWS.map((v) => (v.id === 'sessions' ? { ...v, badge: describe.glance.counts.sessions } : v))} />
          </div>
          <TabPanels active={view} order={ORDER} tabsId={TABS_ID}>
            {view === 'overview' && (
              <OverviewTab doc={describe} spec={undefined} vocabulary={undefined} lineage={null} standalone
                nameOf={(id) => id} onSelect={() => {}} />
            )}
            {view === 'program' && <PhilosophyTracks doc={describe} />}
            {view === 'sessions' && (
              <SessionBrowser groups={describe.groups} sessions={describe.sessions}
                selectedId={sessionId && describe.sessions[sessionId] ? sessionId : null} onSelect={setSessionId} />
            )}
            {view === 'method' && <PhilosophyRules doc={describe} show="rules" />}
          </TabPanels>
        </div>
      )}
    </div>
  )
}
