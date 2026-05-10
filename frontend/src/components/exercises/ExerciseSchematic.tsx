import { cn } from '@/lib/utils'

interface ExerciseSchematicProps {
  category: string
  className?: string
}

// ─── Figures ─────────────────────────────────────────────────────────────────
// All in viewBox "0 0 160 90". Stroke/fill inherited from <svg> root.
// strokeWidth=2.5 for figure, strokeWidth=2 for equipment, strokeWidth=1 for ground.

function Barbell() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* bar + end caps */}
      <line x1="48" y1="27" x2="112" y2="27" strokeWidth={2} />
      <line x1="48" y1="23" x2="48" y2="31" strokeWidth={2} />
      <line x1="112" y1="23" x2="112" y2="31" strokeWidth={2} />
      {/* head */}
      <circle cx="80" cy="16" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      {/* neck to bar, torso angled forward */}
      <line x1="80" y1="22" x2="80" y2="27" strokeWidth={2.5} />
      <line x1="80" y1="27" x2="73" y2="50" strokeWidth={2.5} />
      {/* arms reaching along bar */}
      <line x1="79" y1="34" x2="62" y2="27" strokeWidth={2.5} />
      <line x1="79" y1="34" x2="96" y2="27" strokeWidth={2.5} />
      {/* legs in squat */}
      <polyline points="73,50 57,63 63,78" strokeWidth={2.5} />
      <polyline points="73,50 84,62 81,78" strokeWidth={2.5} />
    </>
  )
}

function Kettlebell() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* head tilted forward (hip hinge) */}
      <circle cx="87" cy="17" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      {/* torso strongly hinged — nearly horizontal */}
      <line x1="83" y1="23" x2="64" y2="42" strokeWidth={2.5} />
      {/* arm reaching toward bell */}
      <line x1="72" y1="35" x2="61" y2="54" strokeWidth={2.5} />
      {/* kettlebell handle (arc) + body */}
      <path d="M53,57 Q61,51 69,57" strokeWidth={2} fill="none" />
      <circle cx="61" cy="64" r="8" strokeWidth={2} fill="currentColor" fillOpacity={0.08} />
      {/* legs — slight knee bend, feet wide */}
      <polyline points="64,42 67,60 70,78" strokeWidth={2.5} />
      <polyline points="64,42 59,60 56,78" strokeWidth={2.5} />
    </>
  )
}

function Bodyweight() {
  return (
    <>
      {/* pull-up bar */}
      <line x1="58" y1="10" x2="102" y2="10" strokeWidth={2.5} />
      <line x1="62" y1="10" x2="62" y2="6" strokeWidth={1} opacity={0.4} />
      <line x1="98" y1="10" x2="98" y2="6" strokeWidth={1} opacity={0.4} />
      {/* arms reaching up to bar */}
      <line x1="71" y1="22" x2="71" y2="10" strokeWidth={2.5} />
      <line x1="89" y1="22" x2="89" y2="10" strokeWidth={2.5} />
      <line x1="71" y1="22" x2="89" y2="22" strokeWidth={2.5} />
      {/* head between arms just below bar */}
      <circle cx="80" cy="17" r="5.5" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      {/* torso + legs hanging */}
      <line x1="80" y1="28" x2="80" y2="50" strokeWidth={2.5} />
      <polyline points="80,50 74,64 76,78" strokeWidth={2.5} />
      <polyline points="80,50 86,64 84,78" strokeWidth={2.5} />
    </>
  )
}

function Aerobic() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* head, slight forward lean */}
      <circle cx="82" cy="12" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      <line x1="81" y1="18" x2="79" y2="40" strokeWidth={2.5} />
      {/* shoulders */}
      <line x1="74" y1="23" x2="88" y2="23" strokeWidth={2.5} />
      {/* left arm forward, right arm back */}
      <line x1="74" y1="23" x2="66" y2="35" strokeWidth={2.5} />
      <line x1="88" y1="23" x2="96" y2="35" strokeWidth={2.5} />
      {/* right leg forward + extended */}
      <polyline points="79,40 93,55 89,72" strokeWidth={2.5} />
      {/* left leg back + kicked up */}
      <polyline points="79,40 67,54 71,38" strokeWidth={2.5} />
    </>
  )
}

function LoadedCarry() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* head + torso upright */}
      <circle cx="80" cy="12" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      <line x1="80" y1="18" x2="80" y2="44" strokeWidth={2.5} />
      {/* shoulders + straight arms hanging */}
      <line x1="70" y1="24" x2="90" y2="24" strokeWidth={2.5} />
      <line x1="70" y1="24" x2="68" y2="54" strokeWidth={2.5} />
      <line x1="90" y1="24" x2="92" y2="54" strokeWidth={2.5} />
      {/* weights */}
      <rect x="63" y="54" width="9" height="14" rx="1.5" strokeWidth={2} fill="currentColor" fillOpacity={0.08} />
      <rect x="88" y="54" width="9" height="14" rx="1.5" strokeWidth={2} fill="currentColor" fillOpacity={0.08} />
      {/* legs */}
      <polyline points="80,44 74,60 76,78" strokeWidth={2.5} />
      <polyline points="80,44 86,60 84,78" strokeWidth={2.5} />
    </>
  )
}

function Mobility() {
  return (
    <>
      <line x1="44" y1="78" x2="100" y2="78" strokeWidth={1} opacity={0.25} />
      {/* low lunge: back knee down, front foot forward, arms raised */}
      <polyline points="57,72 53,78" strokeWidth={2.5} />
      <line x1="57" y1="72" x2="72" y2="54" strokeWidth={2.5} />
      <line x1="72" y1="54" x2="90" y2="54" strokeWidth={2.5} />
      <line x1="90" y1="54" x2="92" y2="78" strokeWidth={2.5} />
      {/* torso upright */}
      <line x1="72" y1="54" x2="71" y2="30" strokeWidth={2.5} />
      {/* shoulders */}
      <line x1="64" y1="34" x2="78" y2="34" strokeWidth={2.5} />
      {/* arms raised */}
      <line x1="64" y1="34" x2="59" y2="16" strokeWidth={2.5} />
      <line x1="78" y1="34" x2="83" y2="16" strokeWidth={2.5} />
      {/* head */}
      <circle cx="71" cy="24" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
    </>
  )
}

function Rehab() {
  return (
    <>
      {/* mat / ground */}
      <line x1="18" y1="72" x2="142" y2="72" strokeWidth={1} opacity={0.25} />
      {/* figure lying horizontal, head on left */}
      <circle cx="28" cy="67" r="5.5" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      <line x1="33" y1="68" x2="90" y2="68" strokeWidth={2.5} />
      {/* bent knee pulled to chest */}
      <polyline points="90,68 94,52 78,48" strokeWidth={2.5} />
      {/* straight leg */}
      <polyline points="90,68 110,68 114,72" strokeWidth={2.5} />
      {/* arm reaching to hold bent knee */}
      <line x1="55" y1="68" x2="80" y2="52" strokeWidth={2.5} />
    </>
  )
}

function Skill() {
  return (
    <>
      {/* box platform */}
      <rect x="54" y="58" width="52" height="20" rx="2" strokeWidth={2} fill="currentColor" fillOpacity={0.07} />
      <line x1="44" y1="78" x2="116" y2="78" strokeWidth={1} opacity={0.25} />
      {/* figure on box, arms raised (landing celebration) */}
      <circle cx="80" cy="24" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      <line x1="80" y1="30" x2="80" y2="50" strokeWidth={2.5} />
      <line x1="72" y1="36" x2="88" y2="36" strokeWidth={2.5} />
      {/* arms raised in V */}
      <line x1="72" y1="36" x2="62" y2="22" strokeWidth={2.5} />
      <line x1="88" y1="36" x2="98" y2="22" strokeWidth={2.5} />
      {/* legs slightly bent on box top */}
      <polyline points="80,50 73,54 75,58" strokeWidth={2.5} />
      <polyline points="80,50 87,54 85,58" strokeWidth={2.5} />
    </>
  )
}

function Sandbag() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* head */}
      <circle cx="80" cy="12" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      {/* sandbag oval at chest */}
      <ellipse cx="80" cy="36" rx="17" ry="11" strokeWidth={2} fill="currentColor" fillOpacity={0.08} />
      {/* torso above and below bag */}
      <line x1="80" y1="18" x2="80" y2="26" strokeWidth={2.5} />
      <line x1="80" y1="46" x2="80" y2="50" strokeWidth={2.5} />
      {/* arms wrapped around sandbag */}
      <path d="M71,24 Q59,34 68,48" strokeWidth={2.5} fill="none" />
      <path d="M89,24 Q101,34 92,48" strokeWidth={2.5} fill="none" />
      {/* legs */}
      <polyline points="80,50 74,62 76,78" strokeWidth={2.5} />
      <polyline points="80,50 86,62 84,78" strokeWidth={2.5} />
    </>
  )
}

function Accessory() {
  return (
    <>
      <line x1="50" y1="78" x2="110" y2="78" strokeWidth={1} opacity={0.25} />
      {/* head + torso */}
      <circle cx="80" cy="12" r="6" strokeWidth={2.5} fill="currentColor" fillOpacity={0.1} />
      <line x1="80" y1="18" x2="80" y2="44" strokeWidth={2.5} />
      {/* shoulders */}
      <line x1="70" y1="24" x2="90" y2="24" strokeWidth={2.5} />
      {/* left arm resting */}
      <line x1="70" y1="24" x2="70" y2="52" strokeWidth={2.5} />
      {/* right arm — bicep curl (upper arm down, forearm curled up) */}
      <line x1="90" y1="24" x2="90" y2="42" strokeWidth={2.5} />
      <line x1="90" y1="42" x2="78" y2="28" strokeWidth={2.5} />
      {/* dumbbell in curled hand */}
      <line x1="74" y1="26" x2="82" y2="26" strokeWidth={2.5} />
      <line x1="74" y1="23" x2="74" y2="29" strokeWidth={2} />
      <line x1="82" y1="23" x2="82" y2="29" strokeWidth={2} />
      {/* legs */}
      <polyline points="80,44 74,60 76,78" strokeWidth={2.5} />
      <polyline points="80,44 86,60 84,78" strokeWidth={2.5} />
    </>
  )
}

// ─── Category map ─────────────────────────────────────────────────────────────

const FIGURES: Record<string, React.FC> = {
  barbell:      Barbell,
  kettlebell:   Kettlebell,
  bodyweight:   Bodyweight,
  aerobic:      Aerobic,
  loaded_carry: LoadedCarry,
  carries:      LoadedCarry,
  mobility:     Mobility,
  rehab:        Rehab,
  skill:        Skill,
  sandbag:      Sandbag,
  accessory:    Accessory,
  gym_jones:    Bodyweight,
}

// ─── Component ───────────────────────────────────────────────────────────────

export function ExerciseSchematic({ category, className }: ExerciseSchematicProps) {
  const Figure = FIGURES[category] ?? Bodyweight
  return (
    <svg
      viewBox="0 0 160 90"
      stroke="currentColor"
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn('h-full w-full', className)}
      aria-hidden="true"
    >
      <Figure />
    </svg>
  )
}
