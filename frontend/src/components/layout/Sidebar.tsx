import { NavLink } from 'react-router-dom'
import {
  House,
  Calendar,
  ClipboardList,
  BarChart3,
  Compass,
  User,
  Activity,
  Terminal,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { ThemeToggle } from '@/components/shared/ThemeToggle'
import { ScrollArea } from '@/components/ui/scroll-area'
import { DEVLAB_ENABLED } from '@/lib/featureFlags'

interface NavItem {
  to: string
  label: string
  icon: React.ElementType
  end?: boolean
}

interface NavGroup {
  label: string
  items: NavItem[]
}

// Grouped by the journey (docs/information-architecture.md): Train is where
// the athlete lives day to day, Insight interprets it, Library is reference,
// You is configuration. The builder is a flow launched from Program, Home's
// empty state and Explore — not a place of its own.
const NAV_GROUPS: NavGroup[] = [
  {
    label: 'Train',
    items: [
      { to: '/', label: 'Home', icon: House, end: true },
      { to: '/program', label: 'Program', icon: Calendar },
      { to: '/log', label: 'Log', icon: ClipboardList },
    ],
  },
  {
    label: 'Insight',
    items: [{ to: '/analytics', label: 'Analytics', icon: BarChart3 }],
  },
  {
    label: 'Library',
    items: [{ to: '/explore', label: 'Explore', icon: Compass }],
  },
  {
    label: 'You',
    items: [{ to: '/profile', label: 'Profile', icon: User }],
  },
  // Developer tooling: present in dev builds, absent from production unless
  // the build sets VITE_DEVLAB=1 (src/lib/featureFlags.ts).
  ...(DEVLAB_ENABLED
    ? [{ label: 'Dev', items: [{ to: '/dev', label: 'Dev Lab', icon: Terminal }] }]
    : []),
]

export function Sidebar() {
  return (
    <aside className="flex h-full w-56 flex-col border-r bg-card">
      {/* Logo */}
      <div className="flex h-14 items-center gap-2 border-b px-4">
        <Activity className="size-5 text-primary" />
        <span className="font-semibold tracking-tight text-foreground">Training</span>
      </div>

      {/* Nav */}
      <ScrollArea className="flex-1">
        <nav className="p-2 space-y-3" aria-label="Primary">
          {NAV_GROUPS.map((group) => (
            <div key={group.label} className="space-y-0.5">
              <p className="px-3 pt-2 pb-1 text-[10px] font-medium uppercase tracking-widest text-muted-foreground/50 select-none">
                {group.label}
              </p>
              {group.items.map(({ to, label, icon: Icon, end }) => (
                <NavLink
                  key={to}
                  to={to}
                  end={end}
                  className={({ isActive }) =>
                    cn(
                      'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
                      isActive
                        ? 'bg-primary/10 text-primary'
                        : 'text-muted-foreground hover:bg-accent hover:text-foreground'
                    )
                  }
                >
                  <Icon className="size-4 shrink-0" />
                  {label}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
      </ScrollArea>

      {/* Footer */}
      <div className="flex items-center justify-between border-t p-3">
        <span className="text-xs text-muted-foreground">v0.1</span>
        <ThemeToggle />
      </div>
    </aside>
  )
}
