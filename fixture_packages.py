"""The shipped packages plus the test fixtures in test_packages/, as one
packages folder (`TRAINING_PACKAGES_DIR`, src/loader.py).

The modality scheduler's tests need a package with strength work, equipment
gaps, a phase test and deloads; every shipped package of that kind now runs
as a training contract or as its source's week templates. `block_fixture` is
Gym Jones as authored before its plans were transcribed as written.

Call `use()` before anything imports `src`: some modules keep the folder
they found at import.

    import fixture_packages
    fixture_packages.use()
    from src import ...
"""
from __future__ import annotations

import atexit
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(ROOT, 'test_packages')


def use() -> str:
    if any(name == 'src' or name.startswith('src.') for name in sys.modules):
        raise RuntimeError('fixture_packages.use() must run before src is imported')
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    for base in (os.path.join(ROOT, 'data', 'packages'), FIXTURES):
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name)
            if os.path.isdir(path):
                shutil.copytree(path, os.path.join(folder, name))
    os.environ['TRAINING_PACKAGES_DIR'] = folder
    return folder
