import * as React from "react"

import { cn } from "@/lib/utils"

/** Long text: the input's look, as many rows as asked for. */
const Textarea = React.forwardRef<HTMLTextAreaElement, React.ComponentProps<"textarea">>(
  ({ className, rows = 4, ...props }, ref) => {
    return (
      <textarea
        rows={rows}
        className={cn(
          "flex w-full rounded-md border border-input bg-background px-3 py-2 text-base leading-relaxed ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 md:text-sm",
          className
        )}
        ref={ref}
        {...props}
      />
    )
  }
)
Textarea.displayName = "Textarea"

export { Textarea }
