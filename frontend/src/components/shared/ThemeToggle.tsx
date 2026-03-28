import { useTheme } from 'next-themes'
import { Check } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

const THEMES = [
  { id: 'light',    label: 'Light',    bg: '#ffffff',  primary: '#f59e0b' },
  { id: 'dark',     label: 'Dark',     bg: '#1c1b27',  primary: '#f59e0b' },
  { id: 'military', label: 'Military', bg: '#1e2318',  primary: '#5b8a3c' },
  { id: 'zen',      label: 'Zen',      bg: '#f7f5f0',  primary: '#4a8c70' },
] as const

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const current = THEMES.find((t) => t.id === theme) ?? THEMES[1]

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8" aria-label="Select theme">
          <span
            className="size-4 rounded-full border border-border/50"
            style={{ background: `linear-gradient(135deg, ${current.bg} 50%, ${current.primary} 50%)` }}
          />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-44 p-1">
        {THEMES.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setTheme(t.id)}
            className="flex w-full items-center gap-2.5 rounded-md px-2 py-1.5 text-sm hover:bg-accent transition-colors"
          >
            <span
              className="size-4 rounded-full border border-border/50 shrink-0"
              style={{ background: `linear-gradient(135deg, ${t.bg} 50%, ${t.primary} 50%)` }}
            />
            <span className="flex-1 text-left">{t.label}</span>
            {theme === t.id && <Check className="size-3 text-primary shrink-0" />}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  )
}
