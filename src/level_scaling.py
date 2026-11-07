"""A prescription written for one level, done at another (docs/logic/levels.md).

A package writes its sessions as its source does — CrossFit's Rx, Fran's
21-15-9 at 43 kg — and a track that declares `authored_level` says which
athlete that is. An athlete below it does a share of it, per dimension:

  load      a fixed weight the slot gives as `load_kg` (the Rx, by sex); a
            % of 1RM or of bodyweight is already the athlete's own and is
            never touched
  volume    sets, reps, a rep scheme, reps a round
  time      minutes and seconds of work, an AMRAP's minutes, a time cap
  distance  metres

The share is the track's own `level_scaling[level]` where its source says
(CrossFit's Level 1 guide: half), else the commons'
(data/commons/training_levels.yaml `scaling`, relative to the authored
level), never more than written. A track without `authored_level` is not
scaled at all: the framework is opt-in per track, so a package converts in
its own change. Nothing here names a package.
"""
from __future__ import annotations

import math

from . import levels

DIMENSIONS = ('load', 'volume', 'time', 'distance')

# The load fields each dimension scales. A count is rounded half up and never
# goes under one; seconds to 5 s, metres to 10 m, kilograms to 2.5 kg.
_VOLUME_INT = ('sets', 'reps', 'reps_per_round')
_TIME_MIN = ('duration_minutes', 'time_minutes')
_TIME_SEC = ('hold_seconds', 'work_sec')


def policy_for(track: dict | None) -> dict | None:
    """A track's level policy, or None when the track has not opted in."""
    if not track or not track.get('authored_level'):
        return None
    return {'authored_level': track['authored_level'],
            'level_scaling': dict(track.get('level_scaling') or {})}


def factors(level: str | None, policy: dict | None) -> dict | None:
    """Each dimension's share of the written prescription at `level`, and
    where it came from: `({dim: share}, {dim: 'track' | 'commons'})`. None when
    nothing scales (no policy, or the athlete is at or above the authored
    level)."""
    if not policy or level not in levels.order():
        return None
    authored = policy['authored_level']
    if levels.rank(level) >= levels.rank(authored):
        return None
    own = (policy.get('level_scaling') or {}).get(level) or {}
    at, top = levels.scaling(level), levels.scaling(authored)
    shares, sources = {}, {}
    for dim in DIMENSIONS:
        if dim in own:
            shares[dim], sources[dim] = min(1.0, float(own[dim])), 'track'
        else:
            shares[dim], sources[dim] = min(1.0, at[dim] / top[dim]), 'commons'
    return shares, sources


def _count(n, share: float) -> int:
    return max(1, math.floor(n * share + 0.5))


def _seconds(n, share: float) -> int:
    return max(5, int(5 * math.floor(n * share / 5 + 0.5)))


def _kg(kg: float, step: float = 2.5) -> float:
    return max(step, round(kg / step) * step)


def rx_kg(slot: dict, sex: str | None) -> float | None:
    """The slot's written fixed weight for this athlete: `load_kg` as a
    number, or `{male, female}` (male when the sex is not known, as the
    standards' tables)."""
    written = slot.get('load_kg')
    if isinstance(written, dict):
        written = written.get('female') if sex == 'female' and written.get('female') else written.get('male')
    return float(written) if isinstance(written, (int, float)) else None


def scale_prescription(load: dict, slot: dict, level: str | None, policy: dict | None,
                       sex: str | None = None, kg_step: float = 2.5) -> dict:
    """The load at the athlete's level. Unchanged without a policy; at or
    above the authored level only a slot's `load_kg` becomes its weight.
    Below it every scaled field keeps its written value under `rx`, and
    `level_scaled` says from which level and how much, for the clients.
    `kg_step` is what a weight rounds to (4 kg for a kettlebell, which
    comes in those sizes)."""
    if not policy or not isinstance(load, dict):
        return load
    out = dict(load)
    rx: dict = {}
    written_kg = rx_kg(slot, sex)
    found = factors(level, policy)
    if found is None:
        if written_kg is not None and 'weight_kg' not in out:
            out['weight_kg'] = written_kg
        return out
    shares, sources = found

    def scale(key, fn, share):
        value = out.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or share >= 1.0:
            return
        new = fn(value, share)
        if new != value:
            rx[key] = value
            out[key] = new

    for key in _VOLUME_INT:
        if key == 'sets' and (out.get('sets') or 0) <= 1:
            continue
        scale(key, _count, shares['volume'])
    if isinstance(out.get('rep_scheme'), list) and shares['volume'] < 1.0:
        scheme = [_count(n, shares['volume']) if isinstance(n, (int, float)) else n for n in out['rep_scheme']]
        if scheme != out['rep_scheme']:
            rx['rep_scheme'] = list(out['rep_scheme'])
            out['rep_scheme'] = scheme
    for key in _TIME_MIN:
        scale(key, _count, shares['time'])
    for key in _TIME_SEC:
        scale(key, _seconds, shares['time'])
    scale('distance_m', lambda v, s: max(10, int(10 * math.floor(v * s / 10 + 0.5))), shares['distance'])
    scale('distance_km', lambda v, s: round(v * s, 2), shares['distance'])

    if written_kg is not None:
        weight = _kg(written_kg * shares['load'], kg_step)
        out['weight_kg'] = weight
        if weight != written_kg:
            rx['weight_kg'] = written_kg
            if slot.get('load'):
                out['load_note'] = f"{weight:g} kg · Rx {slot['load']}"

    if rx:
        out['rx'] = rx
        out['level_scaled'] = {'level': level, 'from': policy['authored_level'],
                               'shares': {d: round(shares[d], 3) for d in DIMENSIONS},
                               'sources': sources}
    return out
