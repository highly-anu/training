"""The package spec, as the server hands it out: docs/schemas/PACKAGE_SPEC.md.

One document says how to write a package (what a package is, each file, every
valid value, how it is checked, a worked example). Its lists are generated
from the commons, the schemas and the gate (tools/gen_package_spec.py, a push
gate), so it is current for the build that serves it. It lives in
docs/schemas because that is the part of docs/ the API image carries.
"""
from __future__ import annotations

import os
import re

PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'docs', 'schemas', 'PACKAGE_SPEC.md')


def text() -> str:
    with open(PATH, encoding='utf-8') as fh:
        return fh.read()


def sections() -> list[dict]:
    """[{number, title, text}] — the spec by its `## N. Title` sections, for a
    reader that wants one part (the valid values, the worked example)."""
    parts = re.split(r'^## (\d+)\. (.+)$', text(), flags=re.M)
    return [{'number': int(parts[i]), 'title': parts[i + 1].strip(), 'text': parts[i + 2].strip()}
            for i in range(1, len(parts) - 2, 3)]
