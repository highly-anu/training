import { useEffect, useState } from 'react'
import { Check, Share2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useCreateShare, type ShareRequest } from '@/api/shares'
import { announce } from '@/lib/announce'
import { shareLink } from '@/lib/share'
import { toast } from '@/lib/toast'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

/**
 * Share a method, the program or a session: makes the link, then hands it to
 * the system's share sheet or copies it. What happened is said on the button
 * itself — "Link copied" — and to a screen reader; a failure stays beside it
 * with the link to copy by hand (docs/frontend-design.md §13.14).
 */
export function ShareButton({ request, title, label = 'Share', icon = false, className }: {
  request: ShareRequest
  /** What the share sheet calls it. */
  title: string
  label?: string
  /** Among a card's icon actions: the mark alone, named for a screen reader; a failure is a toast. */
  icon?: boolean
  className?: string
}) {
  const create = useCreateShare()
  const [said, setSaid] = useState<'copied' | null>(null)
  const [manual, setManual] = useState<string | null>(null)

  useEffect(() => {
    if (!said) return
    const t = setTimeout(() => setSaid(null), 2500)
    return () => clearTimeout(t)
  }, [said])

  const share = async () => {
    setManual(null)
    try {
      const link = await create.mutateAsync(request)
      const outcome = await shareLink(link.url, title)
      if (outcome === 'copied') {
        setSaid('copied')
        announce('Link copied')
      } else if (outcome === 'failed') {
        if (icon) toast.failed(`Copy the link: ${link.url}`)
        else setManual(link.url)
      }
    } catch (err) {
      // The button says why below; the icon has no room to.
      if (icon) toast.failed((err as Error).message)
    }
  }

  if (icon) {
    return (
      <Tip label={said ? 'Link copied' : `${label} ${title}`}>
        <button type="button" aria-label={`${label} ${title}`} disabled={create.isPending} onClick={share}
          className={cn('flex size-7 items-center justify-center rounded-md text-muted-foreground/70 hover:bg-muted/40 '
            + 'hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40', className)}>
          {said ? <Check className="size-3.5 text-done" aria-hidden /> : <Share2 className="size-3.5" aria-hidden />}
        </button>
      </Tip>
    )
  }

  return (
    <span className={cn('inline-flex flex-col items-start gap-1', className)}>
      <Button type="button" variant="outline" size="sm" className="h-8 gap-1.5 text-xs" loading={create.isPending} onClick={share}>
        {said ? <Check className="size-3.5 text-done" aria-hidden /> : <Share2 className="size-3.5" aria-hidden />}
        {said ? 'Link copied' : label}
      </Button>
      {create.isError && <span role="alert" className="text-[11px] text-bad">{create.error.message}</span>}
      {manual && (
        <span className="text-[11px] text-muted-foreground">
          Copy the link: <span className="select-all break-all font-mono text-foreground">{manual}</span>
        </span>
      )}
    </span>
  )
}
