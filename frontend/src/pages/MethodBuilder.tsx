import { useParams, useSearchParams, Link } from 'react-router-dom'
import { ChevronLeft, Sparkles } from 'lucide-react'
import { Page } from '@/components/layout/Page'
import { PageHeader } from '@/components/layout/PageHeader'
import { DescribeMethod } from '@/components/methods/DescribeMethod'
import { MethodBuildProgress } from '@/components/methods/MethodBuildProgress'
import { useScrollRestore } from '@/lib/useScrollRestore'

/**
 * A method of the athlete's own, described in words and written for them
 * (docs/roadmap.md 21.4): `/program/new/method` is the description (or, with
 * `?revise=<id>`, the change to one of theirs), `/program/new/method/:buildId`
 * the build and what came of it. Part of the program builder's flow, reached
 * from its first step.
 */
export function MethodBuilder() {
  const scroller = useScrollRestore()
  const { buildId } = useParams()
  const [params] = useSearchParams()
  const revises = params.get('revise')
  return (
    <Page key="method-builder" className="flex h-full flex-col">
      <PageHeader
        icon={Sparkles}
        title={buildId ? 'Your method' : revises ? 'Revise your method' : 'Describe your own method'}
        subtitle="A training method written for you, to build programs from"
      />
      <div ref={scroller} className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-2xl space-y-6 px-8 py-8">
          <Link to="/program/new" className="flex items-center gap-1 text-[11px] text-muted-foreground/70 hover:text-foreground">
            <ChevronLeft className="size-3" /> Program builder
          </Link>
          {buildId
            // Keyed: another build is another screen, with its own "seen finished".
            ? <MethodBuildProgress key={buildId} buildId={buildId} />
            : <DescribeMethod key={revises ?? 'new'} revises={revises} />}
        </div>
      </div>
    </Page>
  )
}
