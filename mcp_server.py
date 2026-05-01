#!/usr/bin/env python3
"""MCP server for the training system package authoring workflow.

Lets AI agents create data/packages/ without reading documentation.
Query valid values → get templates → write files → validate → fix → done.

Setup (Claude Desktop):
  Windows: %APPDATA%\\Claude\\claude_desktop_config.json
  {
    "mcpServers": {
      "training": {
        "command": "python",
        "args": ["C:/Users/65469/programming/training/mcp_server.py"]
      }
    }
  }

Setup (Claude Code CLI):
  claude mcp add --transport stdio training -- python C:/Users/65469/programming/training/mcp_server.py
"""

import json
import sys
import yaml
import jsonschema
from pathlib import Path
from typing import Any

# ── Path setup ────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'src'))
import loader  # noqa: E402

from mcp.server.fastmcp import FastMCP  # noqa: E402

# ── Constants ─────────────────────────────────────────────────────────────────
SCHEMAS_DIR  = ROOT / 'docs' / 'schemas'
PACKAGES_DIR = ROOT / 'data' / 'packages'

VALID_MODALITIES = [
    'max_strength', 'strength_endurance', 'relative_strength',
    'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning',
    'power', 'mobility', 'movement_skill', 'durability',
    'combat_sport', 'rehab',
]

SCHEMA_FILES = {
    'philosophy':   'philosophy.schema.json',
    'framework':    'framework.schema.json',
    'archetype':    'archetype.schema.json',
    'exercise':     'exercise.schema.json',
    'goal_profile': 'goal_profile.schema.json',
}

mcp = FastMCP("training")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _load_schema(entity_type: str) -> dict:
    filename = SCHEMA_FILES.get(entity_type)
    if not filename:
        raise ValueError(f"Unknown entity_type '{entity_type}'. Valid: {list(SCHEMA_FILES)}")
    with open(SCHEMAS_DIR / filename, encoding='utf-8') as f:
        return json.load(f)


def _schema_errors(schema: dict, data: dict) -> list[dict]:
    """Return list of {path, message} dicts for all validation errors."""
    errors = []
    for err in jsonschema.Draft7Validator(schema).iter_errors(data):
        path = ' -> '.join(str(p) for p in err.absolute_path) or '(root)'
        errors.append({'path': path, 'message': err.message})
    return errors


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

primary_framework_id: {slug}_framework
                         # Default framework ID for this philosophy

framework_groups:
  - id: default
    name: "{title} Program"
    type: alternatives
    frameworks:
      - {slug}_framework
                         # For philosophies with one framework or multiple alternatives (pick one style).
                         # Example alternatives group:
                         # - id: training_styles
                         #   name: "Training Approaches"
                         #   type: alternatives
                         #   frameworks:
                         #     - {slug}_concurrent
                         #     - {slug}_block_periodization
                         #
                         # For phased programs (sequential phases), use type: sequential:
                         # - id: full_program
                         #   name: "Full {title} Program"
                         #   type: sequential
                         #   frameworks:
                         #     - {slug}_transition_phase
                         #     - {slug}_base_phase
                         #     - {slug}_specific_phase
                         #     - {slug}_taper_phase
                         #   canonical_phase_sequence:
                         #     - phase: transition
                         #       weeks: 4
                         #       framework_id: {slug}_transition_phase
                         #       focus: "Recovery and movement prep"
                         #     - phase: base
                         #       weeks: 16
                         #       framework_id: {slug}_base_phase
                         #       focus: "Foundation building"
                         #     - phase: specific
                         #       weeks: 8
                         #       framework_id: {slug}_specific_phase
                         #       focus: "Sport-specific adaptation"
                         #     - phase: taper
                         #       weeks: 3
                         #       framework_id: {slug}_taper_phase
                         #       focus: "Peak and recover for event"

sources: []
# notes: ""
"""

    framework_yaml = f"""\
id: {slug}_framework
name: "{title} Framework"
source_philosophy: {slug}

goals_served:
  - mobility             # goal profile IDs or modality IDs

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
                         # carries | sandbag | mobility | skill | rehab | gym_jones
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
def validate_yaml(entity_type: str, yaml_content: str) -> dict:
    """
    Validate a YAML string against the JSON schema for entity_type.

    entity_type: philosophy | framework | archetype | exercise | goal_profile

    For exercises, pass the full file content (with top-level 'exercises:' key)
    and each item will be validated individually.

    Returns: {"valid": bool, "errors": [{"path": str, "message": str}]}
    """
    try:
        data = yaml.safe_load(yaml_content)
    except yaml.YAMLError as e:
        return {'valid': False, 'errors': [{'path': '(yaml parse)', 'message': str(e)}]}

    if not isinstance(data, dict):
        return {'valid': False, 'errors': [{'path': '(root)', 'message': 'YAML must be a mapping, not a list or scalar.'}]}

    try:
        schema = _load_schema(entity_type)
    except ValueError as e:
        return {'valid': False, 'errors': [{'path': '(setup)', 'message': str(e)}]}

    # Exercise files wrap items in {exercises: [...]}
    if entity_type == 'exercise' and 'exercises' in data:
        all_errors = []
        for i, ex in enumerate(data['exercises']):
            for err in _schema_errors(schema, ex):
                err['path'] = f'exercises[{i}] -> {err["path"]}'
                all_errors.append(err)
        return {'valid': len(all_errors) == 0, 'errors': all_errors}

    errors = _schema_errors(schema, data)
    return {'valid': len(errors) == 0, 'errors': errors}


@mcp.tool()
def validate_package(package_path: str) -> dict:
    """
    Validate all files in a package directory.

    package_path: package name ('yoga') or path ('data/packages/yoga').

    Checks:
      - philosophy.yaml: schema conformance
      - frameworks/*.yaml: schema conformance, source_philosophy cross-ref
      - archetypes/**/*.yaml: schema conformance, ID uniqueness across packages
      - exercises.yaml: schema conformance per item, ID uniqueness across packages

    Returns: {"valid": bool, "files": {filename: [error strings]}}
    """
    pkg_dir = PACKAGES_DIR / package_path if '/' not in package_path and '\\' not in package_path \
              else ROOT / package_path
    if not pkg_dir.exists():
        return {'valid': False, 'files': {'(setup)': [f'Directory not found: {pkg_dir}']}}

    file_errors: dict[str, list[str]] = {}

    def add_err(filename: str, msg: str) -> None:
        file_errors.setdefault(filename, []).append(msg)

    # Collect IDs from all OTHER installed packages (for conflict detection)
    pkg_name = pkg_dir.name
    other_arch_ids: set[str] = set()
    for a in loader.load_all_archetypes():
        if a.get('_package') != pkg_name:
            other_arch_ids.add(a['id'])

    ex_global, ex_by_pkg = loader.load_all_exercises()
    other_exercise_ids: set[str] = {
        ex_id for pkg_id, pkg_exs in ex_by_pkg.items()
        if pkg_id != pkg_name
        for ex_id in pkg_exs
    }

    existing_phil_ids = {p['id'] for p in loader.load_philosophies()}

    # ── philosophy.yaml ──────────────────────────────────────────────────────
    phil_file = pkg_dir / 'philosophy.yaml'
    own_phil_id: str | None = None
    if not phil_file.exists():
        add_err('philosophy.yaml', 'File not found — required.')
    else:
        try:
            phil_data = yaml.safe_load(phil_file.read_text(encoding='utf-8'))
            own_phil_id = phil_data.get('id')
            for err in _schema_errors(_load_schema('philosophy'), phil_data):
                add_err('philosophy.yaml', f"{err['path']}: {err['message']}")
        except Exception as e:
            add_err('philosophy.yaml', f'Parse error: {e}')

    # ── frameworks/*.yaml ────────────────────────────────────────────────────
    for fw_path in sorted(pkg_dir.glob('frameworks/*.yaml')):
        rel = f'frameworks/{fw_path.name}'
        try:
            fw_data = yaml.safe_load(fw_path.read_text(encoding='utf-8'))
            for err in _schema_errors(_load_schema('framework'), fw_data):
                add_err(rel, f"{err['path']}: {err['message']}")
            sp = fw_data.get('source_philosophy')
            if sp and sp not in existing_phil_ids and sp != own_phil_id:
                add_err(rel, f"source_philosophy '{sp}' does not match any installed philosophy ID.")
        except Exception as e:
            add_err(rel, f'Parse error: {e}')

    # ── archetypes/**/*.yaml ─────────────────────────────────────────────────
    seen_arch_ids: set[str] = set()
    for arch_path in sorted(pkg_dir.glob('archetypes/**/*.yaml')):
        rel = arch_path.relative_to(pkg_dir).as_posix()
        try:
            arch_data = yaml.safe_load(arch_path.read_text(encoding='utf-8'))
            for err in _schema_errors(_load_schema('archetype'), arch_data):
                add_err(rel, f"{err['path']}: {err['message']}")
            arch_id = arch_data.get('id')
            if arch_id in other_arch_ids:
                add_err(rel, f"Archetype ID '{arch_id}' already exists in another package.")
            if arch_id in seen_arch_ids:
                add_err(rel, f"Archetype ID '{arch_id}' is duplicated within this package.")
            seen_arch_ids.add(arch_id)
        except Exception as e:
            add_err(rel, f'Parse error: {e}')

    # ── exercises.yaml ───────────────────────────────────────────────────────
    ex_file = pkg_dir / 'exercises.yaml'
    if ex_file.exists():
        try:
            ex_data = yaml.safe_load(ex_file.read_text(encoding='utf-8'))
            schema = _load_schema('exercise')
            seen_ex_ids: set[str] = set()
            for i, ex in enumerate(ex_data.get('exercises', [])):
                for err in _schema_errors(schema, ex):
                    add_err('exercises.yaml', f"exercises[{i}] -> {err['path']}: {err['message']}")
                ex_id = ex.get('id')
                if ex_id in other_exercise_ids:
                    add_err('exercises.yaml', f"Exercise ID '{ex_id}' already exists in another package.")
                if ex_id in seen_ex_ids:
                    add_err('exercises.yaml', f"Exercise ID '{ex_id}' is duplicated within this file.")
                seen_ex_ids.add(ex_id)
        except Exception as e:
            add_err('exercises.yaml', f'Parse error: {e}')

    # ── Modality coverage check ──────────────────────────────────────────────
    # Warn if a modality appears in philosophy scope but has no archetype.
    if phil_file.exists() and own_phil_id:
        try:
            phil_data = yaml.safe_load(phil_file.read_text(encoding='utf-8'))
            scope_modalities = set(phil_data.get('scope', []))
            arch_modalities = set()
            for arch_path in pkg_dir.glob('archetypes/**/*.yaml'):
                try:
                    arch_data = yaml.safe_load(arch_path.read_text(encoding='utf-8'))
                    if arch_data.get('modality'):
                        arch_modalities.add(arch_data['modality'])
                except Exception:
                    pass
            uncovered = scope_modalities - arch_modalities
            for mod in sorted(uncovered):
                add_err('philosophy.yaml',
                        f"Warning: modality '{mod}' is in scope but has no archetype in this package.")
        except Exception:
            pass

    valid = not any(file_errors.values())
    return {'valid': valid, 'files': file_errors}


@mcp.tool()
def check_id_available(entity_type: str, proposed_id: str) -> dict:
    """
    Check whether a proposed ID is already in use across all installed packages.

    entity_type: philosophy | framework | archetype | exercise
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
    else:
        return {'available': False, 'conflict': f"Unknown entity_type '{entity_type}'. Valid: philosophy | framework | archetype | exercise"}

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

    # Reject any path that escapes data/packages/
    try:
        target.relative_to(PACKAGES_DIR.resolve())
    except ValueError:
        return {'written': False, 'path': str(target),
                'errors': ['Path escapes data/packages/ — write rejected.']}

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

    # Infer entity type from path for validation
    name = target.name
    rel = relative_path.replace('\\', '/')
    if name == 'philosophy.yaml':
        entity_type = 'philosophy'
    elif 'frameworks/' in rel:
        entity_type = 'framework'
    elif 'archetypes/' in rel:
        entity_type = 'archetype'
    elif name == 'exercises.yaml':
        entity_type = 'exercise'
    else:
        entity_type = None

    # Validate before writing
    if entity_type:
        result = validate_yaml(entity_type, content)
        if not result['valid']:
            return {'written': False, 'path': str(target), 'errors': result['errors']}

    # Write
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')
    return {'written': True, 'path': str(target), 'errors': []}


@mcp.tool()
def delete_package(package_name: str) -> dict:
    """
    Delete an entire package directory from data/packages/.

    This is irreversible — use only when replacing a package wholesale.
    The legacy backup at data/legacy/ is unaffected.

    Returns: {"deleted": bool, "path": str, "error": str | null}
    """
    pkg_dir = PACKAGES_DIR / package_name
    if not pkg_dir.exists():
        return {'deleted': False, 'path': str(pkg_dir),
                'error': f"Package '{package_name}' not found."}

    import shutil
    shutil.rmtree(pkg_dir)
    return {'deleted': True, 'path': str(pkg_dir), 'error': None}


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    mcp.run()
