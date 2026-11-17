"""The athlete's stored profile as generate's constraints.

The builders on both clients assemble constraints from the profile themselves
(web `ConstraintsForm` + `lib/builderParams`, iOS `ProgramBuilderFlow`); a
route that generates for the athlete without a builder in front of it — the
comparison's "for you" — reads them here, the same way: level, equipment and
injuries copied, the weekly schedule laid over as `weekly_schedule` (generate
normalises it), custom injuries as `custom_injury_flags`.

What the profile does not say is left to generate's defaults and named in
`assumed`, so the answer can say what it took for granted. A training
contract's entry (the movements it expects owned, a pair of bells) is never on
the profile — the builder asks for it per program — so it is assumed met and
named too.
"""
from __future__ import annotations


def from_profile(profile: dict | None) -> tuple[dict, list[dict], list[dict]]:
    """(constraints, custom_injury_flags, assumed) for a profile blob
    (`profiles.profile_data`, camelCase keys). `assumed` entries are
    `{key, text}`."""
    profile = profile or {}
    constraints: dict = {}
    assumed: list[dict] = []

    level = profile.get('trainingLevel')
    if level:
        constraints['training_level'] = level
    else:
        assumed.append({'key': 'training_level', 'text': 'Intermediate level (not set in your profile)'})

    # An empty list is a choice (no equipment), as the builder reads it; only
    # a profile that never set it falls back to generate's default kit.
    if 'equipment' in profile and profile['equipment'] is not None:
        constraints['equipment'] = list(profile['equipment'])
    else:
        assumed.append({'key': 'equipment', 'text': 'A barbell gym with kettlebells (no equipment in your profile)'})

    custom = [f for f in profile.get('customInjuryFlags') or [] if isinstance(f, dict) and f.get('id')]
    constraints['injury_flags'] = list(dict.fromkeys(list(profile.get('injuryFlags') or [])
                                                     + [f['id'] for f in custom]))

    schedule = profile.get('weeklySchedule')
    if schedule:
        constraints['weekly_schedule'] = schedule
    else:
        assumed.append({'key': 'schedule', 'text': '5 days a week, 75 minutes a session (no schedule in your profile)'})

    return constraints, custom, assumed


def with_contract_entry(constraints: dict, contract: dict | None, exercise_names: dict) -> list[dict]:
    """Confirm what a training contract asks of the athlete's level, in place,
    unless the constraints already say; returns the `assumed` entries."""
    if not contract:
        return []
    from src.constraint_impact import contract_requirements
    asks = contract_requirements({'training_contract': contract}, constraints.get('training_level', 'intermediate'))
    out: list[dict] = []
    if asks.get('mastered_exercises') and 'mastered_exercises' not in constraints:
        constraints['mastered_exercises'] = list(asks['mastered_exercises'])
        names = ', '.join(exercise_names.get(e, e.replace('_', ' ')) for e in asks['mastered_exercises'])
        out.append({'key': 'mastered_exercises', 'text': f'You own {names} (the builder asks)'})
    if asks.get('kettlebell_count') and 'kettlebell_count' not in constraints:
        constraints['kettlebell_count'] = asks['kettlebell_count']
        out.append({'key': 'kettlebell_count', 'text': 'A pair of matching bells (the builder asks)'})
    return out
