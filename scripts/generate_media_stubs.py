"""Generate empty stub entries in data/exercise_media.yaml for all unique exercises.

Run once to bootstrap the manifest; safe to re-run — only adds missing IDs.
"""
import glob
import os
import sys
import yaml

_ROOT = os.path.join(os.path.dirname(__file__), '..')
_PACKAGES_DIR = os.path.join(_ROOT, 'data', 'packages')
_MANIFEST_PATH = os.path.join(_ROOT, 'data', 'exercise_media.yaml')

STUB = {
    'description': '',
    'cue_points': [],
    'muscles_primary': [],
    'muscles_secondary': [],
    'common_errors': [],
    'coaching_focus': '',
    'animation': {'type': 'none'},
    'muscle_diagram': {'highlight_primary': [], 'highlight_secondary': []},
}


def _load_yaml(path: str):
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def collect_unique_exercises() -> list[dict]:
    seen: set[str] = set()
    exercises: list[dict] = []
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'exercises.yaml'))):
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            if ex['id'] not in seen:
                seen.add(ex['id'])
                exercises.append({'id': ex['id'], 'name': ex.get('name', ''), 'category': ex.get('category', '')})
    return exercises


def load_manifest() -> dict:
    if not os.path.exists(_MANIFEST_PATH):
        return {}
    data = _load_yaml(_MANIFEST_PATH)
    return data if isinstance(data, dict) else {}


class _NoAliasDumper(yaml.Dumper):
    """Prevent pyyaml from emitting anchors/aliases for repeated equal objects."""
    def ignore_aliases(self, data):
        return True


def save_manifest(manifest: dict) -> None:
    with open(_MANIFEST_PATH, 'w', encoding='utf-8') as f:
        yaml.dump(manifest, f, Dumper=_NoAliasDumper, allow_unicode=True,
                  default_flow_style=False, sort_keys=True)


def main() -> None:
    exercises = collect_unique_exercises()
    manifest = load_manifest()

    added = 0
    for ex in exercises:
        if ex['id'] not in manifest:
            manifest[ex['id']] = dict(STUB)
            added += 1

    save_manifest(manifest)

    total = len(exercises)
    existing = total - added
    print(f"exercise_media.yaml: {total} total | {existing} already present | {added} stubs added")
    print(f"Manifest written to {os.path.abspath(_MANIFEST_PATH)}")

    # Print category breakdown for reference
    categories: dict[str, int] = {}
    for ex in exercises:
        cat = ex['category']
        categories[cat] = categories.get(cat, 0) + 1
    print("\nCategory breakdown:")
    for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
        print(f"  {cat:20s} {count}")


if __name__ == '__main__':
    sys.exit(main())
