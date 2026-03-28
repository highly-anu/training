# Training Program Generator

Algorithmically generates multi-week training programs from goal profiles, equipment, and constraints. Pulls methodology from Starting Strength, Uphill Athlete, Gym Jones, Horsemen, CrossFit Endurance, Wildman kettlebell, and Ido Portal.

## Usage

```bash
python main.py --goal <goal_id> [options]
```

### Goals

| ID | Description |
|----|-------------|
| `general_gpp` | General physical preparedness — balanced concurrent training |
| `alpine_climbing` | Alpine / mountaineering performance — aerobic base + strength |
| `sof_operator` | SOF / Horsemen standard — work capacity + strength + rucking |
| `bjj_competitor` | BJJ competition prep — combat conditioning + strength endurance |
| `ultra_endurance` | Ultra-endurance events — polarized aerobic base |
| `max_strength_focus` | Strength-first — Starting Strength / HLM barbell programming |
| `injury_rehab` | Injury-modified training — maintains fitness around a rehab constraint |

### Key options

| Flag | Default | Description |
|------|---------|-------------|
| `--days` | 5 | Training days per week |
| `--time` | 75 | Session length in minutes |
| `--level` | intermediate | `novice` / `intermediate` / `advanced` / `elite` |
| `--phase` | base | `base` / `build` / `peak` / `taper` / `deload` / `maintenance` / `rehab` / `post_op` |
| `--week` | 1 | Starting week within the phase |
| `--weeks` | 4 | Number of weeks to generate |
| `--equipment` | full barbell gym | Equipment preset or comma-separated list |
| `--injuries` | none | Comma-separated injury flags |
| `--fatigue` | normal | `fresh` / `normal` / `accumulated` / `overreached` |
| `--event-date` | — | `YYYY-MM-DD` — auto-computes phase and week from the calendar |
| `--full` | — | With `--event-date`, generates all remaining weeks through the event |

### Equipment presets

| Preset | Contents |
|--------|----------|
| `barbell_gym` | Full barbell gym + KB + rower + box |
| `home_barbell` | Barbell + rack + KB + pull-up bar |
| `home_kb_only` | Kettlebell + pull-up bar |
| `bodyweight_only` | Pull-up bar + open space |
| `outdoor` | Ruck pack + open space |

### Examples

```bash
# 5-day intermediate GPP program
python main.py --goal general_gpp --days 5 --level intermediate

# Alpine build phase, week 3, full gym
python main.py --goal alpine_climbing --days 5 --phase build --week 3

# KB-only SOF program
python main.py --goal sof_operator --equipment home_kb_only --days 4

# Knee injury — auto-filters contraindicated exercises
python main.py --goal general_gpp --injuries knee_meniscus_post_op --days 4

# Event-date mode — computes which phase/week you're in automatically
python main.py --goal alpine_climbing --event-date 2026-08-15 --days 5

# Full remaining program to event across all phases
python main.py --goal alpine_climbing --event-date 2026-08-15 --days 5 --full
```

## Data

```
data/
  philosophies/    11 source philosophies (SS, UA, Gym Jones, Horsemen, etc.)
  frameworks/      9 methodological frameworks
  modalities/      12 training domains
  archetypes/      20 workout templates
  exercises/       191 exercises across 9 categories
  goals/           7 goal profiles
  constraints/     injury flags (12) + equipment profiles (5)
  benchmarks/      performance standards
```
