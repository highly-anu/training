"""Write confirmed GIF/image URLs from match_report.yaml into exercise_media.yaml.

Run after reviewing data/external_db_cache/match_report.yaml:
  1. Move any 'review' entries you approve into 'confirmed'
  2. Run this script

It only writes exercises whose animation.type is still 'none' — never overwrites
entries that already have a GIF or Lottie animation set.

Usage:
    python scripts/write_gif_urls_to_manifest.py [--dry-run]
"""
import argparse
import os
import sys

import yaml

_ROOT          = os.path.join(os.path.dirname(__file__), '..')
_REPORT_PATH   = os.path.join(_ROOT, 'data', 'external_db_cache', 'match_report.yaml')
_MANIFEST_PATH = os.path.join(_ROOT, 'data', 'exercise_media.yaml')


class _NoAliasDumper(yaml.Dumper):
    def ignore_aliases(self, data):
        return True


def _load_yaml(path: str):
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true',
                        help='Print what would change without writing')
    args = parser.parse_args()

    if not os.path.exists(_REPORT_PATH):
        print(f'ERROR: {_REPORT_PATH} not found — run match_exercise_gifs.py first')
        sys.exit(1)

    report   = _load_yaml(_REPORT_PATH)
    manifest = _load_yaml(_MANIFEST_PATH)

    confirmed: dict = report.get('confirmed', {})
    updated = 0
    skipped = 0

    for ex_id, entry in confirmed.items():
        if ex_id not in manifest:
            print(f'  WARN: {ex_id} not in manifest — run generate_media_stubs.py first')
            continue

        current_type = manifest[ex_id].get('animation', {}).get('type', 'none')
        if current_type != 'none':
            skipped += 1
            continue

        image_url = entry.get('image_url')
        if not image_url:
            continue

        manifest[ex_id]['animation'] = {
            'type':       'gif',
            'gif_url':    image_url,
            'gif_alt':    entry.get('our_name', ex_id),
            'gif_source': 'free_exercise_db',
            'external_id': entry.get('external_id', ''),
        }

        if args.dry_run:
            print(f'  [dry-run] {ex_id} → {image_url}')
        updated += 1

    print(f'\nConfirmed entries: {len(confirmed)}')
    print(f'  Updated: {updated}')
    print(f'  Skipped (animation already set): {skipped}')

    if args.dry_run:
        print('Dry run — no changes written.')
        return

    with open(_MANIFEST_PATH, 'w', encoding='utf-8') as f:
        yaml.dump(manifest, f, Dumper=_NoAliasDumper, allow_unicode=True,
                  default_flow_style=False, sort_keys=True)
    print(f'Manifest updated: {_MANIFEST_PATH}')


if __name__ == '__main__':
    sys.exit(main())
