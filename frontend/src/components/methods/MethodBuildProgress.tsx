import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { Check, ChevronDown } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Collapse } from '@/components/motion/Collapse'
import { ConfirmDialog } from '@/components/shared/ConfirmDialog'
import { FailedState } from '@/components/shared/states/FailedState'
import { LoadingState } from '@/components/shared/states/LoadingState'
import { isOpen, refreshAfterMethodChange, useCancelBuild, useMethodBuild, type MethodBuild } from '@/api/methods'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useBuilderStore } from '@/store/builderStore'
import { useMethodDraft } from '@/store/methodDraftStore'
import { announce } from '@/lib/announce'
import { BUILD_STEPS, buildHeadline, stepIndex } from '@/lib/methodBuild'
import { cn } from '@/lib/utils'

/**
 * One build: what it is doing while it runs (asked again every two seconds),
 * then the method with the ways on — build a program, read it, revise it — or
 * why it was not built. Leaving the page does not stop it.
 */
export function MethodBuildProgress({ buildId }: { buildId: string }) {
  const { data: build, isLoading, error, refetch } = useMethodBuild(buildId)
  const client = useQueryClient()
  const settled = useRef<string | null>(null)
  const clearDraft = useMethodDraft((s) => s.clear)

  // The first time this build is seen finished: everything that lists
  // packages is read again, and the outcome is said aloud.
  useEffect(() => {
    if (!build || isOpen(build) || settled.current === build.id) return
    settled.current = build.id
    if (build.status === 'done') {
      clearDraft()
      void refreshAfterMethodChange(client)
      announce(`${build.result?.name ?? 'Your method'} is built.`)
    } else if (build.status === 'failed') {
      announce(build.error?.message ?? 'The method could not be built.')
    }
  }, [build, client, clearDraft])

  if (isLoading) return <LoadingState shape="lines" label="Loading the build" />
  if (error || !build) {
    return <FailedState title="Could not load this build" error={error ?? new Error('Not found')} onRetry={() => { void refetch() }} />
  }
  if (isOpen(build)) return <Running build={build} />
  if (build.status === 'done' && build.result) return <Built build={build} />
  return <NotBuilt build={build} />
}

function Running({ build }: { build: MethodBuild }) {
  const cancel = useCancelBuild()
  const [asking, setAsking] = useState(false)
  const at = stepIndex(build)
  return (
    <div className="space-y-6">
      <div role="status" className="flex items-start gap-3">
        <Spinner className="mt-0.5 size-4" />
        <div className="space-y-0.5">
          <p className="text-sm font-semibold">{buildHeadline(build)}</p>
          {build.progress.detail && <p className="text-xs text-muted-foreground">{build.progress.detail}</p>}
        </div>
      </div>

      <ol className="space-y-2">
        {BUILD_STEPS.map((step, i) => (
          <li key={step.stage} className={cn('flex items-center gap-2.5 text-xs', i > at && 'text-muted-foreground/50')}>
            <span
              aria-hidden
              className={cn(
                'flex size-4 shrink-0 items-center justify-center rounded-full border',
                i < at && 'border-done bg-done/15 text-done',
                i === at && 'border-primary',
                i > at && 'border-border',
              )}
            >
              {i < at && <Check className="size-3" />}
            </span>
            <span className={cn(i === at && 'font-medium text-foreground')}>{step.label}</span>
            <span className="sr-only">{i < at ? '(done)' : i === at ? '(now)' : '(to come)'}</span>
          </li>
        ))}
      </ol>

      <p className="text-[11px] text-muted-foreground leading-relaxed">
        This takes a few minutes. You can leave this page: the build carries on, and the method appears under
        Your methods in the program builder when it is ready.
      </p>
      {build.description && (
        <blockquote className="rounded-lg border border-border/50 bg-card/30 px-3 py-2 text-xs text-muted-foreground">
          {build.description}
        </blockquote>
      )}

      <div className="flex justify-end">
        <Button variant="outline" size="sm" loading={cancel.isPending} onClick={() => setAsking(true)}>Stop building</Button>
      </div>
      <ConfirmDialog
        open={asking}
        onOpenChange={setAsking}
        title="Stop building this method?"
        description="What has been written so far is discarded, and the build still counts toward today's."
        confirmLabel="Stop building"
        cancelLabel="Keep building"
        destructive
        onConfirm={() => cancel.mutate(build.id)}
      />
    </div>
  )
}

function Built({ build }: { build: MethodBuild }) {
  const navigate = useNavigate()
  const result = build.result!
  const { data: philosophies = [] } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const prefill = useBuilderStore((s) => s.prefillFromPhilosophy)
  const phil = philosophies.find((p) => p.id === result.packageId)
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <p className="flex items-center gap-1.5 text-xs font-medium text-done">
          <Check className="size-3.5" /> {build.revise ? `Revision ${result.revision} is ready` : 'Your method is ready'}
        </p>
        <h2 className="text-xl font-semibold leading-snug">{result.name}</h2>
        {result.summary && <p className="text-sm text-muted-foreground leading-relaxed">{result.summary}</p>}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          // The list is read again once the build is done; until the method is in it there is nothing to build from.
          loading={!phil}
          onClick={() => { if (phil) { prefill(phil, frameworks); navigate('/program/new') } }}
        >
          Build a program
        </Button>
        <Button asChild variant="outline" size="sm">
          <Link to={`/explore?topic=philosophies&id=${encodeURIComponent(result.packageId)}`}>Read the method</Link>
        </Button>
        <Button asChild variant="outline" size="sm">
          <Link to={`/program/new/method?revise=${encodeURIComponent(result.packageId)}`}>Revise</Link>
        </Button>
      </div>
    </div>
  )
}

function NotBuilt({ build }: { build: MethodBuild }) {
  const [open, setOpen] = useState(false)
  const cancelled = build.status === 'cancelled'
  const problems = build.error?.problems ?? []
  const again = build.revise ? `/program/new/method?revise=${encodeURIComponent(build.revise)}` : '/program/new/method'
  return (
    <div className="space-y-5">
      <div role="alert" className="space-y-1">
        <p className="text-sm font-semibold">{cancelled ? 'The build was stopped' : 'The method was not built'}</p>
        {!cancelled && (
          <p className="text-sm text-muted-foreground leading-relaxed">
            {build.error?.message ?? 'Something went wrong while building. Try again.'}
          </p>
        )}
      </div>
      {problems.length > 0 && (
        <div className="space-y-2">
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <ChevronDown className={cn('size-3.5', !open && '-rotate-90')} />
            What the checks still found
          </button>
          <Collapse open={open}>
            <ul className="space-y-1.5 rounded-lg border border-border/50 bg-card/30 p-3">
              {problems.map((p, i) => (
                <li key={i} className="text-[11px] leading-snug text-muted-foreground">
                  {p.file && <span className="font-mono text-foreground/80">{p.file}: </span>}
                  {p.message}
                </li>
              ))}
            </ul>
          </Collapse>
        </div>
      )}
      <div className="flex gap-2">
        <Button asChild size="sm"><Link to={again}>{cancelled ? 'Start again' : 'Try again'}</Link></Button>
        <Button asChild variant="outline" size="sm"><Link to="/program/new">Back to the program builder</Link></Button>
      </div>
    </div>
  )
}
