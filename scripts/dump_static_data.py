#!/usr/bin/env python3
"""Dump the standards to JSON for frontend bundling.

Run from the repo root before `npm run build`:
    python scripts/dump_static_data.py

Output goes to frontend/src/data/static/benchmarks.json, imported directly by
frontend/src/api/benchmarks.ts as the offline fallback for `GET /api/standards`.

It writes exactly what the endpoint serves (`benchmarks_data.to_client`, male
tables). It used to carry a third copy of the loader that drifted from the
server's: male values only, the raw Cell domain (`hips`, which no modality
colour knows) and the old Cell level mapping.

This script used to dump exercises, modalities, frameworks, philosophies, goals
and constraints too, reading the top-level data/<type>/ directories. The vertical
package migration deleted those directories, so the script could not run and the
dumps sat frozen at a pre-migration snapshot. Nothing imported them, so they are
gone; that data is served from the API, which reads the packages directly.
"""
from __future__ import annotations

import json
import os
import sys

# Make src/ importable when run from repo root
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.analytics import benchmarks_data  # noqa: E402

_OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'frontend', 'src', 'data', 'static'
)


def _write(filename: str, data: object) -> None:
    path = os.path.join(_OUT_DIR, filename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'  wrote {path} ({os.path.getsize(path) // 1024} KB)')


def main() -> None:
    os.makedirs(_OUT_DIR, exist_ok=True)
    print('Dumping standards...')
    _write('benchmarks.json', [benchmarks_data.to_client(b) for b in benchmarks_data.load_benchmarks()])
    print('Done.')


if __name__ == '__main__':
    main()
