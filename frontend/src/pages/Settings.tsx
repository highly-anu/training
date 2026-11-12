import { TabPanels } from '@/components/motion/TabPanels'
import { PageHeader } from '@/components/layout/PageHeader'
import { SubTabs } from '@/components/layout/SubTabs'
import { useSearchParams } from 'react-router-dom'
import { Page } from '@/components/layout/Page'
import { Settings as SettingsIcon, Plug, UserCircle, Palette, Terminal } from 'lucide-react'
import { useDevLabEnabled } from '@/lib/featureFlags'
import { ConnectionsSettings } from '@/components/settings/ConnectionsSettings'
import { AccountSettings } from '@/components/settings/AccountSettings'
import { AppearanceSettings } from '@/components/settings/AppearanceSettings'
import { DeveloperSettings } from '@/components/settings/DeveloperSettings'

/**
 * Configuration, not a destination: the services connected, the account,
 * the look, and (in dev builds and for `dev` users) the developer switches. Profile keeps what
 * is about the athlete — level, equipment, injuries, schedule, benchmarks,
 * heart rate. The phone's Settings screen holds the same set, pushed from
 * Profile's gear (ios/docs/design-system.md §6.13).
 *
 * Sub-tabs are URL-driven: the Garmin and Strava OAuth callbacks land on
 * `/settings?tab=connections&<provider>=connected`.
 */
export type SettingsTab = 'connections' | 'account' | 'appearance' | 'developer'

interface SubTabItem { id: SettingsTab; label: string; Icon: React.ElementType }

const SUB_TABS: SubTabItem[] = [
  { id: 'connections', label: 'Connections', Icon: Plug },
  { id: 'appearance',  label: 'Appearance',  Icon: Palette },
  { id: 'account',     label: 'Account',     Icon: UserCircle },
]
const DEVELOPER_TAB: SubTabItem = { id: 'developer', label: 'Developer', Icon: Terminal }

function isSettingsTab(value: string | null, tabs: SubTabItem[]): value is SettingsTab {
  return !!value && tabs.some((t) => t.id === value)
}

export function Settings() {
  const [searchParams, setSearchParams] = useSearchParams()
  const devLab = useDevLabEnabled()
  const tabs = devLab ? [...SUB_TABS, DEVELOPER_TAB] : SUB_TABS
  const requested = searchParams.get('tab')
  const activeTab: SettingsTab = isSettingsTab(requested, tabs) ? requested : 'connections'

  function setActiveTab(tab: SettingsTab) {
    const next = new URLSearchParams(searchParams)
    next.set('tab', tab)
    setSearchParams(next, { replace: true })
  }

  return (
    <Page
      key="settings"
      className="flex h-full flex-col"
    >
      <PageHeader
        icon={SettingsIcon}
        title="Settings"
        tabs={<SubTabs id="settings-tabs" label="Settings sections" tabs={tabs} active={activeTab} onChange={setActiveTab} />}
      />

      <TabPanels active={activeTab} order={tabs.map((t) => t.id)} tabsId="settings-tabs" className="flex-1 overflow-hidden">
        {activeTab === 'connections' && <ConnectionsSettings />}
        {activeTab === 'account'     && <AccountSettings />}
        {activeTab === 'appearance'  && <AppearanceSettings />}
        {activeTab === 'developer'   && devLab && <DeveloperSettings />}
      </TabPanels>
    </Page>
  )
}
