/** The two smallest Explore-detail primitives: a labelled block and a stat tile. */
export function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">{label}</p>
      {children}
    </div>
  )
}

export function StatCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
      <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
      <p className="text-[11px] font-medium text-foreground">{value}</p>
    </div>
  )
}
