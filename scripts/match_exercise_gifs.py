"""Fuzzy-match our exercises against free-exercise-db and produce a match report.

Usage:
    python scripts/match_exercise_gifs.py [--min-score 0.6] [--force-download]

Outputs data/external_db_cache/match_report.yaml with three sections:
  confirmed  — score >= 0.9 (auto-accept)
  review     — score 0.6–0.89 (human check)
  no_match   — score < 0.6

After reviewing the `review` section, run write_gif_urls_to_manifest.py to
fold confirmed + approved entries into data/exercise_media.yaml.
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.request

import yaml

_ROOT          = os.path.join(os.path.dirname(__file__), '..')
_CACHE_DIR     = os.path.join(_ROOT, 'data', 'external_db_cache')
_PACKAGES_DIR  = os.path.join(_ROOT, 'data', 'packages')
_MANIFEST_PATH = os.path.join(_ROOT, 'data', 'exercise_media.yaml')
_REPORT_PATH   = os.path.join(_CACHE_DIR, 'match_report.yaml')

FREE_DB_URL = (
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json'
)
FREE_DB_IMAGE_BASE = (
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises'
)

SKIP_CATEGORIES = {'aerobic'}


# ── normalisation ─────────────────────────────────────────────────────────────

def _normalise(text: str) -> str:
    text = text.lower()
    text = re.sub(r'[^a-z0-9 ]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def _tokens(text: str) -> set[str]:
    return set(_normalise(text).split())


def _score(a: str, b: str) -> float:
    """Token-set similarity in [0, 1]."""
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    inter = ta & tb
    # Jaccard on intersection vs union, but bias toward exact subset matches
    jaccard = len(inter) / len(ta | tb)
    # bonus if one is a full subset of the other (handles "Bench Press" vs "Barbell Bench Press")
    subset_bonus = 0.15 if ta <= tb or tb <= ta else 0.0
    return min(1.0, jaccard + subset_bonus)


# ── data loading ──────────────────────────────────────────────────────────────

def _load_yaml(path: str):
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def load_our_exercises() -> list[dict]:
    seen: set[str] = set()
    result: list[dict] = []
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'exercises.yaml'))):
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            if ex['id'] not in seen:
                seen.add(ex['id'])
                result.append({'id': ex['id'], 'name': ex.get('name', ''), 'category': ex.get('category', '')})
    return result


def fetch_free_db(force: bool = False) -> list[dict]:
    os.makedirs(_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(_CACHE_DIR, 'free_exercise_db.json')
    if not force and os.path.exists(cache_path):
        print(f'Using cached free-exercise-db at {cache_path}')
    else:
        print(f'Downloading free-exercise-db from {FREE_DB_URL} ...')
        with urllib.request.urlopen(FREE_DB_URL, timeout=30) as resp:
            data = resp.read()
        with open(cache_path, 'wb') as f:
            f.write(data)
        print(f'Saved to {cache_path}')
    with open(cache_path, encoding='utf-8') as f:
        return json.load(f)


# ── matching ──────────────────────────────────────────────────────────────────

def build_image_url(external: dict) -> str | None:
    """Build a raw GitHub URL for the first image of an external exercise."""
    images = external.get('images', [])
    if not images:
        return None
    # images are stored as relative paths like "Abs/AbWheel/0.jpg"
    img = images[0]
    return f'{FREE_DB_IMAGE_BASE}/{img}'


def match_exercises(
    ours: list[dict],
    external: list[dict],
    min_score: float,
) -> dict:
    confirmed: dict = {}
    review: dict = {}
    no_match: list = []

    for ex in ours:
        if ex['category'] in SKIP_CATEGORIES:
            continue

        best_score = 0.0
        best_ext = None
        for ext in external:
            s = _score(ex['name'], ext.get('name', ''))
            if s > best_score:
                best_score = s
                best_ext = ext

        entry = {
            'our_name': ex['name'],
            'category': ex['category'],
        }
        if best_ext:
            entry['external_name'] = best_ext.get('name', '')
            entry['external_id']   = best_ext.get('id', '')
            entry['score']         = round(best_score, 3)
            img_url = build_image_url(best_ext)
            if img_url:
                entry['image_url'] = img_url

        if best_score >= 0.9:
            confirmed[ex['id']] = entry
        elif best_score >= min_score:
            review[ex['id']] = entry
        else:
            no_match.append({'id': ex['id'], **entry})

    return {'confirmed': confirmed, 'review': review, 'no_match': no_match}


# ── report ────────────────────────────────────────────────────────────────────

class _NoAliasDumper(yaml.Dumper):
    def ignore_aliases(self, data):
        return True


def save_report(report: dict) -> None:
    os.makedirs(_CACHE_DIR, exist_ok=True)
    with open(_REPORT_PATH, 'w', encoding='utf-8') as f:
        yaml.dump(report, f, Dumper=_NoAliasDumper, allow_unicode=True,
                  default_flow_style=False, sort_keys=False)
    print(f'Report written to {_REPORT_PATH}')


def print_summary(report: dict) -> None:
    c = len(report['confirmed'])
    r = len(report['review'])
    n = len(report['no_match'])
    total = c + r + n
    print(f'\nMatch results ({total} exercises processed):')
    print(f'  confirmed  (>= 0.90): {c}')
    print(f'  review     (>= min):  {r}   -- edit match_report.yaml then run write_gif_urls_to_manifest.py')
    print(f'  no_match   (< min):   {n}   -- need custom animation (Lottie/SVG)')


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--min-score', type=float, default=0.6,
                        help='Minimum score for review tier (default: 0.6)')
    parser.add_argument('--force-download', action='store_true',
                        help='Re-download free-exercise-db even if cached')
    args = parser.parse_args()

    ours     = load_our_exercises()
    external = fetch_free_db(force=args.force_download)
    print(f'Matching {len(ours)} our exercises against {len(external)} external exercises ...')

    report = match_exercises(ours, external, min_score=args.min_score)
    save_report(report)
    print_summary(report)


if __name__ == '__main__':
    sys.exit(main())
