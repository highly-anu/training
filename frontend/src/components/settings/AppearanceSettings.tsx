import { useTheme } from 'next-themes'
import { Check } from 'lucide-react'
import { cn } from '@/lib/utils'
import { THEMES } from '@/lib/themes'

/**
 * Settings → Appearance: the four themes as cards. The sidebar's quick
 * toggle stays; this is the place that explains what each one is.
 */
export function AppearanceSettings() {
  const { theme, setTheme } = useTheme()
  const current = THEMES.find((t) => t.id === theme)?.id ?? 'dark'

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Settings
          </p>
          <h2 className="text-2xl font-semibold tracking-tight">Appearance.</h2>
          <p className="text-sm text-muted-foreground max-w-prose">
            Remembered by this browser. The phone has its own setting under Settings ▸ Appearance.
          </p>
        </div>

        <div className="space-y-3">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">Theme</h3>
          <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="Theme">
            {THEMES.map((t) => {
              const selected = t.id === current
              return (
                <button
                  key={t.id}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  onClick={() => setTheme(t.id)}
                  className={cn(
                    'flex items-center gap-3 rounded-lg border p-4 text-left transition-colors',
                    selected ? 'border-primary/40 bg-primary/5' : 'border-border/30 bg-card/40 hover:bg-muted/40'
                  )}
                >
                  <span
                    className="size-8 shrink-0 rounded-full border border-border/50"
                    style={{ background: `linear-gradient(135deg, ${t.bg} 50%, ${t.primary} 50%)` }}
                    aria-hidden="true"
                  />
                  <span className="flex-1">
                    <span className="block text-sm font-medium">{t.label}</span>
                    <span className="block text-[11px] text-muted-foreground">{t.description}</span>
                  </span>
                  {selected && <Check className="size-4 text-primary shrink-0" aria-hidden="true" />}
                </button>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}
