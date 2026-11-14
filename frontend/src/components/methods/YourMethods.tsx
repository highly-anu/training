import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Pencil, Sparkles, Trash2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { ConfirmDialog } from '@/components/shared/ConfirmDialog'
import { Tip } from '@/components/shared/Tip'
import { isOpen, useDeleteMethod, useMethods, type Method } from '@/api/methods'
import { buildHeadline, deleteRefusal, unavailableReason } from '@/lib/methodBuild'
import { toast } from '@/lib/toast'
import { announce } from '@/lib/announce'
import { cn } from '@/lib/utils'
import type { Philosophy } from '@/api/types'

const CARD = 'rounded-lg border px-3 py-2.5 text-left transition-all'
const IDLE = 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20'
const ICON_BUTTON = 'flex size-7 items-center justify-center rounded-md text-muted-foreground/70 '
  + 'hover:bg-muted/40 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring '
  + 'disabled:opacity-40 disabled:hover:bg-transparent'

/**
 * The athlete's own methods in the program builder's first step, with the way
 * to describe another (docs/roadmap.md 21.4). A method is a philosophy like
 * the shipped ones — picking one selects it — with two things only its owner
 * can do: revise it and delete it. Renders nothing for an account the builder
 * is not on for.
 */
export function YourMethods({ philosophies, selectedId, onSelect, onDeleted }: {
  philosophies: Philosophy[]
  selectedId: string | null
  onSelect: (phil: Philosophy) => void
  /** The method that was just deleted (the step lets go of it if it was picked). */
  onDeleted: (id: string) => void
}) {
  const { data } = useMethods()
  const remove = useDeleteMethod()
  const [deleting, setDeleting] = useState<Method | null>(null)

  if (!data || data.reason === 'not_enabled') return null
  const open = data.builds.find(isOpen)
  const unavailable = unavailableReason(data)
  // Nothing of theirs and no way to make one: no group at all.
  if (data.methods.length === 0 && !open && !data.available) return null

  function confirmDelete(method: Method) {
    remove.mutate(method.id, {
      onSuccess: () => { onDeleted(method.id); announce(`${method.name} deleted.`) },
      onError: (e) => toast.failed(deleteRefusal(e)),
    })
  }

  return (
    <div className="space-y-2">
      <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">Your methods</p>
      <div className="grid grid-cols-2 gap-2">
        {data.methods.map((method) => {
          const phil = philosophies.find((p) => p.id === method.id)
          const selected = selectedId === method.id
          return (
            <div
              key={method.id}
              className={cn(CARD, 'flex items-start gap-1 p-0', selected ? 'border-2 border-primary bg-primary/5 shadow-md' : IDLE)}
            >
              <button
                type="button"
                disabled={!phil}
                aria-pressed={selected}
                onClick={() => phil && onSelect(phil)}
                className="group min-w-0 flex-1 cursor-pointer rounded-lg px-3 py-2.5 text-left disabled:cursor-not-allowed disabled:opacity-50"
              >
                <span className="flex items-center gap-1.5">
                  <span className={cn('truncate text-xs font-medium leading-snug', !selected && 'group-hover:text-primary')}>
                    {method.name}
                  </span>
                  <Badge variant="outline" className="shrink-0 px-1.5 py-0 text-[9px]">Yours</Badge>
                </span>
                <span className="mt-0.5 block text-[10px] text-muted-foreground/60">
                  {phil
                    ? `Revision ${method.revision}${method.inUse ? ' · your program runs on it' : ''}`
                    : 'Set aside: it no longer passes the checks. Revise it to use it again.'}
                </span>
              </button>
              <div className="flex shrink-0 items-center gap-0.5 py-1.5 pr-1.5">
                <Tip label="Revise">
                  <Link
                    to={`/program/new/method?revise=${encodeURIComponent(method.id)}`}
                    aria-label={`Revise ${method.name}`}
                    className={ICON_BUTTON}
                  >
                    <Pencil className="size-3.5" />
                  </Link>
                </Tip>
                <Tip label={method.inUse ? 'Your program runs on it' : 'Delete'}>
                  <button
                    type="button"
                    aria-label={`Delete ${method.name}`}
                    aria-disabled={method.inUse}
                    onClick={() => { if (!method.inUse) setDeleting(method) }}
                    className={cn(ICON_BUTTON, method.inUse && 'opacity-40 hover:bg-transparent hover:text-muted-foreground/70')}
                  >
                    <Trash2 className="size-3.5" />
                  </button>
                </Tip>
              </div>
            </div>
          )
        })}

        {open ? (
          <Link
            to={`/program/new/method/${encodeURIComponent(open.id)}`}
            className={cn(CARD, IDLE, 'flex items-start gap-2.5')}
          >
            <Spinner className="mt-0.5 size-3.5" />
            <span className="min-w-0">
              <span className="block truncate text-xs font-medium leading-snug">{buildHeadline(open)}</span>
              <span className="mt-0.5 block truncate text-[10px] text-muted-foreground/60">
                {open.description || 'Your method is being built'}
              </span>
            </span>
          </Link>
        ) : unavailable ? (
          <div className={cn(CARD, 'border-border/30 bg-card/20 text-muted-foreground/60')}>
            <p className="text-xs font-medium leading-snug">Describe your own method</p>
            <p className="mt-0.5 text-[10px]">{unavailable}</p>
          </div>
        ) : (
          <Link to="/program/new/method" className={cn(CARD, IDLE, 'group flex items-start gap-2.5')}>
            <Sparkles className="mt-0.5 size-3.5 shrink-0 text-muted-foreground group-hover:text-primary" />
            <span className="min-w-0">
              <span className="block text-xs font-medium leading-snug group-hover:text-primary">Describe your own method</span>
              <span className="mt-0.5 block text-[10px] text-muted-foreground/60">
                Say how you want to train and have it written for you
              </span>
            </span>
          </Link>
        )}
      </div>

      <ConfirmDialog
        open={deleting !== null}
        onOpenChange={(v) => { if (!v) setDeleting(null) }}
        title={`Delete ${deleting?.name ?? 'this method'}?`}
        description="The method and its revisions are removed. Programs you already built from it keep their sessions."
        confirmLabel="Delete"
        destructive
        onConfirm={() => { if (deleting) confirmDelete(deleting) }}
      />
    </div>
  )
}
