# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A training logic system that algorithmically generates periodized training programs from goals, constraints, and weighted priorities. Sources: Starting Strength, Uphill Athlete, CrossFit Endurance, Wildman Kettlebell, Ido Portal, Horsemen GPP, Gym Jones, Marcus Filly, ATG.

## Current State

**Fully functional end-to-end.** Python backend generates programs; Flask API serves them; React frontend connects to the API.

- To run: `python api.py` (port 8000) + `cd frontend && npm run dev` (port 5173)
- Frontend uses real API when `frontend/.env.local` contains `VITE_API_BASE_URL=http://localhost:8000/api`; falls back to MSW mock data otherwise

## Repository Structure

```
training/
├── api.py                    # Flask REST API (port 8000)
├── main.py                   # CLI entry point
├── requirements.txt          # pyyaml, flask, flask-cors
├── src/
│   ├── generator.py          # Orchestrates full program generation
│   ├── scheduler.py          # Assigns modalities to days (recovery-aware)
│   ├── selector.py           # Selects archetypes and exercises per slot
│   ├── progression.py        # Calculates loads (linear, RPE, time-domain)
│   ├── validator.py          # Pre-flight feasibility checks
│   ├── loader.py             # YAML data loading + caching
│   ├── output.py             # Markdown formatter
│   └── summary.py            # Volume summary computation
├── data/
│   ├── goals/                # 7 goal profiles (YAML): general_gpp, alpine_climbing,
│   │                         #   sof_operator, bjj_competitor, ultra_endurance,
│   │                         #   max_strength_focus, injury_rehab
│   ├── archetypes/           # ~25 workout archetypes across 5 categories
│   │   ├── strength/         # 5x5, 3x5_linear, hlm, emom_strength, gym_jones_operator
│   │   ├── conditioning/     # long_zone_2, threshold_intervals, mixed_modal_amrap,
│   │   │                     #   tabata, gym_jones_circuit, gym_jones_accumulation, etc.
│   │   ├── kettlebell/       # kb_double_strength, kb_ballistic, tgu_practice, etc.
│   │   ├── gpp_durability/   # ruck_session, loaded_carry_circuit, bodyweight_circuit,
│   │   │                     #   sandbag_complex, horsemen_power_endurance
│   │   └── movement_skill/   # skill_ladder, movement_flow, joint_prep_circuit
│   ├── exercises/            # ~198 exercises across 9 files (barbell, bodyweight,
│   │                         #   kettlebell, aerobic, carries, mobility, skill,
│   │                         #   rehab, gym_jones, sandbag)
│   ├── modalities/           # 12 modality definitions
│   ├── frameworks/           # 8 frameworks (linear_progression, polarized_80_20,
│   │                         #   concurrent_training, gpp_circuits, etc.)
│   ├── philosophies/         # Source philosophy YAMLs (reference only)
│   ├── constraints/
│   │   ├── injury_flags.yaml # 12 injury flags with excluded patterns + substitutions
│   │   └── equipment_profiles.yaml
│   └── benchmarks/           # Strength + conditioning + cell standards
├── docs/plan.md              # Original design document (ontology reference)
└── frontend/                 # React app (see below)
```

## API Endpoints (api.py)

All prefixed `/api/`:

| Method | Path | Returns |
|--------|------|---------|
| GET | `/goals` | `GoalProfile[]` |
| GET | `/goals/<id>` | `GoalProfile` |
| GET | `/exercises` | `Exercise[]` (198 total) |
| GET | `/modalities` | `Modality[]` |
| GET | `/constraints/equipment-profiles` | `EquipmentProfile[]` |
| GET | `/constraints/injury-flags` | `InjuryFlag[]` |
| POST | `/programs/generate` | `GeneratedProgram` |

`POST /programs/generate` body: `{ goal_id: string, constraints: AthleteConstraints, num_weeks?: number }`

## Frontend (frontend/)

React 19 + Vite 8 + TypeScript, Tailwind CSS v4, shadcn/ui, Framer Motion, TanStack Query, Zustand, Recharts, MSW v2, React Router v7.

**Pages:** Dashboard, ProgramBuilder (3-step wizard), ProgramView (week calendar), SessionDetail, ExerciseCatalog, ProfileBenchmarks

**State:** `builderStore` (wizard state + constraints form), `profileStore` (persisted: level, equipment, injuries, perf logs), `uiStore` (sidebar, filters)

**API hooks:** `src/api/` — goals.ts, exercises.ts, programs.ts, constraints.ts, modalities.ts, benchmarks.ts

## System Architecture

```
Philosophy → Methodology → Modalities → Archetypes → Exercises → Progression → Constraints → Goal → Program
```

1. **Goal profile** — weighted priority vector (e.g. `{ aerobic_base: 0.6, max_strength: 0.2 }`) + phase sequence
2. **Scheduler** — maps goal priorities + framework → session slots per day (recovery-aware)
3. **Selector** — picks best archetype per slot; fills archetype slots with exercises (injury/equipment/level filtered)
4. **Progression** — calculates load prescription per slot type (linear_load, rpe_autoregulation, time_to_task, distance, density)
5. **Validator** — pre-flight checks on equipment, days, session time, injury conflicts, phase validity
6. **API** — transforms integer day keys → day names; wraps in `{ goal, constraints, validation, weeks, volume_summary }`

## Key Engine Behaviors

- **Injury flags**: excluded_movement_patterns blocks exercises by movement pattern; contraindicated_with blocks specific exercises. Slots whose required pattern is fully excluded show as `injury_skip` (not an error).
- **Session time cap**: `_time_to_task` progression is capped at `session_time_minutes` — Zone 2 duration never exceeds the athlete's session limit even in build phase.
- **Archetype fallback**: sessions whose modality has no valid archetype for the phase fall back to `aerobic_base`.
- **Exercise scoring**: prefers exercises with defined movement_patterns (+0.5) and forward-unlocking exercises (+0.5); penalizes recently used (-2 per recent use). AMRAP/for_time slots exclude `mobility` and `rehab` category exercises.
- **Deload**: auto-triggered every N weeks (per framework) or when `fatigue_state: overreached`.

## Known Gaps / Next Work

No open gaps. All planned features are implemented.
