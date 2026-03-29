import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  Wand2,
  Calendar,
  Dumbbell,
  User,
  Activity,
  BookOpen,
  Upload,
  HeartPulse,
  Terminal,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { ThemeToggle } from '@/components/shared/ThemeToggle'
import { ScrollArea } from '@/components/ui/scroll-area'

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/builder', label: 'Build Program', icon: Wand2 },
  { to: '/program', label: 'My Program', icon: Calendar },
  { to: '/exercises', label: 'Exercises', icon: Dumbbell },
  { to: '/profile', label: 'Profile', icon: User },
  { to: '/philosophies', label: 'Philosophies', icon: BookOpen },
  { to: '/import', label: 'Import Workouts', icon: Upload },
  { to: '/bio', label: 'Bio Log', icon: HeartPulse },
  { to: '/dev', label: 'Dev Lab', icon: Terminal },
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
        <nav className="p-2 space-y-0.5">
          {NAV_ITEMS.map(({ to, label, icon: Icon, end }) => (
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
