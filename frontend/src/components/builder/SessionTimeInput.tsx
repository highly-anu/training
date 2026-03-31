import { useState } from 'react'
import { Label } from '@/components/ui/label'
import { Slider } from '@/components/ui/slider'

interface SessionTimeInputProps {
  weekday: number
  weekend: number
  onChange: (weekday: number, weekend: number) => void
}

function fmtTime(m: number): string {
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  const rem = m % 60
  return rem > 0 ? `${h}h ${rem}m` : `${h}h`
}

export function SessionTimeInput({ weekday, weekend, onChange }: SessionTimeInputProps) {
  const isSplit = weekday !== weekend
  const [split, setSplit] = useState(isSplit)

  function toggleSplit() {
    if (split) {
      // Collapsing — use weekday value for both
      onChange(weekday, weekday)
    }
    setSplit((v) => !v)
  }

  if (!split) {
    return (
      <div className="space-y-3">
        <Label className="text-sm font-semibold">
          Session Time — <span className="text-primary font-bold">{fmtTime(weekday)}</span>
        </Label>
        <Slider
          min={15} max={180} step={15}
          value={[weekday]}
          onValueChange={([v]) => onChange(v, v)}
        />
        <div className="flex items-center justify-between text-[10px] text-muted-foreground">
          <span>15 min</span>
          <button
            type="button"
            onClick={toggleSplit}
            className="text-[10px] text-muted-foreground/70 hover:text-primary transition-colors underline-offset-2 hover:underline"
          >
            Different on weekends
          </button>
          <span>3h</span>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label className="text-sm font-semibold">
            Weekdays — <span className="text-primary font-bold">{fmtTime(weekday)}</span>
          </Label>
          <p className="text-[10px] text-muted-foreground">Mon – Fri</p>
          <Slider
            min={15} max={180} step={15}
            value={[weekday]}
            onValueChange={([v]) => onChange(v, weekend)}
          />
          <div className="flex justify-between text-[10px] text-muted-foreground">
            <span>15 min</span><span>3h</span>
          </div>
        </div>
        <div className="space-y-2">
          <Label className="text-sm font-semibold">
            Weekends — <span className="text-primary font-bold">{fmtTime(weekend)}</span>
          </Label>
          <p className="text-[10px] text-muted-foreground">Sat – Sun</p>
          <Slider
            min={15} max={180} step={15}
            value={[weekend]}
            onValueChange={([v]) => onChange(weekday, v)}
          />
          <div className="flex justify-between text-[10px] text-muted-foreground">
            <span>15 min</span><span>3h</span>
          </div>
        </div>
      </div>
      <div className="flex justify-end">
        <button
          type="button"
          onClick={toggleSplit}
          className="text-[10px] text-muted-foreground/70 hover:text-primary transition-colors underline-offset-2 hover:underline"
        >
          Same time every day
        </button>
      </div>
    </div>
  )
}
