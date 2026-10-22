#!/usr/bin/env python3
"""Draw the session workout icons (data/commons/workout_icons.json) from
tools/icons/workout_glyphs.py.

    python3 tools/icons/gen_workout_icons.py --preview /tmp/icons.png [--html /tmp/icons.html]

--preview renders the review sheet: every icon in each modality colour, at a
Garmin hero's size, a list row's and a header's, light and dark
(tools/icons/render_icons.swift). --html writes the same as a page.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import workout_glyphs  # noqa: E402

VOCAB = os.path.join(ROOT, 'data', 'commons', 'workout_icons.json')

# The modality colours a session icon is drawn in (frontend/src/lib/modalityColors.ts).
PREVIEW_COLORS = [
    ('power', '#eab308'), ('movement_skill', '#14b8a6'), ('strength_endurance', '#f97316'),
    ('max_strength', '#ef4444'), ('mixed_modal', '#8b5cf6'),
]
PREVIEW_SIZES = [24, 40, 72]   # px: a list row's glyph, a Garmin hero, a header


def vocabulary() -> dict:
    with open(VOCAB, encoding='utf-8') as f:
        return json.load(f)


def icon_paths() -> list[dict]:
    """[{id, label, d}] in the vocabulary's order; every id must have a glyph."""
    out = []
    for icon in vocabulary()['icons']:
        make = workout_glyphs.GLYPHS.get(icon['id'])
        if make is None:
            raise SystemExit(f"no glyph for '{icon['id']}' in tools/icons/workout_glyphs.py")
        out.append({'id': icon['id'], 'label': icon['label'], 'd': workout_glyphs.normalized_d(make())})
    return out


def preview_png(out: str) -> None:
    sheet = {'icons': icon_paths(), 'sizes': PREVIEW_SIZES,
             'colors': [{'name': n, 'hex': h} for n, h in PREVIEW_COLORS]}
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
        json.dump(sheet, f)
    subprocess.run(['swift', os.path.join(HERE, 'render_icons.swift'), f.name, out], check=True)
    os.unlink(f.name)


def preview_html(out: str) -> None:
    icons = icon_paths()
    rows = []
    for icon in icons:
        cells = []
        for name, hexv in PREVIEW_COLORS:
            for s in PREVIEW_SIZES:
                cells.append(f'<svg viewBox="0 0 100 100" width="{s}" height="{s}" style="color:{hexv}" '
                             f'role="img" aria-label="{icon["label"]}"><path fill="currentColor" d="{icon["d"]}"/></svg>')
        rows.append(f'<tr><th><code>{icon["id"]}</code><br><small>{icon["label"]}</small></th>'
                    f'<td>{"".join(cells)}</td></tr>')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('<!doctype html><meta charset="utf-8"><title>Workout icons</title>'
                '<style>body{font:14px system-ui;margin:16px}td svg{margin:6px}th{text-align:left;padding-right:16px}'
                '.dark{background:#12141a;color:#eee}</style>'
                f'<table>{"".join(rows)}</table><table class="dark">{"".join(rows)}</table>')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--preview', metavar='PNG')
    ap.add_argument('--html', metavar='HTML')
    args = ap.parse_args()
    if args.preview:
        preview_png(args.preview)
    if args.html:
        preview_html(args.html)
    return 0


if __name__ == '__main__':
    sys.exit(main())
