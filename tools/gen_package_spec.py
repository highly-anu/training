#!/usr/bin/env python
"""Write the generated parts of docs/schemas/PACKAGE_SPEC.md — the one document
that says how to write a package (docs/roadmap.md 20.8).

The spec's prose is written by hand; what it lists is not. Every block between
`<!-- gen:NAME -->` and `<!-- /gen:NAME -->` is written here from the one place
each fact lives: the files a package holds (src/portability.FILES and what an
athlete's package may carry, src/package_store.py), the gate's stages
(src/package_gate.py), every valid value (the commons and the schemas' enums),
the limits, and the worked example — test_packages/scratch_minimal, file for
file, which test_package_gate.py holds to every gate.

    .venv/bin/python tools/gen_package_spec.py            # rewrite the blocks
    .venv/bin/python tools/gen_package_spec.py --check    # fail when one is stale

`--check` is a push gate (checks/python_suites.yaml): a value added to the
commons, or a change to the example package, without this file run, fails.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

import yaml  # noqa: E402

from src import equipment, loader, package_gate, package_store, portability, recovery_regions  # noqa: E402

SPEC = os.path.join(ROOT, 'docs', 'schemas', 'PACKAGE_SPEC.md')
EXAMPLE = os.path.join(ROOT, 'test_packages', 'scratch_minimal')
SCHEMAS = os.path.join(ROOT, 'docs', 'schemas')

# The schema that checks each file of a package.
_SCHEMA_OF = {'philosophy': 'philosophy', 'frameworks': 'framework', 'archetypes': 'archetype', 'exercises': 'exercise',
              'analytics': 'analytics', 'watch': 'watch', 'contract': 'training_contract', 'standards': 'standards',
              'vocabulary': 'vocabulary', 'fidelity': 'fidelity', 'source_weeks': 'source_weeks'}
_WHAT = {
    'philosophy': 'The method: its beliefs, scope and tracks, each an ordered list of its own phases.',
    'frameworks': 'One file per framework, named `<framework id>.yaml`: how a week of a phase is built.',
    'archetypes': 'One file per session shape, in any subfolders: the slots a session is made of.',
    'exercises': '`exercises:` — the movements the package owns, with its own loads.',
    'media': 'Demo links per exercise id.',
    'level_seeds': 'What an athlete of each level is assumed to know already (unlocks `requires`).',
    'analytics': 'What progress means for the method. Without it a spec is synthesised from the frameworks.',
    'watch': 'How its sessions look on the watches. Without it, the slot types\' default screens.',
    'contract': 'Per track, modules the engine places as written, with earned progress (the advanced shape).',
    'standards': 'Standards the method tests that the commons lack.',
    'vocabulary': 'Modalities, movement patterns and equipment the package adds for itself.',
    'fidelity': 'Its sources, rules and inventions (a package that ships in the repository).',
    'source_weeks': "The source's own example weeks, compared with generation (repository packages).",
    'tests': 'Its own tests (repository packages).',
}


def _schema(name: str) -> dict:
    with open(os.path.join(SCHEMAS, f'{name}.schema.json'), encoding='utf-8') as fh:
        return json.load(fh)


def _yaml(*parts: str):
    with open(os.path.join(ROOT, 'data', *parts), encoding='utf-8') as fh:
        return yaml.safe_load(fh)


def _code(values) -> str:
    return ', '.join(f'`{v}`' for v in values)


def block_files() -> str:
    allowed = package_store._TOP_LEVEL
    rows = ['| File | Required | Schema | An athlete\'s package may carry it | What it is |', '|---|---|---|---|---|']
    for fid, path, required in portability.FILES:
        shown = f'`{path}/`' if fid in ('frameworks', 'archetypes', 'tests') else f'`{path}`'
        schema = f'`{_SCHEMA_OF[fid]}.schema.json`' if fid in _SCHEMA_OF else '—'
        mine = 'yes' if path in allowed or fid in ('frameworks', 'archetypes') else 'no'
        rows.append(f"| {shown} | {'yes' if required else 'no'} | {schema} | {mine} | {_WHAT[fid]} |")
    return '\n'.join(rows)


def block_gate() -> str:
    what = {
        'files': "A `philosophy.yaml` whose `id` is the folder's name.",
        'schema': 'Every file against its schema and the checks beside it (section 6).',
        'ids': "The files a package needs; no id another package or the commons declare; every modality, movement "
               "pattern, equipment, phase kind, standard and watch template it names is the commons', its own "
               "(`vocabulary.yaml`, `standards.yaml`) or one it borrows; for an athlete's own package, the owner's "
               'prefix on every id it declares.',
        'smoke': 'Every phase of every track validates and generates one week on the framework it names — an '
                 'intermediate with every implement, at the framework\'s ideal days and minutes — and a phase that '
                 'tests places every test.',
        'provenance': 'Nothing in those programs comes from outside the package and what it borrows.',
    }
    rows = ['| Stage | Passes when |', '|---|---|'] + [f'| `{s}` | {what[s]} |' for s in package_gate.STAGES]
    return '\n'.join(rows)


def block_limits() -> str:
    return '\n'.join([
        f'- at most **{package_store.MAX_FILES} files** and **{package_store.MAX_BYTES // 1024} KB** of YAML in a '
        f'package, and **{package_store.MAX_PACKAGES} packages** an athlete;',
        '- only the files the table above marks, as lower-case paths: ' + _code(sorted(package_store._TOP_LEVEL))
        + ', `frameworks/<id>.yaml`, `archetypes/<…>/<id>.yaml` (up to three subfolders);',
        '- the package id is 3–64 characters of `a-z`, `0-9` and `_`, starting with a letter;',
        "- every id the package declares for itself — the package, frameworks, archetypes, standards and their "
        "categories, modalities, movement patterns, equipment — starts with the owner's prefix, `u<8 hex>_` "
        '(`GET /api/packages` says it). An exercise id either carries it or is an exercise a shipped package '
        'declares, which the package may re-declare with its own loads.',
    ])


def block_values() -> str:
    archetype, exercise, philosophy, framework = (_schema(n) for n in ('archetype', 'exercise', 'philosophy', 'framework'))
    slot = archetype['properties']['slots']['items']['properties']
    with loader.overlay(None):   # the commons', whoever runs this
        modalities = loader.load_all_modalities()
        from src.analytics import families
        fams = families.families()
    regions = recovery_regions.config()
    aliases = _yaml('commons', 'movement_patterns.yaml')['aliases']
    flags = _yaml('commons', 'constraints', 'injury_flags.yaml')['injury_flags']
    kinds = loader.load_phase_kinds()
    levels = _yaml('commons', 'training_levels.yaml')
    watch = json.load(open(os.path.join(ROOT, 'data', 'commons', 'watch_vocabulary.json'), encoding='utf-8'))
    from src.analytics import vocabulary as analytics_vocabulary
    primitives = sorted(analytics_vocabulary.to_client().get('primitives') or {})
    out = []

    out += ['**Modalities** (`data/commons/modalities/`; a package adds its own in `vocabulary.yaml`):', '',
            '| id | name | family | recovery cost | progression model |', '|---|---|---|---|---|']
    for mid, mod in sorted(modalities.items(), key=lambda kv: (kv[1].get('display') or {}).get('order', 99)):
        fam = next((f for f, ms in fams.items() if mid in ms), 'other')
        out.append(f"| `{mid}` | {mod.get('name')} | {fam} | {mod.get('recovery_cost')} | "
                   f"`{mod.get('progression_model', 'linear_load')}` |")
    out += ['', f'**Modality families** (`vocabulary.yaml` `family`): {_code(fams)}.', '',
            f"**Phase kinds** (a phase's `kind`, an archetype's `applicable_phases`): {_code(kinds)}.", '',
            '**Training levels**: ' + _code(lv['id'] for lv in levels['levels']) + '.' if isinstance(levels, dict)
            and isinstance(levels.get('levels'), list) else
            '**Training levels**: ' + _code(archetype['properties']['training_levels']['items']['enum']) + '.', '',
            f"**Slot types** (`slot_type`): {_code(slot['slot_type']['enum'])}.", '',
            f"**Intensities** (a slot's `intensity`): {_code(slot['intensity']['enum'])}.", '',
            f"**Progression models** (a framework's or modality's `progression_model`): "
            f"{_code(framework['properties']['progression_model']['enum'])}.", '',
            f"**Archetype categories**: {_code(archetype['properties']['category']['enum'])}.", '',
            f"**Exercise categories**: {_code(exercise['properties']['category']['enum'])}. "
            f"**Effort**: {_code(exercise['properties']['effort']['enum'])}.", '',
            f"**Philosophy `intensity_model`**: {_code(philosophy['properties']['intensity_model']['enum'])}.", '',
            f"**Philosophy `progression_philosophy`**: {_code(philosophy['properties']['progression_philosophy']['enum'])}.", '',
            '**Equipment** (`data/commons/constraints/equipment.yaml`; an exercise may also say `none`; a package '
            'adds its own in `vocabulary.yaml`): ' + _code(e['id'] for e in equipment.commons_items()) + '.', '',
            f"**Body regions** (a package pattern's `regions`): {_code(regions['regions'])}.", '',
            '**Movement patterns that load a region** (`data/commons/recovery_regions.yaml`): '
            + _code(regions['patterns']) + '.', '',
            f"**Movement patterns that load nothing**: {_code(regions.get('unloaded') or [])}.", '',
            "**Slot-filter aliases** (a slot's `exercise_filter.movement_pattern` may name one; anything else is "
            'matched as a pattern directly): ' + ', '.join(
                f"`{name}` ({a['mode']}: {', '.join(a['patterns'])})" for name, a in aliases.items()) + '.', '',
            '**Injury flags** (an exercise\'s `contraindicated_with`, a package pattern\'s `excluded_by`): '
            + _code(f['id'] for f in flags) + '.', '',
            f"**Analytics primitives** (`analytics.yaml` `primitive`): {_code(primitives)}.", '',
            f"**Watch templates** (`watch.yaml` `template`): {_code(watch.get('templates') or {})}."]
    return '\n'.join(line for line in out if line is not None)


def block_example() -> str:
    out = []
    for path in sorted(glob.glob(os.path.join(EXAMPLE, '**', '*.yaml'), recursive=True),
                       key=lambda p: (os.path.relpath(p, EXAMPLE).count(os.sep), os.path.relpath(p, EXAMPLE))):
        rel = os.path.relpath(path, EXAMPLE).replace(os.sep, '/')
        with open(path, encoding='utf-8') as fh:
            out += [f'`{rel}`', '', '```yaml', fh.read().rstrip('\n'), '```', '']
    return '\n'.join(out).rstrip('\n')


BLOCKS = {'files': block_files, 'gate': block_gate, 'limits': block_limits, 'values': block_values,
          'example': block_example}


def render(text: str) -> str:
    for name, build in BLOCKS.items():
        pattern = re.compile(rf'(<!-- gen:{name} -->\n).*?(<!-- /gen:{name} -->)', re.S)
        if not pattern.search(text):
            raise SystemExit(f'{os.path.relpath(SPEC, ROOT)}: no <!-- gen:{name} --> block')
        body = build()
        text = pattern.sub(lambda m, body=body: m.group(1) + body + '\n' + m.group(2), text)
    return text


def main() -> int:
    with open(SPEC, encoding='utf-8') as fh:
        current = fh.read()
    wanted = render(current)
    if '--check' in sys.argv:
        if wanted != current:
            print(f'{os.path.relpath(SPEC, ROOT)} is stale: run .venv/bin/python tools/gen_package_spec.py')
            return 1
        print(f'{os.path.relpath(SPEC, ROOT)} is current.')
        return 0
    if wanted != current:
        with open(SPEC, 'w', encoding='utf-8') as fh:
            fh.write(wanted)
        print(f'wrote {os.path.relpath(SPEC, ROOT)}')
    else:
        print(f'{os.path.relpath(SPEC, ROOT)} is current.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
