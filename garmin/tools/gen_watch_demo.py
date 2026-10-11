#!/usr/bin/env python3
"""Give the demo programmes their packages' screen specs.

The demo programmes (garmin/TrainingCompanionCIQ/resources/jsonData/demo_*.json)
are hand-written showcase days in the today-session shape: they carry fields the
generator does not emit yet (targetRpm, switchAtSec, restUntilHr) so a demo can
show what the watch can do. What they must not carry by hand is how a session
looks: that is its package's, so this tool resolves each session through the
same src/watch_spec.py the server's ?spec=1 uses and writes packageId, watch,
screens and each exercise's screen key in place. A demo session therefore
renders exactly as a real one built from the same archetype.

    .venv/bin/python garmin/tools/gen_watch_demo.py          # write
    .venv/bin/python garmin/tools/gen_watch_demo.py --check  # exit 1 if stale
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

from src import watch_spec  # noqa: E402

DEMO_DIR = os.path.join(ROOT, 'garmin', 'TrainingCompanionCIQ', 'resources', 'jsonData')


def annotate(session: dict) -> None:
    arch_id = session.get('archetypeId')
    pkg = watch_spec.session_package({'archetype': {'id': arch_id}})
    exercises = session.get('exercises') or []
    table, keys = watch_spec.session_screens(
        pkg, arch_id, [(e.get('slotRole') or None, e.get('slotType')) for e in exercises])
    for e, key in zip(exercises, keys):
        e['screen'] = key
    session['packageId'] = pkg
    session['watch'] = watch_spec.session_identity(pkg)
    session['screens'] = table


def render(path: str) -> str:
    with open(path) as f:
        data = json.load(f)
    for day in data.get('days') or []:
        for session in day.get('sessions') or []:
            annotate(session)
    return json.dumps(data, indent=1, ensure_ascii=False) + '\n'


def main() -> int:
    stale = []
    for path in sorted(glob.glob(os.path.join(DEMO_DIR, 'demo_*.json'))):
        text = render(path)
        with open(path) as f:
            current = f.read()
        if text == current:
            continue
        if '--check' in sys.argv:
            stale.append(os.path.relpath(path, ROOT))
        else:
            with open(path, 'w') as f:
                f.write(text)
            print(f'wrote {os.path.relpath(path, ROOT)}')
    for p in stale:
        print(f'{p} is stale: run garmin/tools/gen_watch_demo.py')
    return 1 if stale else 0


if __name__ == '__main__':
    sys.exit(main())
