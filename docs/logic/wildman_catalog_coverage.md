# Wildman catalog reachability

Coverage is a package-wide reachability requirement, not a target for variety
inside an individual program. General Practice and Pentathlon keep their focused
exercise sets. Every catalog ID must appear in at least one fully generated,
qualified track/level program. Preparation and recovery count as prescribed work;
rest-only blocks do not count as exercises.

## Supported paths

All runs below use the complete default track, four available days, a 90-minute
budget, all catalog equipment, explicitly confirmed required proficiency, and two
matching bells. A qualified fixture is not a recommendation for a novice to enter
an advanced track.

| Track | Novice unique | Intermediate unique | Advanced unique | Elite unique | Weeks |
|---|---:|---:|---:|---:|---:|
| General Practice | 4 | 6 | 6 | 6 | 16 |
| Pentathlon Prep | unsupported | 7 | 7 | 7 | 12 |
| Squat Practice | 3 | 3 | 3 | 3 | 12 |
| Snatch Practice | unsupported | 4 | 4 | 4 | 12 |
| Get-Up and Loaded Mobility | unsupported | 5 | 5 | 5 | 12 |
| Double-Bell Practice | unsupported | 6 | 6 | 6 | 12 |

The union is **20 of 20 catalog IDs**; adding the columns is invalid because many
tracks share preparation movements. No exercise catalog entries were removed to
make the percentage larger.

| Exercise family absent from the original two tracks | New programming path |
|---|---|
| Goblet squat | Squat Practice |
| Single-arm swing and full snatch | Snatch Practice |
| Windmill, rack carry, overhead carry | Get-Up and Loaded Mobility |
| Double clean, press, front squat, jerk | Double-Bell Practice |

## Evidence and adaptation boundaries

- [Official program catalog](https://programs.wildmanathletica.com/kettlebell-programs):
  separate swing, clean/press, get-up and snatch offerings; squat is a foundational
  movement family. Goblet squat practice does **not** reproduce the Deck Squat program.
- [Official snatch description](https://programs.wildmanathletica.com/snatch):
  a separate progressive snatch focus, with different learning and working protocols.
  Our low-repetition EMOM is an app adaptation, not their purchased prescription.
- [Official get-up description](https://programs.wildmanathletica.com/tgu) and
  [Wildman's windmill demonstration](https://www.youtube.com/watch?v=LpFZMjh80nM):
  support the get-up and loaded mobility movement family. The carry selection and
  fixed practice windows are app-authored complementary work.
- [Official double-bell discussion](https://programs.wildmanathletica.com/blog/the-benefits-of-double-kettlebell-training):
  describes double cleans, presses, squats and carries. The separate double-jerk
  technique block is an app-authored extension using the existing catalog, not a
  verified official Wildman jerk cycle or a pentathlon event. Its inclusion is an
  explicit programming choice; catalog coverage alone does not establish fidelity.
- [Tetris scheduling](https://www.wildmanathletica.com/programming): repeated
  movement programs can be scheduled as separate blocks on nonconsecutive days.

The added tracks are publicly labelled **app adaptations**. Twelve weeks is an
app default practice horizon, not a claim that a paid Wildman program ends then.
They do not automatically unlock a harder movement, add heavier bells or infer
proficiency from an athlete's calendar age or advanced/elite label.

Mobility durations are whole practice windows including brief efforts and rest;
a four-minute carry window is never an instruction for one continuous overhead
hold. Double-bell selection requires two matching bells; recorded weight is per
bell. A single-bell equipment label is insufficient.

## Regression gate

Run `.venv/bin/python -B tools/check_exercise_coverage.py`.
It generates all supported track/level combinations, refuses empty/failed runs,
rejects foreign exercise IDs and fails on any orphan catalog entry. CI runs it
alongside the contract checks. This establishes a usable generated path for each
exercise, independently of the catalog's notes or unused archetypes.
