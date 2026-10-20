# Horsemen GPP — source dossier

Status: **audited** (2026-10-20) for the 4-Month Macro, which runs as written;
the GPP Circuits track is an invention awaiting the owner's decision and is
excluded from the status (status.yaml `excluded_tracks`). The 25 catalog
exercises from before the rebuild that no workout names were removed the same
day. Engine shape: week
templates and category pools (philosophy.yaml `week_templates`,
frameworks/concurrent_training.yaml `categories`, src/week_template.py).

## Sources

- `data/horsemen/horsemen.pdf` / `horsemen.docx` (Horsemen Training Program,
  2008) — read in full; `docs/extracted/horsemen.md` summarises it.

## Rules → where they live

| Rule (source) | Encoded as |
|---|---|
| Four 28-day months — strength, power endurance, job specific, maintenance — each with an example week sequence, run two or three times | Four phases, each with its four `week_templates`, day by day |
| Six training days and a rest day; recovery days at ≤65 % max HR | the templates; recovery archetypes at zone 1 |
| Each day is a category; the workout is picked from that category's named list | `categories` → pools of ~190 `pool_only` archetypes, rotated, no repeat within a week |
| Every day opens with a warm-up from its list | `warm_up_category` |
| Loads: a 1RM worked up to on the day, percentages of it, fixed weights, multiples of bodyweight; no RPE, no deload | `progression_model: as_written`; each slot's `load` text; `work_up_1rm` slots |
| Substitutes the source declares (no rope → 10 pull-ups, no sled → jingle jangles, KB ↔ DB) | `exercise_filter.ordered`: the written movement first |
| "Light, work on form" days | template `{categories, light: true}` |
| Goals within four months (DL 2.5×, FS 1.5×, bench 1.5×, press 1×, 3 mi < 20:00, SSST 200) | analytics `benchmarks`; strength measured on the day's worked-up max |

Decided by the owner (2026-10-19): every workout is kept, each listing its
equipment and passed over when the athlete lacks it (API, partner and facility
workouts included); names with profanity or a slur are cleaned; the PT test is
placed where it fits the method.

## Open

- Workouts the source leaves undefined ("400 m Rob Shauls"); movements it names
  without defining (cauldron, corkscrew, arm haulers …) are read as noted in the catalog.
- No equipment id for elliptical, stair master, climbing, paddling or skiing.
- The PT test's 800 m swim, and the goals no session tests (SSST, the 5-mile run,
  bodyweight bench reps, pull-ups with 25 lb), are entered by hand (`manual: true`
  in analytics.yaml).

## Inventions (see status.yaml)

- The GPP Circuits track and its archetypes (all 26 fidelity findings).
- The PT test's placement: the macro's first and last hard job-specific days.

## Tests

test_week_template.py — `test_horsemen_runs_the_source_weeks_as_written`,
`test_horsemen_without_the_equipment_passes_workouts_over`,
`test_a_regenerate_from_mid_track_carries_on_the_rotation`, the route tests.
