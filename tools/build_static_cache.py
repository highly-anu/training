#!/usr/bin/env python
"""Answer every reference route into a directory the API serves from
(api.build_static; the Docker build runs it, STATIC_BUILD_DIR points at it).

Usage:  SUPABASE_URL= DATABASE_URL= .venv/bin/python tools/build_static_cache.py <out_dir>
Exits non-zero if a route does not answer, so a broken package fails the build.
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    os.environ.pop('STATIC_BUILD_DIR', None)   # build from the packages, never from an earlier build
    import api
    import yaml
    from src import loader
    started = time.time()
    manifest = api.build_static(sys.argv[1])
    size = sum(os.path.getsize(os.path.join(sys.argv[1], e['gz'])) for e in manifest.values())
    print(f"static build: {len(manifest)} answers, {size // 1024} KB gzipped, {time.time() - started:.1f} s, "
          f"YAML parser {'libyaml' if loader._SAFE_LOADER is not yaml.SafeLoader else 'pure Python'}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
