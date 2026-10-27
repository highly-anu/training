import { useState } from 'react'
import { ChevronDown, ChevronRight, Quote } from 'lucide-react'
import type { PhilosophyDescription } from '@/api/types'

const SHOWN = 6

function Rule({ rule }: { rule: PhilosophyDescription['rules'][number] }) {
  const [open, setOpen] = useState(false)
  return (
    <li className="rounded-md border border-border/40 bg-card/40">
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        className="flex w-full items-start gap-2 px-3 py-2 text-left hover:bg-muted/20">
        <span className="font-mono text-[9px] text-muted-foreground/60 pt-0.5 w-6 shrink-0">{rule.id}</span>
        <span className="flex-1 text-[11px] leading-relaxed text-foreground/90">{rule.text}</span>
        {rule.cites.length > 0 && (open
          ? <ChevronDown className="size-3 mt-0.5 shrink-0 text-muted-foreground/60" />
          : <Quote className="size-3 mt-0.5 shrink-0 text-muted-foreground/40" />)}
      </button>
      {open && rule.cites.length > 0 && (
        <ul className="space-y-1 border-t border-border/30 px-3 py-2 pl-11">
          {rule.cites.map((c, i) => (
            <li key={i} className="text-[10px] leading-relaxed text-muted-foreground">
              {c.quote && <span className="italic">{c.quote}</span>}
              <span className="text-muted-foreground/60"> — {c.source}</span>
            </li>
          ))}
        </ul>
      )}
    </li>
  )
}

function Disclosure({ label, children }: { label: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false)
  return (
    <div>
      <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground">
        {open ? <ChevronDown className="size-3" /> : <ChevronRight className="size-3" />}
        {label}
      </button>
      {open && <div className="mt-1.5 pl-4">{children}</div>}
    </div>
  )
}

/**
 * What the method holds true, in its own words: the rules of the package's
 * fidelity record, each with the passage it rests on; then, said as plainly,
 * where the app had to decide (inventions) and what it does not model yet.
 * A package without a record shows its core principles.
 */
export function PhilosophyRules({ doc }: { doc: PhilosophyDescription }) {
  const [all, setAll] = useState(false)
  if (!doc.rules.length) {
    if (!doc.principles.length) return null
    return (
      <ul className="space-y-0.5">
        {doc.principles.map((p) => <li key={p} className="text-[11px] text-muted-foreground">· {p}</li>)}
      </ul>
    )
  }
  const rules = all ? doc.rules : doc.rules.slice(0, SHOWN)
  return (
    <div className="space-y-3">
      <ul className="space-y-1.5">
        {rules.map((r) => <Rule key={r.id} rule={r} />)}
      </ul>
      {doc.rules.length > SHOWN && (
        <button type="button" onClick={() => setAll((a) => !a)}
          className="text-[11px] text-muted-foreground hover:text-foreground">
          {all ? 'Show fewer' : `Show all ${doc.rules.length} rules`}
        </button>
      )}
      <div className="space-y-1.5">
        {doc.inventions.length > 0 && (
          <Disclosure label={`Where the app decides (${doc.inventions.length})`}>
            <ul className="space-y-1">
              {doc.inventions.map((i) => (
                <li key={i.id} className="text-[10px] leading-relaxed text-muted-foreground">
                  <span className="font-mono text-muted-foreground/60">{i.id}</span> {i.text}
                </li>
              ))}
            </ul>
          </Disclosure>
        )}
        {doc.open.length > 0 && (
          <Disclosure label={`Not modelled yet (${doc.open.length})`}>
            <ul className="space-y-1">
              {doc.open.map((o) => <li key={o} className="text-[10px] leading-relaxed text-muted-foreground">· {o}</li>)}
            </ul>
          </Disclosure>
        )}
      </div>
    </div>
  )
}
