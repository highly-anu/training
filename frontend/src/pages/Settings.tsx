import { useSearchParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Settings as SettingsIcon, Plug, UserCircle, Palette, Terminal } from 'lucide-react'
import { cn } from '@/lib/utils'
import { DEVLAB_ENABLED } from '@/lib/featureFlags'
import { ConnectionsSettings } from '@/components/settings/ConnectionsSettings'
import { AccountSettings } from '@/components/settings/AccountSettings'
import { AppearanceSettings } from '@/components/settings/AppearanceSettings'
import { DeveloperSettings } from '@/components/settings/DeveloperSettings'

/**
 * Configuration, not a destination: the services connected, the account,
 * the look, and (in dev builds) the developer switches. Profile keeps what
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
  { id: 'account',     label: 'Account',     Icon: UserCircle },
  { id: 'appearance',  label: 'Appearance',  Icon: Palette },
  ...(DEVLAB_ENABLED ? [{ id: 'developer' as const, label: 'Developer', Icon: Terminal }] : []),
]

const SUB_TAB_IDS = SUB_TABS.map((t) => t.id)

function isSettingsTab(value: string | null): value is SettingsTab {
  return !!value && (SUB_TAB_IDS as string[]).includes(value)
}

export function Settings() {
  const [searchParams, setSearchParams] = useSearchParams()
  const requested = searchParams.get('tab')
  const activeTab: SettingsTab = isSettingsTab(requested) ? requested : 'connections'

  function setActiveTab(tab: SettingsTab) {
    const next = new URLSearchParams(searchParams)
    next.set('tab', tab)
    setSearchParams(next, { replace: true })
  }

  return (
    <motion.div
      key="settings"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header — §17.2: icon, title, sub-tabs after a hairline */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <SettingsIcon className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Settings</h1>
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <div className="flex items-center gap-1" role="tablist" aria-label="Settings sections">
            {SUB_TABS.map((tab) => {
              const isActive = tab.id === activeTab
              const Icon = tab.Icon
              return (
                <button
                  key={tab.id}
                  type="button"
                  role="tab"
                  aria-selected={isActive}
                  onClick={() => setActiveTab(tab.id)}
                  className={cn(
                    'flex items-center gap-1.5 px-3 py-1 text-xs rounded border transition-colors',
                    isActive
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  )}
                >
                  <Icon className="size-3.5" />
                  {tab.label}
                </button>
              )
            })}
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-hidden">
        {activeTab === 'connections' && <ConnectionsSettings />}
        {activeTab === 'account'     && <AccountSettings />}
        {activeTab === 'appearance'  && <AppearanceSettings />}
        {activeTab === 'developer'   && DEVLAB_ENABLED && <DeveloperSettings />}
      </div>
    </motion.div>
  )
}
