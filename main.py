#!/usr/bin/env python3
"""CLI entry point for the training program generator.

Usage examples:
    python main.py --goal general_gpp --days 4 --level intermediate
    python main.py --goal alpine_climbing --days 5 --time 90 --phase build --week 3
    python main.py --goal general_gpp --days 3 --equipment kettlebell,pull_up_bar,open_space
    python main.py --goal alpine_climbing --injuries shoulder_impingement --days 5
    python main.py --goal alpine_climbing --event-date 2026-08-15 --days 5
"""
import argparse
import sys
import os
from datetime import date

sys.path.insert(0, os.path.dirname(__file__))

from src.generator import generate
from src.loader import load_goal
from src.phase_calendar import compute_phase_from_date, build_remaining_schedule


_EQUIPMENT_PRESETS = {
    'barbell_gym':     'barbell,rack,plates,kettlebell,dumbbell,pull_up_bar,rings,'
                       'rower,bike,box,jump_rope,open_space',
    'home_kb_only':    'kettlebell,pull_up_bar,open_space',
    'bodyweight_only': 'pull_up_bar,open_space',
    'outdoor':         'ruck_pack,open_space',
    'home_barbell':    'barbell,rack,plates,kettlebell,pull_up_bar,open_space',
}

_DEFAULT_EQUIPMENT = 'barbell,rack,plates,kettlebell,pull_up_bar,ruck_pack,open_space'


def _parse_list(s: str) -> list[str]:
    return [x.strip() for x in s.split(',') if x.strip()]


def main():
    parser = argparse.ArgumentParser(
        description='Generate a training program from a goal profile and constraints.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        '--goal', required=True,
        help='Goal profile ID. Choices: alpine_climbing, sof_operator, bjj_competitor, '
             'general_gpp, ultra_endurance, max_strength_focus, injury_rehab',
    )
    parser.add_argument('--days',    type=int, default=5,
                        help='Training days per week (1–7, default 5)')
    parser.add_argument('--time',    type=int, default=75,
                        help='Session length in minutes (default 75)')
    parser.add_argument('--level',   default='intermediate',
                        choices=['novice', 'intermediate', 'advanced', 'elite'],
                        help='Training level (default intermediate)')
    parser.add_argument('--phase',   default='base',
                        choices=['base', 'build', 'peak', 'taper', 'deload',
                                 'maintenance', 'rehab', 'post_op'],
                        help='Training phase (default base)')
    parser.add_argument('--week',    type=int, default=1,
                        help='Starting week number in the phase (default 1)')
    parser.add_argument('--weeks',   type=int, default=4,
                        help='Number of weeks to generate (default 4)')
    parser.add_argument(
        '--equipment', default=_DEFAULT_EQUIPMENT,
        help=f'Comma-separated equipment IDs, or a preset name: '
             f'{list(_EQUIPMENT_PRESETS.keys())}. '
             f'Default: {_DEFAULT_EQUIPMENT}',
    )
    parser.add_argument('--injuries', default='',
                        help='Comma-separated injury flag IDs (optional). '
                             'e.g. shoulder_impingement,lumbar_disc')
    parser.add_argument('--fatigue', default='normal',
                        choices=['fresh', 'normal', 'accumulated', 'overreached'],
                        help='Current fatigue state (default normal)')
    parser.add_argument(
        '--event-date', default=None, metavar='YYYY-MM-DD',
        help='Target event date. Automatically sets --phase and --week by counting '
             'backward through the goal\'s phase_sequence. Overrides --phase/--week.',
    )
    parser.add_argument(
        '--full', action='store_true',
        help='When used with --event-date, generate all remaining weeks from today '
             'to the event, spanning phase boundaries automatically.',
    )

    args = parser.parse_args()

    # Resolve equipment preset or parse list
    equip_str = _EQUIPMENT_PRESETS.get(args.equipment, args.equipment)
    equipment = _parse_list(equip_str)

    constraints = {
        'equipment':            equipment,
        'days_per_week':        args.days,
        'session_time_minutes': args.time,
        'training_level':       args.level,
        'training_phase':       args.phase,
        'periodization_week':   args.week,
        'fatigue_state':        args.fatigue,
        'injury_flags':         _parse_list(args.injuries),
    }

    # --event-date: compute phase/week from the calendar and override constraints
    if args.event_date:
        try:
            event_date = date.fromisoformat(args.event_date)
        except ValueError:
            print(f'Error: --event-date must be YYYY-MM-DD, got: {args.event_date}',
                  file=sys.stderr)
            sys.exit(1)

        goal_data = load_goal(args.goal)
        calendar = compute_phase_from_date(goal_data, event_date)

        constraints['training_phase']     = calendar['phase']
        constraints['periodization_week'] = calendar['week_in_phase']
        constraints['event_calendar']     = calendar

        print(f'\n  {calendar["message"]}\n')

    try:
        phase_schedule = None
        if args.full and args.event_date:
            if 'event_calendar' not in constraints:
                print('Error: --full requires --event-date', file=sys.stderr)
                sys.exit(1)
            phase_schedule = build_remaining_schedule(constraints['event_calendar'])

        output = generate(
            goal_id=args.goal,
            constraints=constraints,
            num_weeks=args.weeks,
            phase_schedule=phase_schedule,
        )
        print(output)
    except FileNotFoundError as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f'Generation error: {e}', file=sys.stderr)
        raise


if __name__ == '__main__':
    main()
