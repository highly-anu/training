import { Toaster as Sonner } from 'sonner'
import { useTheme } from 'next-themes'

/**
 * Where `lib/toast.ts` shows its two messages: bottom centre, one at a time
 * above the content, in the theme's own surface colours. Mounted once, in App.
 */
export function Toaster() {
  const { resolvedTheme } = useTheme()
  return (
    <Sonner
      position="bottom-center"
      // Military and Zen are dark and light surfaces of their own; the tokens below colour all four.
      theme={resolvedTheme === 'light' || resolvedTheme === 'zen' ? 'light' : 'dark'}
      visibleToasts={2}
      style={{
        '--normal-bg': 'var(--popover)',
        '--normal-text': 'var(--popover-foreground)',
        '--normal-border': 'var(--border)',
        '--border-radius': 'var(--radius)',
      } as React.CSSProperties}
      toastOptions={{
        classNames: {
          toast: 'shadow-lg',
          actionButton: '!bg-primary !text-primary-foreground !font-medium',
        },
      }}
    />
  )
}
