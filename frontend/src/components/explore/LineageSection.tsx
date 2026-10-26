import { useState } from 'react'
import { Section } from '@/components/explore/ExploreSection'
import { TOPIC_ICONS, useExploreNavigate } from '@/components/explore/topics'
import { cn } from '@/lib/utils'
import type { Lineage, LineageGroup, LineageItem } from '@/lib/exploreLinks'

const COLLAPSED = 12

/** An entity as a pill: a button into its detail, or plain text for what has
 *  none (a concept, a slot filter). */
export function LineagePill({ item }: { item: LineageItem }) {
  const open = useExploreNavigate()
  const Icon = item.topic ? TOPIC_ICONS[item.topic] : null
  const body = (
    <>
      {Icon && <Icon className="size-3 shrink-0 opacity-60" />}
      <span className="truncate">{item.name}</span>
      {item.note && <span className="text-muted-foreground/60 font-mono text-[9px] truncate">{item.note}</span>}
    </>
  )
  const base = 'inline-flex max-w-full items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px]'
  // The level's colour as a left border, the landings' colour-coded border (§13.6).
  const style = item.color ? { borderLeftColor: item.color, borderLeftWidth: 2 } : undefined
  if (!item.topic) {
    return <span className={cn(base, 'border-dashed border-border/60 text-muted-foreground')} style={style}>{body}</span>
  }
  const topic = item.topic
  return (
    <button
      type="button"
      onClick={() => open(topic, item.id)}
      className={cn(base, 'border-border bg-muted text-muted-foreground hover:border-primary/50 hover:text-foreground transition-colors')}
      style={style}
    >
      {body}
    </button>
  )
}

function Group({ group }: { group: LineageGroup }) {
  const [all, setAll] = useState(false)
  const shown = all ? group.items : group.items.slice(0, COLLAPSED)
  return (
    <div className="space-y-1">
      <p className="text-[10px] text-muted-foreground/70">
        {group.label} <span className="font-mono text-muted-foreground/40">{group.items.length}</span>
      </p>
      <div className="flex flex-wrap gap-1">
        {shown.map((item) => <LineagePill key={`${item.topic ?? ''}:${item.id}`} item={item} />)}
        {group.items.length > COLLAPSED && (
          <button type="button" onClick={() => setAll(!all)}
            className="px-2 py-0.5 text-[10px] text-muted-foreground/60 hover:text-foreground transition-colors">
            {all ? 'Show fewer' : `Show all ${group.items.length}`}
          </button>
        )}
      </div>
    </div>
  )
}

function Side({ label, groups, empty }: { label: string; groups: LineageGroup[]; empty: string }) {
  return (
    <Section label={label}>
      {groups.length > 0
        ? <div className="space-y-2.5">{groups.map((g) => <Group key={g.label} group={g} />)}</div>
        : <p className="text-[10px] text-muted-foreground/60">{empty}</p>}
    </Section>
  )
}

/** What leads into an entity and what follows from it (lib/exploreLinks.ts),
 *  side by side, stacking at phone width. */
export function LineageSection({ lineage, emptyUp, emptyDown }: {
  lineage: Lineage | null
  emptyUp: string
  emptyDown: string
}) {
  if (!lineage) {
    return <div className="h-16 rounded-md bg-muted/20 animate-pulse" />
  }
  return (
    <div className="grid gap-4 md:grid-cols-2 items-start rounded-lg border border-border/40 bg-card/30 p-3">
      <Side label="Leads into it" groups={lineage.up} empty={emptyUp} />
      <Side label="Follows from it" groups={lineage.down} empty={emptyDown} />
    </div>
  )
}
