# Training System — Ontology Author Guide

**Audience:** AI agents or humans adding a training methodology to the system as a
package: a folder under `data/packages/` that the app picks up without a code change.

**Read with:** `docs/package-fidelity/README.md` — how a package is built from its
sources, recorded (`fidelity.yaml`, the dossier) and graded, and the gates it must pass.
The JSON schemas in `docs/schemas/` are the field reference, and this guide points at them
rather than copying them. An agent can do all of it through the MCP server
(`docs/mcp/README.md`). What a package still cannot bring in its own folder is on Dev Lab ▸
Model Interactions and in `docs/roadmap.md` item 9.

**Validation:** After writing YAML files, run:
```
python tools/validate_entities.py path/to/your/file.yaml
python tools/validate_entities.py --all    # validate everything
```

---

## 1. The Ontology — What Each Entity Is

```
Philosophy
    └─ Tracks → Phases     (ways to follow it; each phase names a framework and a kind)
         └─ Framework      (how a week of a phase is built)
              └─ Modality  (what physical quality is trained — shared, in the commons)
                   └─ Archetype (what a single session looks like)
                        └─ Exercise (individual movements)
                             └─ Progression (how load/complexity increases)
                                  └─ Constraints (athlete-specific limits)
```

### What each entity means in plain English

**Philosophy** — A named training source or methodology. Examples: Starting Strength, CrossFit, Kelly Starrett's mobility system. A philosophy describes beliefs about training and declares one or more **tracks**: ordered lists of its own **phases**. Each phase has an id, a name, a **kind** from `data/commons/phase_kinds.yaml` (the engine reads the kind, never the words), weeks, the `framework_id` that builds its weeks, and its own text.

**Framework** — A weekly session structure: how many sessions of each modality, how hard, which days, how it deloads. A week is built one of three ways, decided by the data: a **training contract** (`training_contract.yaml`, per track) places its own modules; a phase's **week templates** write the source's week day by day from the framework's `categories`; otherwise the **modality scheduler** allocates `sessions_per_week`.

**Modality** — A physical quality domain, shared by every package (`data/commons/modalities/`). Map a methodology onto the existing ones; a new modality is a shared edit and, today, client code.

**Archetype** — A reusable session template. An archetype belongs to one modality and defines the session's slots (slot type, sets/reps/duration, intensity, `exercise_filter`).

**Exercise** — A single movement (e.g. back squat, hip circle, reverse sled drag). Exercises have categories, equipment, movement patterns, prerequisites, contraindications and the package's own starting loads.

**Goal** — Not authored. `src/goals.py:philosophy_to_goal` builds one per request from the chosen track.

---

## 2. Authoring Workflow

1. **Read the sources and keep a record** — `fidelity.yaml` and `docs/package-fidelity/<id>.md` (the README says what each holds).
2. **Write the folder** — philosophy with its tracks, frameworks, archetypes, exercises; the optional files below as the method needs them.
3. **Use the commons** — modalities, phase kinds, movement patterns, equipment, injury flags, standards and watch templates are shared vocabulary; reference them, do not redefine them.
4. **Bring it in** — `tools/add_package.py <id> --check`, then without `--check`: the folder's schemas, no id another package declares, every id in the commons, then its dossier stubbed and its baselines and golden hashes recorded. Then the gates the package-fidelity README lists (`tools/run_checks.py`; the pre-push hook runs them).

---

## 3. File Placement

Each methodology is one **self-contained package** under `data/packages/`:

```
data/
  packages/
    {your_package_id}/           ← one directory per methodology; the id is the folder name
      philosophy.yaml            ← the philosophy with its tracks and phases (exactly one)
      frameworks/{id}.yaml       ← one file per framework
      archetypes/<group>/{id}.yaml  ← any subfolders; strength/, conditioning/, kettlebell/, …
      exercises.yaml             ← exercises: [...]
      exercise_media.yaml        ← optional: demo links per exercise id
      level_seeds.yaml           ← optional: what an athlete at each level already knows
      analytics.yaml             ← optional: what progress means for the method
      watch.yaml                 ← optional: how its sessions look on the watches
      training_contract.yaml     ← optional: per track, modules the engine places as written
      fidelity.yaml              ← its sources, rules, inventions (docs/package-fidelity/README.md)
      source_weeks.yaml          ← optional: the source's own weeks, compared with generation
      standards.yaml             ← optional: standards the method tests that the commons lack
  commons/                       ← shared by every package: modalities, phase kinds,
                                 #   movement patterns, constraints, watch vocabulary, icons
  benchmarks/                    ← the shared standards and their groups (categories.yaml)
```

**Ids are package-scoped by convention, not by the loader.** Prefix archetype and framework ids with something your package owns: when two packages declare one id the loader keeps one copy silently (Dev Lab ▸ Model Interactions lists any). Exercise ids may be shared on purpose — each package keeps its own prescription.

---

## 4. Valid Values — Where They Live

The allowed values are not copied here: a copy drifts (this guide's did — framework and
philosophy lists a year out of date, 22 equipment ids where there are 30). Read them from the
source, or ask the MCP server (`list_valid_values(field)`, `docs/mcp/README.md`):

| Values | The one source |
|---|---|
| Modalities | `data/commons/modalities/<id>.yaml` — shared; a new one is a commons edit and `tools/gen_client_vocab.py` |
| Phase kinds (a phase's `kind`, an archetype's `applicable_phases`) | `data/commons/phase_kinds.yaml` |
| Equipment | `data/commons/constraints/equipment.yaml` (the four schemas' enums are generated from it) |
| Movement patterns and slot aliases | `data/commons/movement_patterns.yaml`, `data/commons/recovery_regions.yaml` |
| Injury flags | `data/commons/constraints/injury_flags.yaml` |
| Standards | `data/benchmarks/` (shared) and each package's own `standards.yaml` |
| Watch templates, fields, lines | `data/commons/watch_vocabulary.json` |
| Levels, slot types, intensities, progression models, categories | the enums in `docs/schemas/*.schema.json` |

---

## 5. The Files

Every file is checked by `tools/validate_entities.py` against its schema and the checks
beside it (section 6). Required fields, and a shipped file to read before writing one:

| File | Schema | Required | Read |
|---|---|---|---|
| `philosophy.yaml` | `philosophy.schema.json` | id, name, core_principles, scope, bias, tracks (each: id, name, phases; each phase: id, name, kind, weeks, framework_id) | `data/packages/kelly_starrett/philosophy.yaml` |
| `frameworks/<id>.yaml` | `framework.schema.json` | id, name, source_philosophy, sessions_per_week, progression_model | `data/packages/gym_jones/frameworks/` |
| `archetypes/**/<id>.yaml` | `archetype.schema.json` | id, name, modality, category, duration_estimate_minutes, slots (each: role, slot_type) | `data/packages/starting_strength/archetypes/` |
| `exercises.yaml` | `exercise.schema.json` (per entry) | id, name, category, modality, equipment, effort | `data/packages/starting_strength/exercises.yaml` |
| `training_contract.yaml` | `training_contract.schema.json` | version, sources, tracks | `data/packages/wildman_kettlebell/` (`docs/logic/training_contracts.md`) |
| `analytics.yaml` | `analytics.schema.json` | id, progress | any shipped package |
| `watch.yaml` | `watch.schema.json` | id, spec_version | `data/packages/wildman_kettlebell/watch.yaml` (`docs/watch.md`) |
| `standards.yaml` | `standards.schema.json` (entries: `benchmark.schema.json`) | standards (each: id, name, domain, metric_type, levels) | `test_package_standards.py` |
| `fidelity.yaml` | `fidelity.schema.json` | shape | any shipped package (`docs/package-fidelity/README.md`) |
| `source_weeks.yaml` | `source_weeks.schema.json` | — | `data/packages/horsemen_gpp/source_weeks.yaml` |
| `exercise_media.yaml`, `level_seeds.yaml` | — | — | any shipped package |

**A philosophy owns its phases.** A track is one way to follow the method, an ordered list of
its phases; each phase names its `kind` (what the engine reads), its `framework_id` (how its
weeks are built) and its own words (`focus`, `description`, `adaptations`, `intensity`). A
phase may also carry what the generator reads — `priority_override`, `exclude_exercises`,
`rotate_main_lifts`, `tests`, `week_templates`, `drop_order` — and `checks`, which only the
fidelity gate reads. There is no goal file: `src/goals.py` builds one per request from a track.

**The engine shape decides how a week is built** (README, "The method", step 2): a training
contract (`training_contract.yaml`) places its own modules; a phase's `week_templates` write the
source's week day by day from the framework's `categories`; otherwise the modality scheduler
allocates `sessions_per_week` by `cadence_options`.

---

## 6. Cross-Reference Rules

What `validate_entities.py --all` and `check_provenance.py` hold a package to, beyond its
schemas:

- every track and phase id is unique, and a phase's `framework_id` is this package's
  (`src/phases.validate_philosophy_tracks`);
- a templated phase's day categories are its framework's, and each category names this
  package's archetypes; a `pool_only` archetype is named by some day category;
- a test archetype measures a standard that exists, with a result its slot type and the
  standard's metric agree on, and names its `exercise_ids`; a package standard is its own or
  one it borrows;
- an injury flag's substitution pair is declared together in one package;
- no archetype, framework, media or standard id is another package's;
- a package draws only on itself and what its philosophy declares in `borrows_from`
  (`src/provenance.py`); `analytics.yaml` scopes only what it owns or borrows;
- a training contract with blocks loaded by weight names its `implement`.

`tools/add_package.py <id> --check` runs these for one package, plus every id in the commons.

---

## 7. Common Mistakes

- **A phase kind used as a phase id.** `kind: base` is the shared vocabulary; the phase's `id`
  and `name` are the method's own ("Foundations").
- **An id another package has.** Prefix archetype and framework ids with something your
  package owns; exercise ids may be shared on purpose (each package keeps its prescription).
- **A value copied from an old list.** Read it from its source (section 4).
- **A rule with nothing that enforces it.** Each rule in `fidelity.yaml` names what enforces it
  (data, a phase claim, a source week, a test), or the scorecard counts it as debt (S3).
- **Editing a shipped package through the API.** The API edits only the `custom` package; an
  authored package is changed as files in a branch, where the gates check it.

---

## 8. Worked Examples

The shipped packages are the examples, one per engine shape: Wildman (a training contract),
Horsemen (week templates) and `test_packages/block_fixture` (the modality scheduler).
`test_package_dropin.py` copies the three under new ids and runs them end to end — the shortest
proof of what a folder needs. To start a new one, `get_package_template(name)` on the MCP
server writes a valid skeleton.
