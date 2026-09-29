import { useState } from 'react'
import { ChevronDown, ChevronRight, Star } from 'lucide-react'
import type { ModalityId, ProgressSpecEntry, PrimitiveVocabulary } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { entrySentence, expectedText, stallText } from '@/lib/analyticsSpecText'
import { cn } from '@/lib/utils'

function Chip({ children, hex }: { children: React.ReactNode; hex?: string }) {
  return (
    <span
      className="text-[10px] px-1.5 py-0.5 rounded font-mono border"
      style={hex
        ? { color: hex, backgroundColor: `${hex}15`, borderColor: `${hex}30` }
        : { borderColor: 'hsl(var(--border))' }}
    >
      {children}
    </span>
  )
}

/**
 * One progress signal from a philosophy's spec: label, primitive, and the
 * sentence that says what it measures against what. Expands to the exact
 * scope, expectation, stall rule, standards and notes.
 */
export function ProgressSpecRow({ entry, vocab, accentHex, defaultOpen = false }: {
  entry: ProgressSpecEntry; vocab: PrimitiveVocabulary | undefined; accentHex: string; defaultOpen?: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)
  const { scope } = entry
  const hasScope = scope.modalities.length || scope.archetypes.length || scope.frameworks.length
    || scope.exercises.length || scope.movementPatterns.length || scope.slotTypes.length
    || scope.slotRoles.length || scope.excludeSlotRoles.length

  return (
    <div className={cn('rounded-md border bg-card/30', entry.headline ? 'border-border/60' : 'border-border/30')}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="w-full flex items-start gap-2 px-3 py-2 text-left hover:bg-muted/10 transition-colors"
      >
        {open
          ? <ChevronDown className="size-3.5 mt-0.5 shrink-0 text-muted-foreground/60" />
          : <ChevronRight className="size-3.5 mt-0.5 shrink-0 text-muted-foreground/60" />}
        <div className="flex-1 min-w-0 space-y-0.5">
          <div className="flex items-center gap-1.5 flex-wrap">
            {entry.headline && <Star className="size-3 shrink-0" style={{ color: accentHex }} fill={accentHex} aria-label="headline signal" />}
            <span className="text-[11px] font-medium text-foreground">{entry.label}</span>
            <Chip hex={accentHex}>{vocab?.label ?? entry.primitive.replace(/_/g, ' ')}</Chip>
            {entry.source === 'default' && <span className="text-[9px] text-muted-foreground/60 font-mono">default</span>}
          </div>
          <p className="text-[10px] text-muted-foreground leading-relaxed">{entrySentence(entry, vocab)}</p>
        </div>
      </button>

      {open && (
        <div className="px-3 pb-3 pl-8 space-y-2 border-t border-border/30 pt-2 text-[10px]">
          {hasScope ? (
            <div className="space-y-1">
              <p className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px]">Scope</p>
              <div className="flex flex-wrap gap-1">
                {scope.modalities.map((m) => <Chip key={m.id} hex={MODALITY_COLORS[m.id as ModalityId]?.hex}>{MODALITY_COLORS[m.id as ModalityId]?.label ?? m.name}</Chip>)}
                {scope.frameworks.map((f) => <Chip key={f.id}>during {f.name}</Chip>)}
                {scope.archetypes.map((a) => <Chip key={a.id}>{a.name}</Chip>)}
                {scope.exercises.map((e) => <Chip key={e.id}>{e.name}</Chip>)}
                {scope.movementPatterns.map((p) => <Chip key={p}>{p.replace(/_/g, ' ')}</Chip>)}
                {scope.slotTypes.map((t) => <Chip key={t}>{t.replace(/_/g, ' ')} slots</Chip>)}
                {scope.slotRoles.map((r) => <Chip key={r}>role {r}</Chip>)}
                {scope.excludeSlotRoles.map((r) => <Chip key={r}>not role {r}</Chip>)}
              </div>
            </div>
          ) : (
            <p className="text-muted-foreground/60">Every session in the program.</p>
          )}
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-muted-foreground">
            <dt className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px] pt-px">Measures</dt>
            <dd>{vocab?.measures ?? entry.primitive}{vocab?.unit ? ` (${vocab.unit})` : ''}</dd>
            {(entry.expected.kind !== 'none' || entry.rpmTarget != null || entry.targetLevel) && (<>
              <dt className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px] pt-px">Expected</dt>
              <dd>{expectedText(entry.expected, entry)}</dd>
            </>)}
            {entry.stall && (<>
              <dt className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px] pt-px">Stall</dt>
              <dd>{stallText(entry.stall)} (within {entry.stall.tolerancePct}%)</dd>
            </>)}
            {entry.benchmarks.length > 0 && (<>
              <dt className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px] pt-px">Standards</dt>
              <dd>{entry.benchmarks.map((b) => b.name).join(' · ')}</dd>
            </>)}
            <dt className="uppercase tracking-wider text-muted-foreground/50 font-medium text-[9px] pt-px">Counts after</dt>
            <dd>{entry.minSessions} session{entry.minSessions === 1 ? '' : 's'}</dd>
          </dl>
          {entry.notes && <p className="italic text-muted-foreground/70 leading-relaxed">{entry.notes}</p>}
        </div>
      )}
    </div>
  )
}
