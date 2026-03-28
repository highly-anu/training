import { Menu } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ThemeToggle } from '@/components/shared/ThemeToggle'
import { useUiStore } from '@/store/uiStore'
import { Activity } from 'lucide-react'

export function TopBar() {
  const toggleSidebar = useUiStore((s) => s.toggleSidebar)

  return (
    <header className="flex h-14 items-center gap-3 border-b bg-card px-4 md:hidden">
      <Button variant="ghost" size="icon" onClick={toggleSidebar} className="size-8">
        <Menu className="size-4" />
      </Button>
      <div className="flex items-center gap-2">
        <Activity className="size-4 text-primary" />
        <span className="font-semibold tracking-tight text-sm">Training</span>
      </div>
      <div className="ml-auto">
        <ThemeToggle />
      </div>
    </header>
  )
}
