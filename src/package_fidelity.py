"""A package's fidelity record: data/packages/<id>/fidelity.yaml.

The machine half of the source dossier (data/packages/<id>/dossier.md): the
sources and how much of each was read, every rule they state with the data,
claim, source week or test that enforces it, what they leave open, and what
the app adds (docs/schemas/fidelity.schema.json). The scorecard's Source
criteria are computed from it rather than declared: debt is a rule nothing
enforces, a source kind is what the sources are, and anything that loosens a
grade — a phase claim, a contract, a week template, a hand-entered standard,
the lead measure, an excluded track — counts only when a rule cites it.

It lives in the package folder, so adding a package touches nothing outside
it; the package's status (records/status.yaml, src/package_records.py) is
generated from it and the recorded scorecard (`status_entry`). Nothing at
runtime reads it but Explore's philosophy page.
"""
from __future__ import annotations

import os
import re

import yaml

from src import loader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = loader._PACKAGES_DIR
CHECKS = os.path.join(ROOT, 'checks', 'python_suites.yaml')
FILE = 'fidelity.yaml'
SOURCE_WEEKS = 'source_weeks.yaml'
TESTS = 'tests'
READ = ('full', 'partial')


def record_path(pkg: str) -> str:
    return os.path.join(PACKAGES, pkg, FILE)


def dossier_path(pkg: str) -> str:
    from src import package_records
    return package_records.dossier_path(pkg)


def load(pkg: str) -> dict | None:
    path = record_path(pkg)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return yaml.safe_load(fh) or {}


def dossier(pkg: str) -> str | None:
    path = dossier_path(pkg)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def _yaml(pkg: str, name: str):
    path = os.path.join(PACKAGES, pkg, name)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return yaml.safe_load(fh)


def _workflow() -> str:
    """The commands the pre-push checks run (checks/python_suites.yaml), one
    `python <command>` a line: a cited test at the root counts as enforced only
    when it runs there; the package's own (tests/) always runs. (Until
    2026-10-26 the GitHub workflow was the list.)"""
    with open(CHECKS, encoding='utf-8') as fh:
        doc = yaml.safe_load(fh) or {}
    run = (doc.get('suites') or []) + (doc.get('exclusive') or []) + (doc.get('scratch_db') or [])
    return '\n'.join(f'python {c}' for c in run)


# ── References ───────────────────────────────────────────────────────────────

def _package_test(file: str) -> bool:
    """`tests/test_<x>.py` names a test in the package's own folder — one the
    checks find (tools/run_checks.py) — rather than one at the repository root."""
    head, base = os.path.split(file)
    return head == TESTS and base.startswith('test_') and base.endswith('.py')


def _walk(node, path: str):
    """Follow a dotted key path; a list step matches an item's id (a slot's
    role), else an index."""
    for step in path.split('.'):
        if isinstance(node, dict):
            if step not in node:
                return None, step
            node = node[step]
        elif isinstance(node, list):
            hit = next((x for x in node if isinstance(x, dict) and step in (str(x.get('id')), str(x.get('role')))),
                       None)
            if hit is None and step.isdigit() and int(step) < len(node):
                hit = node[int(step)]
            if hit is None:
                return None, step
            node = hit
        else:
            return None, step
    return node, None


def ref_error(pkg: str, ref: str, workflow: str | None = None) -> str | None:
    """Why `ref` does not resolve, or None when it does."""
    kind, _, rest = ref.partition(':')
    if kind == 'data':
        name, _, path = rest.partition('#')
        doc = _yaml(pkg, name)
        if doc is None:
            return f'{ref}: no {name} in the package'
        _, missing = _walk(doc, path)
        return f'{ref}: no {missing!r} in {name}' if missing else None
    if kind == 'checks':
        where, _, key = rest.partition('.')
        track, _, phase = where.partition('/')
        node, missing = _walk(_yaml(pkg, 'philosophy.yaml') or {}, f'tracks.{track}.phases.{phase}.checks.{key}')
        return f'{ref}: no {missing!r} in philosophy.yaml' if missing else None
    if kind == 'test':
        file, _, name = rest.partition('::')
        own = _package_test(file)
        path = os.path.join(PACKAGES, pkg, file) if own else os.path.join(ROOT, file)
        if not os.path.exists(path):
            return f'{ref}: no file {file}' + (' in the package' if own else '')
        with open(path, encoding='utf-8') as fh:
            if f'def {name}(' not in fh.read():
                return f'{ref}: {file} has no {name}'
        # The package's own tests are found by the checks (tools/run_checks.py);
        # a test at the root runs only once the registry lists it.
        if not own and f'python {file}' not in (workflow if workflow is not None else _workflow()):
            return f'{ref}: the checks do not run {file} (checks/python_suites.yaml)'
        return None
    if kind == 'week':
        weeks = _yaml(pkg, SOURCE_WEEKS) or []
        return None if any(w.get('id') == rest for w in weeks) else f'{ref}: no source week {rest!r}'
    return f'{ref}: unknown kind {kind!r}'


def _cited(rec: dict | None) -> list[tuple[str, str]]:
    """(rule or invention id, reference) for everything the record cites:
    what enforces each rule, and where each invention lives."""
    rec = rec or {}
    return [(r['id'], ref) for r in rec.get('rules') or [] for ref in r.get('enforced_by') or []] + \
           [(i['id'], ref) for i in rec.get('inventions') or [] for ref in i.get('implemented_by') or []]


def refs(rec: dict | None) -> set:
    """Every reference the record makes: a claim, contract, template or
    standard counts as declared once a rule — or, for what the app adds, an
    invention — names it."""
    return {ref for _, ref in _cited(rec)}


def ref_errors(pkg: str, rec: dict | None) -> list[str]:
    workflow = _workflow()
    return [f"{owner}: {err}" for owner, r in _cited(rec) if (err := ref_error(pkg, r, workflow))]


# ── What the record says ─────────────────────────────────────────────────────

def debt(rec: dict | None) -> list[str]:
    """Rules nothing enforces: they live only in prose."""
    return [r['id'] for r in (rec or {}).get('rules') or [] if not r.get('enforced_by')]


def sources_kind(rec: dict | None) -> str | None:
    """`primary` when a primary source was read in full; `consensus` when
    three or more were read; `secondary` when fewer; None with none read."""
    sources = (rec or {}).get('sources') or []
    if any(s['kind'] == 'primary' and s['read'] == 'full' for s in sources):
        return 'primary'
    read = [s for s in sources if s['read'] in READ]
    if len(read) >= 3:
        return 'consensus'
    return 'secondary' if read else None


def citation_errors(pkg: str, rec: dict | None, text: str | None) -> list[str]:
    """A rule that cites nothing, or only sources not read; an excluded track,
    a currency or a citation naming nothing; a rule or invention the dossier
    never names (the prose and the record read together by their ids)."""
    if rec is None:
        return []
    sources = {s['id']: s for s in rec.get('sources') or []}
    rule_ids = {r['id'] for r in rec.get('rules') or []}
    inventions = {i['id'] for i in rec.get('inventions') or []}
    out = []
    for rule in rec.get('rules') or []:
        cited = [c['source'] for c in rule.get('cites') or []]
        unknown = [c for c in cited if c not in sources]
        if unknown:
            out.append(f"{rule['id']} cites unknown source(s) {', '.join(unknown)}")
        if not any(sources.get(c, {}).get('read') in READ for c in cited):
            out.append(f"{rule['id']} rests on no source that was read")
    for track, inv in (rec.get('excluded_tracks') or {}).items():
        if inv not in inventions:
            out.append(f'excluded track {track} names {inv}, which is not an invention')
    for week in _yaml(pkg, SOURCE_WEEKS) or []:
        if week.get('rule') not in rule_ids:
            out.append(f"source week {week.get('id')} pins {week.get('rule')}, which is not a rule")
    for track, cur in (rec.get('currency') or {}).items():
        if cur['rule'] not in rule_ids | inventions:
            out.append(f"currency of {track} cites {cur['rule']}, which is neither a rule nor an invention")
    if text is not None:
        missing = sorted((rule_ids | inventions) - set(re.findall(r'\b[RI][0-9]+\b', text)),
                         key=lambda x: (x[0], int(x[1:])))
        if missing:
            out.append(f"the dossier never names {', '.join(missing)}")
    return out


def source_tests(rec: dict | None) -> list[str]:
    """The tests a rule names as what enforces it (an invention's tests pin
    the app's own design, not the source)."""
    return sorted({ref[len('test:'):] for r in (rec or {}).get('rules') or []
                   for ref in r.get('enforced_by') or [] if ref.startswith('test:')})


def tests_in_ci(pkg: str, rec: dict | None) -> int:
    workflow = _workflow()
    return sum(1 for t in source_tests(rec) if not ref_error(pkg, f'test:{t}', workflow))


# How a reference names what it cites — the one spelling, for the graders
# (src/package_eval.py) as for the record. `refs` is refs(record).

def _under(refs: set, prefix: str) -> bool:
    """A reference to `prefix` or to something inside it (`tracks.a` is not
    inside `tracks.a_b`)."""
    return any(r == prefix or r.startswith(prefix + '.') for r in refs)


def contract_cited(refs: set, track: str) -> bool:
    return _under(refs, f'data:training_contract.yaml#tracks.{track}')


def template_cited(refs: set, track: str, phase: str) -> bool:
    return _under(refs, f'data:philosophy.yaml#tracks.{track}.phases.{phase}.week_templates')


def claim_ref(track: str, phase: str, key: str) -> str:
    return f'checks:{track}/{phase}.{key}'


def claim_cited(refs: set, track: str, phase: str, key: str) -> bool:
    return claim_ref(track, phase, key) in refs


def manual_cited(rec: dict | None, standard: str) -> bool:
    return f'data:analytics.yaml#benchmarks.{standard}' in refs(rec)


def invented_track(rec: dict | None, track: str) -> str | None:
    """The invention a whole track is (its `implemented_by` names the track
    itself), or None: such a track has no source to be read against."""
    whole = {f'data:training_contract.yaml#tracks.{track}', f'data:philosophy.yaml#tracks.{track}'}
    return next((i['id'] for i in (rec or {}).get('inventions') or []
                 if whole & set(i.get('implemented_by') or [])), None)


def currency(rec: dict | None, track: str) -> tuple[str | None, str | None]:
    """(the entry, the rule it rests on). An invention stands in for the rule
    only on a track that is itself that invention — elsewhere the currency is
    the method's word or nothing."""
    cur = ((rec or {}).get('currency') or {}).get(track) or {}
    rule_ids = {r['id'] for r in (rec or {}).get('rules') or []}
    rule = cur.get('rule')
    if rule in rule_ids or (rule and rule == invented_track(rec, track)):
        return cur.get('entry'), rule
    return cur.get('entry'), None


# ── Status ───────────────────────────────────────────────────────────────────
# A package's records/status.yaml (src/package_records.py), generated by
# tools/evaluate_packages.py --update-baseline — the legend is
# docs/package-fidelity/README.md's ("The status").

def status_entry(pkg: str, rec: dict | None, earned: str) -> dict:
    rec = rec or {}
    rules = {r['id']: r['text'] for r in rec.get('rules') or []}
    entry: dict = {'status': earned}
    if rec.get('shape'):
        entry['shape'] = rec['shape']
    if dossier(pkg) is not None:
        entry['dossier'] = os.path.basename(dossier_path(pkg))   # in the package's folder
    if rec.get('sources'):
        entry['sources_kind'] = sources_kind(rec)
        entry['debt'] = [f"{rid}: {rules[rid]}" for rid in debt(rec)]
    if rec.get('currency'):
        entry['currency'] = {t: c['entry'] for t, c in rec['currency'].items()}
    if rec.get('excluded_tracks'):
        inv = {i['id']: i['text'] for i in rec.get('inventions') or []}
        entry['excluded_tracks'] = {t: f"{i}: {inv.get(i, '')}" for t, i in rec['excluded_tracks'].items()}
    if source_tests(rec):
        entry['source_tests'] = source_tests(rec)
    if rec.get('inventions'):
        entry['inventions'] = [f"{i['id']}: {i['text']}" for i in rec['inventions']]
    reviews = sorted(rec.get('reviews') or [], key=lambda r: r['date'])
    if reviews:
        entry['last_review'] = {r['kind']: r['date'] for r in reviews}
    if rec.get('next'):
        entry['next'] = rec['next']
    return entry
