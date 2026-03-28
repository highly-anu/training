# Source Extraction Guide

How to add a new training source to the system. Use this to brief an LLM or AI agent.

---

## What an extraction produces

Every source gets one file:

- `docs/extracted/[source-name].md` — structured notes covering philosophy, methodology, archetypes, exercises, benchmarks, and programming rules

If the source includes explicit performance standards or benchmark tables, also produce:

- `data/benchmarks/[source-name].yaml` — structured standards data keyed by level/tier

Then update the Phase 0 table in `docs/roadmap.md` to mark the row done.

---

## Output format

All extraction `.md` files follow this structure. Omit sections that genuinely don't apply to the source — don't pad with guesses.

```markdown
# [Source Name] — Extracted Notes

Sources: [list actual files or URLs used]

---

## Philosophy
Core beliefs, non-negotiables, and guiding principles.
Direct quotes where available.

## Methodology
How training is structured over time:
- Weekly session structure (days/week, types per week)
- Intensity distribution model (e.g. 80/20 polarized, hard/easy, block periodization)
- Block or phase structure (if applicable)
- Progression philosophy

## Workout Archetypes
Reusable workout shapes — the named formats or session types this source uses.
For each: format, time domain, intensity, notes.

## Exercises
Exercises mentioned, grouped by category.
Include: loads/volumes where specified, progressions, any form cues that affect programming.

## Benchmarks / Standards
Specific numbers the source uses to define levels of fitness.
Testing protocols where described.

## Programming Rules
Explicit rules the system must follow when drawing from this source:
- Things this methodology always does
- Things it never does
- How it handles recovery, deloads, and phase transitions
- Interference rules with other modalities

## Equipment
What this source assumes is available.
Note anything minimal or specialized.
```

---

## Prompt templates

### Template A: extraction from a file you provide

Use this when you have a PDF, XLSX, DOCX, or other source file.

```
You are extracting structured training knowledge from a source document for a training system design project.

The project uses this ontology:
  Philosophy → Methodology → Modalities → Archetypes → Exercises → Progression → Constraints → Goal → Program

Your task: read [SOURCE FILE(S)] and produce a structured extraction following the format in `docs/extraction-guide.md`.

Source: [describe the source — author, title, what it covers]
File(s): [file path(s)]
Output file: docs/extracted/[source-name].md

Instructions:
- Work from the actual content of the file. Do not fill gaps from general knowledge.
- Be specific: include numbers (weights, reps, times, distances, percentages) wherever the source provides them.
- If the source uses named workouts or protocols, list them by name with their full format.
- If the source includes benchmark standards or performance tiers, also produce data/benchmarks/[source-name].yaml using the format from data/benchmarks/cell_standards.yaml as a reference.
- After writing the file(s), update the Phase 0 table in docs/roadmap.md to mark this source as done.
```

---

### Template B: extraction from a well-known source (no file)

Use this when the source is a widely-documented book, methodology, or coach whose work is publicly available.

```
You are extracting structured training knowledge from a well-known source for a training system design project.

The project uses this ontology:
  Philosophy → Methodology → Modalities → Archetypes → Exercises → Progression → Constraints → Goal → Program

Your task: research [SOURCE] thoroughly and produce a structured extraction following the format in `docs/extraction-guide.md`.

Source: [author/title/methodology — e.g. "Uphill Athlete by Steve House and Scott Johnston", "Al Kavadlo calisthenics methodology", "Juggernaut Method by Chad Wesley Smith"]

Instructions:
- Prioritize information from the primary source (book, official website, authored articles) over secondary commentary.
- Be specific: include numbers where the source provides them (rep maxes, week structures, zone boundaries, etc.).
- If different editions or iterations of the methodology exist, note which version you are drawing from.
- Mark any section where you are inferring from general knowledge rather than a specific source claim — use "(inferred)" at the end of that line.
- Output file: docs/extracted/[source-name].md
- If benchmark standards exist, also produce: data/benchmarks/[source-name].yaml
- After writing, add a row to the Phase 0 table in docs/roadmap.md.
```

---

### Template C: extracting a new domain (no single canonical source)

Use this when you want to cover a domain (e.g. "ultra running", "gymnastics") that draws from multiple sources.

```
You are adding a new training domain to a training system design project.

The project uses this ontology:
  Philosophy → Methodology → Modalities → Archetypes → Exercises → Progression → Constraints → Goal → Program

Your task: produce a structured extraction for the domain "[DOMAIN]" by synthesizing the best-established knowledge from the primary sources in that field.

Domain: [e.g. "ultra running", "gymnastics strength training", "calisthenics / street workout"]
Primary sources to draw from: [e.g. "Uphill Athlete, Hal Koerner's Field Guide, David Roche coaching", or "Overcoming Gravity by Steven Low, GMB Fitness, Christopher Sommer Building the Gymnastic Body"]

Instructions:
- Treat this domain as a single philosophy entry in the system, even if multiple coaches contributed.
- Where sources disagree on something important (e.g. volume vs. intensity priority in ultra running training), note the disagreement explicitly — don't paper over it.
- Focus on what is unique or distinctive about this domain vs. what is already covered by existing sources in docs/extracted/.
- Mark consensus vs. contested positions clearly.
- Output file: docs/extracted/[domain-name].md
- If benchmark standards exist (e.g. race finish times, gymnastics skill levels), also produce: data/benchmarks/[domain-name].yaml
- After writing, add a row to the Phase 0 table in docs/roadmap.md.
```

---

## What to adjust per domain type

| Domain type | Emphasize | Notes |
|-------------|-----------|-------|
| Strength-focused (barbell, KB) | Progression models, intensity %s, deload rules | Linear or block progression; numbers matter most |
| Endurance (running, cycling, rucking) | Volume periodization, zone structure, peak mileage, taper | Add `volume_progression` section to archetypes |
| Skill/movement (gymnastics, calisthenics, movement) | Prerequisite tree, skill levels, practice format | Progression is complexity-based, not load-based |
| Combat sport (BJJ, wrestling) | Conditioning formats specific to the sport, injury patterns | Mat time as primary modality; gym work is supplementary |
| Rehab/prehab | Phase transition criteria, return-to-sport criteria | Link to injury flags in constraint layer |
| Mixed/GPP | All of the above at lower resolution | Identify which existing sources it draws from |

---

## What to do with the file after extraction

1. Read `docs/plan.md` sections 1–4 and note which parts of the new source fill gaps identified there
2. If the source adds a new modality not in `plan.md`, add it to the modalities list
3. If the source adds a new workout archetype shape, add it to the archetypes table
4. If the source changes your understanding of an existing philosophy schema, update `plan.md` accordingly

Extraction files are inputs to Phase 1 (schema design) and Phase 2 (data population). They don't need to be perfect — they need to be honest about what the source says vs. what was inferred.

---

## File naming conventions

| Type | Convention | Example |
|------|-----------|---------|
| Extraction notes | `docs/extracted/[kebab-case].md` | `docs/extracted/uphill-athlete.md` |
| Benchmark standards | `data/benchmarks/[kebab-case].yaml` | `data/benchmarks/uphill-athlete.yaml` |
| Source files (PDFs etc.) | `data/[domain]/[original-filename]` | `data/ultra-running/uphill-athlete-ch4.pdf` |

---

## Current extractions completed

| Source | File | Notes |
|--------|------|-------|
| Gym Jones | `docs/extracted/gym-jones.md` | From 3 PDFs: Operator Fitness I, II, Soldier of Steel |
| Horsemen GPP | `docs/extracted/horsemen.md` | From horsemen.pdf; 4-month operator program |
| Ido Portal | `docs/extracted/ido-portal.md` | Floreio Routines PDF only; locomotion + equilibre |
| CrossFit Journal | `docs/extracted/crossfit-journal.md` | 11 articles, 2002–2012 |
| Kettlebell (personal log) | `docs/extracted/kettlebell.md` | From XLSX; small personal workout log, not a canonical source |
| The Cell Standards | `data/benchmarks/cell_standards.yaml` | Full Level I–V across all domains |

**Not yet extracted (in plan.md):**
- Starting Strength (Rippetoe) — only JSON schema stub exists; no extraction notes
- Uphill Athlete (House/Johnston) — no source file; can be done from book via Template B
- Marcus Filly / Functional Bodybuilding — no source file; Template B
- ATG / Knees Over Toes — no source file; Template B
- Kelly Starrett / Supple Leopard — no source file; Template B
- BJJ conditioning — no single canonical source; Template C
