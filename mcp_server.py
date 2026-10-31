#!/usr/bin/env python3
"""MCP server for the training system package authoring workflow.

Lets AI agents write a package folder (data/packages/<id>/, or
TRAINING_PACKAGES_DIR) without reading documentation: query valid values → get
templates → write files → validate → fix → bring it in with
tools/add_package.py. Every file is checked by the one validator
(tools/validate_entities.py — the schemas in docs/schemas/ and the checks
beside them, for every kind a package carries), and a package by add_package's
checks too (no id another package declares, every id in the commons).

Setup (Claude Code CLI), from the checkout:
  claude mcp add --transport stdio training -- .venv/bin/python mcp_server.py
It needs the MCP SDK (`pip install mcp`); without it the tools still import,
which is how test_mcp_server.py runs them. docs/mcp/README.md lists the tools.
"""

import json
import sys
import yaml
import jsonschema
from pathlib import Path
from typing import Any

# ── Path setup ────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from src import loader  # noqa: E402
from tools import validate_entities as ve  # noqa: E402

try:
    from mcp.server.fastmcp import FastMCP  # noqa: E402
except ImportError:  # the tools stay importable (test_mcp_server.py) without the SDK
    class FastMCP:  # type: ignore[no-redef]
        def __init__(self, name: str):
            self.name = name

        def tool(self):
            return lambda f: f

        def run(self):
            raise SystemExit('The MCP SDK is not installed: pip install mcp')

# ── Constants ─────────────────────────────────────────────────────────────────
SCHEMAS_DIR  = ROOT / 'docs' / 'schemas'
# The folder the loader reads, so a test or a scratch run can point it elsewhere.
PACKAGES_DIR = Path(loader._PACKAGES_DIR)

# Every modality the commons define, by its file (data/commons/modalities).
VALID_MODALITIES = sorted(p.stem for p in (ROOT / 'data' / 'commons' / 'modalities').glob('*.yaml'))

SCHEMA_FILES = {
    'philosophy':        'philosophy.schema.json',
    'framework':         'framework.schema.json',
    'archetype':         'archetype.schema.json',
    'exercise':          'exercise.schema.json',
    'analytics':         'analytics.schema.json',
    'watch':             'watch.schema.json',
    'training_contract': 'training_contract.schema.json',
    'fidelity':          'fidelity.schema.json',
    'source_weeks':      'source_weeks.schema.json',
    'standards':         'standards.schema.json',
}
# Where each kind lives in a package folder: validate_entities finds its schema
# (and the checks beside it) by the file's place.
KIND_PATHS = {
    'philosophy': 'philosophy.yaml', 'framework': 'frameworks/{id}.yaml',
    'archetype': 'archetypes/{id}.yaml', 'exercise': 'exercises.yaml',
    'analytics': 'analytics.yaml', 'watch': 'watch.yaml', 'training_contract': 'training_contract.yaml',
    'fidelity': 'fidelity.yaml', 'source_weeks': 'source_weeks.yaml', 'standards': 'standards.yaml',
}

mcp = FastMCP("training")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _load_schema(entity_type: str) -> dict:
    filename = SCHEMA_FILES.get(entity_type)
    if not filename:
        raise ValueError(f"Unknown entity_type '{entity_type}'. Valid: {list(SCHEMA_FILES)}")
    with open(SCHEMAS_DIR / filename, encoding='utf-8') as f:
        return json.load(f)


# ── Query tools ───────────────────────────────────────────────────────────────

@mcp.tool()
def list_modality_ids() -> list[str]:
    """
    Return all modality IDs in use across installed packages.

    Includes the 12 core modalities plus any package-specific modalities
    (e.g. 'swimming', 'cycling') introduced by installed packages.
    Use this as a reference — new packages may define additional modalities
    in their philosophy scope without restriction.
    """
    modality_ids: set[str] = set(VALID_MODALITIES)
    for phil in loader.load_philosophies():
        modality_ids.update(phil.get('scope', []))
        modality_ids.update(phil.get('bias', []))
    for arch in loader.load_all_archetypes():
        if arch.get('modality'):
            modality_ids.add(arch['modality'])
    return sorted(modality_ids)


@mcp.tool()
def list_philosophy_ids() -> list[str]:
    """Return IDs of all installed philosophies. Check this before creating a new package to avoid ID collisions."""
    return [p['id'] for p in loader.load_philosophies()]


@mcp.tool()
def list_framework_ids() -> list[str]:
    """Return IDs of all installed frameworks."""
    return list(loader.load_all_frameworks().keys())


@mcp.tool()
def list_archetype_ids() -> list[dict]:
    """Return all installed archetypes with their modality and source package."""
    return [
        {'id': a['id'], 'modality': a.get('modality'), 'package': a.get('_package')}
        for a in loader.load_all_archetypes()
    ]


@mcp.tool()
def list_valid_values(field: str) -> list[str]:
    """
    Return valid enum values for a named field. Use before writing any YAML.

    Supported fields:
      intensity, slot_type, training_level, training_phase, equipment,
      exercise_category, intensity_model, progression_philosophy,
      movement_pattern, progression_model, exercise_effort, archetype_category
    """
    # movement_pattern and modality are open — read from installed packages dynamically
    if field == 'movement_pattern':
        patterns: set[str] = set()
        # Seed from commons aliases file
        commons_mp = ROOT / 'data' / 'commons' / 'movement_patterns.yaml'
        if commons_mp.exists():
            data = yaml.safe_load(commons_mp.read_text(encoding='utf-8'))
            for alias_data in data.get('aliases', {}).values():
                patterns.update(alias_data.get('patterns', []))
        # Collect from all installed exercises
        ex_global, _ = loader.load_all_exercises()
        for ex in ex_global.values():
            patterns.update(ex.get('movement_patterns', []))
        return sorted(patterns)

    if field == 'modality':
        return list_modality_ids()

    field_map: dict[str, tuple[str, list[str]]] = {
        'intensity':              ('archetype', ['properties', 'slots', 'items', 'properties', 'intensity', 'enum']),
        'slot_type':              ('archetype', ['properties', 'slots', 'items', 'properties', 'slot_type', 'enum']),
        'training_level':         ('archetype', ['properties', 'training_levels', 'items', 'enum']),
        'training_phase':         ('archetype', ['properties', 'applicable_phases', 'items', 'enum']),
        'equipment':              ('philosophy', ['properties', 'required_equipment', 'items', 'enum']),
        'exercise_category':      ('exercise',   ['properties', 'category', 'enum']),
        'intensity_model':        ('philosophy', ['properties', 'intensity_model', 'enum']),
        'progression_philosophy': ('philosophy', ['properties', 'progression_philosophy', 'enum']),
        'progression_model':      ('framework',  ['properties', 'progression_model', 'enum']),
        'exercise_effort':        ('exercise',   ['properties', 'effort', 'enum']),
        'archetype_category':     ('archetype',  ['properties', 'category', 'enum']),
    }

    entry = field_map.get(field)
    if not entry:
        return [f"Unknown field '{field}'. Supported: {sorted(['movement_pattern', 'modality'] + list(field_map.keys()))}"]

    schema_type, path = entry
    node = _load_schema(schema_type)
    for key in path:
        node = node[key]
    return node


# ── Template tools ────────────────────────────────────────────────────────────

@mcp.tool()
def get_package_template(package_name: str) -> dict[str, str]:
    """
    Return skeleton YAML content for a new package.

    Keys are relative file paths within data/packages/<package_name>/.
    Values are YAML strings with all required fields present and valid
    enum values listed in comments.

    Write these files to disk, then fill in the placeholders before calling
    validate_package().
    """
    slug = package_name.lower().replace(' ', '_').replace('-', '_')
    title = package_name.replace('_', ' ').title()

    philosophy_yaml = f"""\
id: {slug}
name: "{title}"
core_principles:
  - principle_one        # Non-negotiable beliefs as short slugs
  - principle_two
scope:
  - mobility             # Modalities this philosophy claims authority over.
                         # Valid: max_strength | strength_endurance | relative_strength |
                         #        aerobic_base | anaerobic_intervals | mixed_modal_conditioning |
                         #        power | mobility | movement_skill | durability | combat_sport | rehab
bias:
  - mobility             # Subset of scope — what this philosophy emphasizes most.
# avoid_with: []         # Modality IDs that conflict at high volume.
# required_equipment: [] # barbell | rack | plates | kettlebell | dumbbell | pull_up_bar |
                         # rings | parallettes | rower | bike | ski_erg | ruck_pack | sandbag |
                         # sled | tire | medicine_ball | resistance_band | rope | box |
                         # ghd | jump_rope | open_space
intensity_model: skill_based
                         # linear_progression | polarized_80_20 | block_periodization |
                         # autoregulation_rpe | constant_variation | skill_based |
                         # hard_easy_alternation | operator_readiness
progression_philosophy: complexity_based
                         # load_based | volume_based | complexity_based | time_based |
                         # density_based | feel_based | rpm_based | range_based

primary_track_id: default
                         # Default track. Each track is one way to follow this
                         # philosophy: an ordered list of its OWN phases. Phase
                         # names and text belong to this package only.

tracks:
  - id: default
    name: "{title} Program"
    description: "What this track is for and when to choose it."
    phases:
      - id: {slug}_block
        name: "{title} Block"
        kind: base           # transition | base | build | specific | peak | taper |
                             # maintenance | deload | recovery | rehab | post_op | active
                             # (data/commons/phase_kinds.yaml — the engine keys on this)
        weeks: 8
        framework_id: {slug}_framework
        focus: "One-line focus"
        description: "What this phase is and why, in this philosophy's own words."
        # adaptations: ["…"]
        # intensity: "…"
        # repeatable: true   # a block that may be cycled
                         # A phased program lists several phases in order, each on
                         # the framework that builds its weeks:
                         #   phases:
                         #     - {{id: transition, name: Transition, kind: transition, weeks: 4,
                         #        framework_id: {slug}_transition_phase, ...}}
                         #     - {{id: base, name: Base, kind: base, weeks: 16,
                         #        framework_id: {slug}_base_phase, ...}}
                         # Alternative goals (pick one) are separate tracks.

sources: []
# notes: ""
"""

    framework_yaml = f"""\
id: {slug}_framework
name: "{title} Framework"
source_philosophy: {slug}

goals_served:
  - mobility             # modality IDs

sessions_per_week:
  mobility: 3            # modality_id: sessions (0–7)

intensity_distribution:
  zone1_2_pct: 0.8
  zone3_pct: 0.2
  zone4_5_pct: 0.0
  max_effort_pct: 0.0

progression_model: complexity
                         # linear_load | density | volume_block | complexity | time_to_task |
                         # intensity_split_shift | rpe_autoregulation | pentathlon_rpm | range_progression

applicable_when:
  training_level:
    - novice
    - intermediate
    - advanced
    - elite
  days_per_week_min: 1
  days_per_week_max: 7

deload_protocol:
  frequency_weeks: 4
  volume_reduction_pct: 0.6
  intensity_change: maintain   # maintain | reduce_slightly | reduce_significantly

expectations:
  min_weeks: 8               # Minimum program duration in weeks for this framework to be effective
  ideal_weeks: 12            # Ideal/recommended program duration in weeks
  min_days_per_week: 3       # Minimum training days per week required
  ideal_days_per_week: 4     # Ideal training days per week for this framework
  min_session_minutes: 45    # Minimum session duration in minutes
  ideal_session_minutes: 60  # Ideal session duration in minutes
  # ideal_long_session_minutes: 90  # Optional: ideal duration for long sessions (e.g., weekend endurance work)
  supports_split_days: false # Whether this framework supports split sessions (AM/PM training on same day)

sources: []
# notes: ""
"""

    archetype_yaml = f"""\
id: {slug}_session
name: "{title} Session"
modality: mobility
           # max_strength | strength_endurance | relative_strength | aerobic_base |
           # anaerobic_intervals | mixed_modal_conditioning | power | mobility |
           # movement_skill | durability | combat_sport | rehab
category: movement_skill
           # strength | conditioning | movement_skill | gpp_durability |
           # kettlebell | recovery | rehab | combat_sport
training_levels:
  - novice
  - intermediate
  - advanced
  - elite
duration_estimate_minutes: 45
# applicable_phases: []  # base | build | peak | taper | deload | maintenance | rehab | recovery

slots:
  - role: warmup
    slot_type: time_domain
               # sets_reps | time_domain | distance | amrap | amrap_movement |
               # emom | for_time | rounds_for_time | skill_practice | static_hold
    duration_minutes: 10
    intensity: low
               # max | max_effort | heavy | submaximal | progressing | moderate |
               # medium | light | low | high | bodyweight | zone1 | zone2 | zone3 | zone4 | zone4_5 | zone5
    exercise_filter:
      category: mobility

  - role: main_practice
    slot_type: skill_practice
    duration_minutes: 30
    intensity: moderate
    exercise_filter:
      category: mobility

sources: []
# notes: ""
"""

    exercises_yaml = f"""\
exercises:
  - id: {slug}_example
    name: "Example Exercise"
    category: mobility   # barbell | kettlebell | bodyweight | aerobic | loaded_carry |
                         # carries | sandbag | mobility | skill | rehab | accessory
    modality:
      - mobility         # one or more valid modality IDs
    equipment:
      - none             # barbell | rack | plates | kettlebell | dumbbell | pull_up_bar |
                         # rings | parallettes | rower | bike | ski_erg | ruck_pack |
                         # sandbag | sled | tire | medicine_ball | resistance_band |
                         # rope | box | ghd | jump_rope | open_space | pool | none
    effort: low          # low | medium | high | max
    bilateral: true
    movement_patterns:
      - isometric        # hip_hinge | squat | horizontal_push | horizontal_pull |
                         # vertical_push | vertical_pull | loaded_carry | rotation |
                         # hip_flexion | knee_extension | locomotion | ballistic |
                         # olympic_lift | isometric | aerobic_monostructural |
                         # farmer_carry | rack_carry | step_up
    # requires: []
    # unlocks: []
    # contraindicated_with: []
    progressions:
      complexity: next_harder_variation_id
    typical_volume:
      duration_sec: 30
    # sources: []
    # notes: ""
"""

    return {
        'philosophy.yaml':                               philosophy_yaml,
        f'frameworks/{slug}_framework.yaml':             framework_yaml,
        f'archetypes/movement_skill/{slug}_session.yaml': archetype_yaml,
        'exercises.yaml':                                exercises_yaml,
    }


@mcp.tool()
def get_archetype_template(modality: str, slot_type: str) -> str:
    """
    Return a skeleton archetype YAML for the given modality and slot_type.

    modality: one of the 12 valid modality IDs (call list_modality_ids() if unsure).
    slot_type: sets_reps | time_domain | distance | amrap | amrap_movement |
               emom | for_time | rounds_for_time | skill_practice | static_hold
    """
    category_map = {
        'max_strength':             'strength',
        'relative_strength':        'strength',
        'strength_endurance':       'conditioning',
        'aerobic_base':             'conditioning',
        'anaerobic_intervals':      'conditioning',
        'mixed_modal_conditioning': 'conditioning',
        'power':                    'strength',
        'mobility':                 'movement_skill',
        'movement_skill':           'movement_skill',
        'durability':               'gpp_durability',
        'combat_sport':             'combat_sport',
        'rehab':                    'rehab',
    }
    category = category_map.get(modality, 'conditioning')

    slot_volume = {
        'sets_reps':       'sets: 3\n    reps: 5\n    rest_sec: 180',
        'time_domain':     'duration_minutes: 20',
        'distance':        'distance_m: 5000',
        'amrap':           'duration_minutes: 20',
        'amrap_movement':  'reps_per_round: 10',
        'emom':            'duration_minutes: 10',
        'for_time':        'rounds: 1',
        'rounds_for_time': 'rounds: 3',
        'skill_practice':  'duration_minutes: 20',
        'static_hold':     'hold_seconds: 30\n    sets: 3',
    }.get(slot_type, 'duration_minutes: 20')

    return f"""\
id: new_{modality}_{slot_type}
name: "New {modality.replace('_', ' ').title()} ({slot_type.replace('_', ' ')})"
modality: {modality}
category: {category}
training_levels:
  - novice
  - intermediate
  - advanced
duration_estimate_minutes: 45
# applicable_phases: []

slots:
  - role: primary
    slot_type: {slot_type}
    {slot_volume}
    intensity: moderate
    exercise_filter:
      category: {category}
      # movement_pattern: hip_hinge
      # bilateral: true

# scaling:
#   deload:
#     volume_multiplier: 0.6
#   time_limited:
#     drop_slots: [secondary]

# required_equipment: []
# sources: []
# notes: ""
"""


# ── Validation tools ──────────────────────────────────────────────────────────

@mcp.tool()
def validate_yaml(entity_type: str, yaml_content: str, package_name: str | None = None) -> dict:
    """
    Validate a YAML string as one package file of entity_type, with the same
    checks the push gates run (tools/validate_entities.py).

    entity_type: philosophy | framework | archetype | exercise | analytics |
      watch | training_contract | fidelity | source_weeks | standards
    package_name: the package it belongs to, when a check reads its other
      files (an archetype's standard is checked against what it borrows).

    For exercises, pass the full file content (with its top-level 'exercises:' key).

    Returns: {"valid": bool, "errors": [{"path": str, "message": str}]}
    """
    rel = KIND_PATHS.get(entity_type)
    if not rel:
        return {'valid': False, 'errors': [{'path': '(setup)', 'message':
                f"Unknown entity_type '{entity_type}'. Valid: {sorted(KIND_PATHS)}"}]}
    if not package_name and entity_type == 'philosophy':
        try:   # a philosophy names its package
            package_name = (yaml.safe_load(yaml_content) or {}).get('id')
        except yaml.YAMLError:
            pass
    return _validate_text(package_name or '_draft', rel.format(id='draft'), yaml_content)


def _validate_text(package_name: str, relative_path: str, content: str) -> dict:
    """The content checked as the file it would be: written into a scratch copy
    of its package (whose other files some checks read — a philosophy's
    frameworks, an archetype's borrows) and run through
    validate_entities.validate_file."""
    import shutil
    import tempfile
    try:
        yaml.safe_load(content)
    except yaml.YAMLError as e:
        return {'valid': False, 'errors': [{'path': '(yaml parse)', 'message': str(e)}]}
    with tempfile.TemporaryDirectory() as tmp:
        pkg = Path(tmp) / 'packages' / package_name
        if (PACKAGES_DIR / package_name).is_dir():
            shutil.copytree(PACKAGES_DIR / package_name, pkg)
        target = pkg / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        if not (pkg / 'philosophy.yaml').exists():
            (pkg / 'philosophy.yaml').write_text(f'id: {package_name}\n', encoding='utf-8')
        target.write_text(content, encoding='utf-8')
        errors = ve.validate_file(str(target), verbose=False) or []
    return {'valid': not errors, 'errors': [{'path': relative_path, 'message': e} for e in errors]}


@mcp.tool()
def validate_package(package_path: str) -> dict:
    """
    Validate a package folder with the gates' own checks.

    package_path: package name ('yoga') or path ('data/packages/yoga').

    Checks:
      - every file against its schema and the checks beside it
        (tools/validate_entities.py: tracks and phases, templates and pools,
        tests and standards, contracts, analytics, watch screens, fidelity);
      - no id another package declares, every id in the commons, the files a
        package needs (tools/add_package.py, src/portability.py);
      - a warning for a modality in the philosophy's scope that no archetype serves.

    Then bring it in: .venv/bin/python tools/add_package.py <id> (--check first).

    Returns: {"valid": bool, "files": {filename: [error strings]}}
    """
    pkg_dir = PACKAGES_DIR / package_path if '/' not in package_path and '\\' not in package_path \
              else ROOT / package_path
    if not pkg_dir.exists():
        return {'valid': False, 'files': {'(setup)': [f'Directory not found: {pkg_dir}']}}

    file_errors: dict[str, list[str]] = {}
    for path, errors in ve.validate_path(str(pkg_dir), verbose=False).items():
        if errors:
            file_errors[Path(path).relative_to(pkg_dir).as_posix()] = list(errors)

    if pkg_dir.resolve().parent == PACKAGES_DIR.resolve():
        from src import portability
        from tools.add_package import _problems
        problems = _problems(pkg_dir.name, portability.report()) \
            if any(p['id'] == pkg_dir.name for p in portability.report()['packages']) else []
        if problems:
            file_errors['(package)'] = problems

    phil_file = pkg_dir / 'philosophy.yaml'
    if phil_file.exists():
        try:
            phil_data = yaml.safe_load(phil_file.read_text(encoding='utf-8')) or {}
            arch_modalities = set()
            for arch_path in pkg_dir.glob('archetypes/**/*.yaml'):
                arch = yaml.safe_load(arch_path.read_text(encoding='utf-8')) or {}
                if arch.get('modality'):
                    arch_modalities.add(arch['modality'])
            warnings = [f"Warning: modality '{m}' is in scope but has no archetype in this package."
                        for m in sorted(set(phil_data.get('scope') or []) - arch_modalities)]
            if warnings:
                file_errors.setdefault('philosophy.yaml', []).extend(warnings)
        except Exception:
            pass

    valid = not any(e for f, errs in file_errors.items() for e in errs if not e.startswith('Warning:'))
    return {'valid': valid, 'files': file_errors}


@mcp.tool()
def check_id_available(entity_type: str, proposed_id: str) -> dict:
    """
    Check whether a proposed ID is already in use across all installed packages.

    entity_type: philosophy | framework | archetype | exercise | standard
    Returns: {"available": bool, "conflict": str | null}
    """
    if entity_type == 'philosophy':
        ids = {p['id']: p.get('name', '') for p in loader.load_philosophies()}
    elif entity_type == 'framework':
        ids = {k: v.get('name', '') for k, v in loader.load_all_frameworks().items()}
    elif entity_type == 'archetype':
        ids = {a['id']: a.get('name', '') for a in loader.load_all_archetypes()}
    elif entity_type == 'exercise':
        ex_global, _ = loader.load_all_exercises()
        ids = {k: v.get('name', '') for k, v in ex_global.items()}
    elif entity_type == 'standard':
        from src.analytics import benchmarks_data
        ids = {b['id']: b.get('name', '') for b in benchmarks_data.load_benchmarks()}
    else:
        return {'available': False, 'conflict': f"Unknown entity_type '{entity_type}'. "
                'Valid: philosophy | framework | archetype | exercise | standard'}

    if proposed_id in ids:
        return {'available': False, 'conflict': f"'{proposed_id}' is already used by: {ids[proposed_id]}"}
    return {'available': True, 'conflict': None}


# ── Cross-reference tools ─────────────────────────────────────────────────────

@mcp.tool()
def get_package_summary(package_name: str) -> dict[str, Any]:
    """
    Return a summary of an existing package: philosophy metadata, framework
    sessions_per_week, archetype count by modality, exercise count.

    Useful for understanding what a package contains before extending or
    referencing it.
    """
    pkg_dir = PACKAGES_DIR / package_name
    if not pkg_dir.exists():
        installed = sorted(p.name for p in PACKAGES_DIR.iterdir() if p.is_dir())
        return {'error': f"Package '{package_name}' not found.", 'installed_packages': installed}

    result: dict[str, Any] = {'package': package_name}

    phil_file = pkg_dir / 'philosophy.yaml'
    if phil_file.exists():
        phil = yaml.safe_load(phil_file.read_text(encoding='utf-8'))
        result['philosophy'] = {
            'id':                    phil.get('id'),
            'name':                  phil.get('name'),
            'scope':                 phil.get('scope', []),
            'bias':                  phil.get('bias', []),
            'avoid_with':            phil.get('avoid_with', []),
            'intensity_model':       phil.get('intensity_model'),
            'progression_philosophy': phil.get('progression_philosophy'),
        }

    frameworks = []
    for fw_path in sorted(pkg_dir.glob('frameworks/*.yaml')):
        fw = yaml.safe_load(fw_path.read_text(encoding='utf-8'))
        frameworks.append({
            'id':                fw.get('id'),
            'name':              fw.get('name'),
            'sessions_per_week': fw.get('sessions_per_week', {}),
            'progression_model': fw.get('progression_model'),
        })
    result['frameworks'] = frameworks

    archetype_counts: dict[str, int] = {}
    for arch_path in pkg_dir.glob('archetypes/**/*.yaml'):
        arch = yaml.safe_load(arch_path.read_text(encoding='utf-8'))
        mod = arch.get('modality', 'unknown')
        archetype_counts[mod] = archetype_counts.get(mod, 0) + 1
    result['archetype_count_by_modality'] = archetype_counts
    result['total_archetypes'] = sum(archetype_counts.values())

    ex_file = pkg_dir / 'exercises.yaml'
    result['exercise_count'] = len(
        yaml.safe_load(ex_file.read_text(encoding='utf-8')).get('exercises', [])
    ) if ex_file.exists() else 0

    return result


@mcp.tool()
def list_package_exercises(package_name: str) -> dict:
    """
    Return the full exercise records for an installed package.

    Use this before extending a package to see what exercises already exist,
    avoid duplicating IDs, and understand what movement patterns are covered.

    Returns: {"package": str, "count": int, "exercises": [exercise records]}
    Each record includes all fields: id, name, category, modality, equipment,
    effort, movement_patterns, requires, unlocks, progressions, etc.
    """
    pkg_dir = PACKAGES_DIR / package_name
    if not pkg_dir.exists():
        installed = sorted(p.name for p in PACKAGES_DIR.iterdir() if p.is_dir())
        return {'error': f"Package '{package_name}' not found.", 'installed_packages': installed}

    ex_file = pkg_dir / 'exercises.yaml'
    if not ex_file.exists():
        return {'package': package_name, 'count': 0, 'exercises': []}

    data = yaml.safe_load(ex_file.read_text(encoding='utf-8'))
    exercises = data.get('exercises', [])
    return {'package': package_name, 'count': len(exercises), 'exercises': exercises}


# ── Write tools ──────────────────────────────────────────────────────────────

@mcp.tool()
def write_package_file(
    package_name: str,
    relative_path: str,
    content: str,
    overwrite: bool = False,
) -> dict:
    """
    Write a file into a package directory.

    package_name: the package slug, e.g. 'yoga'. The directory
      data/packages/yoga/ will be created if it does not exist.
    relative_path: path within the package, e.g. 'philosophy.yaml',
      'frameworks/yoga_framework.yaml', or
      'archetypes/movement_skill/yoga_session.yaml'.
    content: full YAML string to write.
    overwrite: if False (default), refuses to overwrite an existing file.
      Set to True only when intentionally replacing or extending a file.

    The content is validated against its schema before writing. The write
    is rejected if validation fails — fix the errors and retry.

    Returns: {"written": bool, "path": str, "errors": [...]}
    """
    # Resolve and guard the target path
    pkg_dir = PACKAGES_DIR / package_name
    target = (pkg_dir / relative_path).resolve()

    # Reject any path that escapes the packages folder
    try:
        target.relative_to(PACKAGES_DIR.resolve())
    except ValueError:
        return {'written': False, 'path': str(target),
                'errors': ['Path escapes the packages folder — write rejected.']}

    # Refuse to overwrite without explicit flag
    if target.exists() and not overwrite:
        return {
            'written': False,
            'path': str(target),
            'errors': [
                f"File already exists: {relative_path}. "
                "Pass overwrite=True to replace it."
            ],
        }

    # Validate as the file it will be, every kind a package carries (a file
    # the validator has no schema for — media, level seeds — is written as is)
    result = _validate_text(package_name, relative_path.replace('\\', '/'), content)
    if not result['valid']:
        return {'written': False, 'path': str(target), 'errors': result['errors']}

    # Write
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')
    return {'written': True, 'path': str(target), 'errors': []}


@mcp.tool()
def delete_package(package_name: str) -> dict:
    """
    Delete an entire package directory from the packages folder.

    Irreversible outside version control — use only when replacing a package
    wholesale; a shipped package is removed in a branch, where git keeps it.

    Returns: {"deleted": bool, "path": str, "error": str | null}
    """
    pkg_dir = PACKAGES_DIR / package_name
    if pkg_dir.resolve().parent != PACKAGES_DIR.resolve():
        return {'deleted': False, 'path': str(pkg_dir), 'error': 'Not a package folder — delete rejected.'}
    if not pkg_dir.exists():
        return {'deleted': False, 'path': str(pkg_dir),
                'error': f"Package '{package_name}' not found."}

    import shutil
    shutil.rmtree(pkg_dir)
    return {'deleted': True, 'path': str(pkg_dir), 'error': None}


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    mcp.run()
