#!/usr/bin/env python3
"""Generate the watch icon set.

Authoring rules, driven by the Apache Batik build bundled in monkeybrains.jar
(a 2020 build, so SVG 1.1 only):

  * explicit width/height/viewBox on the root <svg>
  * basic shapes and flat <path> only; fills as XML attributes, never CSS
  * no <style> blocks, CSS variables, filters, masks, clipPath, <text> or <use>
  * pure white on transparent -- the shape lives in the alpha channel, which
    makes drawBitmap2(:tintColor) correct under either tint interpretation
    (multiply-luminance or replace-RGB-keep-alpha)
  * every <bitmap> carries scope="application": without it these link into the
    64KB glance build and it dies with an out-of-memory error

Geometry is bolder than a web icon set: these render at ~54px on a wrist, in
motion, outdoors. Minimum stroke weight is 7 units in a 96 unit box (~4px).
"""
import os, textwrap

VB = 96
OUT = os.path.join(os.path.dirname(__file__), '..', 'resources', 'drawables', 'icons')

W = '#FFFFFF'

def r(x, y, w, h, rx=None, rot=None):
    a = f'<rect x="{x}" y="{y}" width="{w}" height="{h}"'
    if rx: a += f' rx="{rx}"'
    a += f' fill="{W}"'
    if rot: a += f' transform="rotate({rot[0]} {rot[1]} {rot[2]})"'
    return a + '/>'

def c(cx, cy, rad):
    return f'<circle cx="{cx}" cy="{cy}" r="{rad}" fill="{W}"/>'

def poly(pts):
    s = ' '.join(f'{x},{y}' for x, y in pts)
    return f'<polygon points="{s}" fill="{W}"/>'

def path(d):
    return f'<path fill="{W}" d="{d}"/>'

def ring(cx, cy, rad, wdt):
    """Annulus via even-odd fill -- two subpaths in one path element."""
    o, i = rad, rad - wdt
    return (f'<path fill="{W}" fill-rule="evenodd" d="'
            f'M{cx-o},{cy} a{o},{o} 0 1,0 {2*o},0 a{o},{o} 0 1,0 {-2*o},0 Z '
            f'M{cx-i},{cy} a{i},{i} 0 1,0 {2*i},0 a{i},{i} 0 1,0 {-2*i},0 Z"/>')

# A barbell: plates at both ends of a bar, used by several lifting icons.
def barbell(y, x0=6, x1=90, bar=9, plate_h=30):
    return [
        r(x0 + 8, y, x1 - x0 - 16, bar),
        r(x0, y - (plate_h - bar) // 2, 9, plate_h, rx=3),
        r(x1 - 9, y - (plate_h - bar) // 2, 9, plate_h, rx=3),
    ]

ICONS = {}

# ── movement patterns ────────────────────────────────────────────────────────

ICONS['squat'] = barbell(24) + [
    c(48, 48, 9),                       # head under the bar
    r(38, 58, 20, 12, rx=4),            # torso
    r(30, 70, 12, 18, rx=5, rot=(20, 36, 79)),   # thigh out
    r(54, 70, 12, 18, rx=5, rot=(-20, 60, 79)),
]

ICONS['hip_hinge'] = [
    c(24, 26, 9),                       # head, pitched forward
    path('M30 30 L70 44 L66 56 L26 42 Z'),       # hinged torso
    r(62, 52, 12, 32, rx=5),            # rear leg
    *barbell(70, x0=14, x1=62, bar=8, plate_h=26),
]

ICONS['vertical_push'] = barbell(12, x0=10, x1=86, bar=8, plate_h=26) + [
    r(28, 20, 10, 24, rx=4, rot=(12, 33, 32)),   # arms overhead
    r(58, 20, 10, 24, rx=4, rot=(-12, 63, 32)),
    c(48, 50, 10),
    r(38, 62, 20, 26, rx=6),
]

ICONS['horizontal_push'] = [
    r(10, 44, 76, 10, rx=5),            # bench
    c(26, 30, 9),
    r(36, 26, 34, 12, rx=6),            # torso on the bench
    r(52, 8, 10, 22, rx=4),             # pressing arm
    *barbell(6, x0=34, x1=86, bar=7, plate_h=22),
]

ICONS['vertical_pull'] = [
    r(10, 10, 76, 9, rx=4),             # bar overhead
    r(34, 18, 9, 20, rx=4),             # arms up
    r(53, 18, 9, 20, rx=4),
    c(48, 44, 10),
    r(38, 56, 20, 20, rx=6),
    r(40, 76, 7, 14, rx=3), r(49, 76, 7, 14, rx=3),
]

ICONS['horizontal_pull'] = [
    c(22, 30, 9),
    r(30, 34, 30, 12, rx=5),            # torso
    r(56, 30, 24, 9, rx=4),             # pulling arm
    *barbell(52, x0=48, x1=90, bar=8, plate_h=26),
    r(28, 58, 12, 30, rx=5),
]

ICONS['loaded_carry'] = [
    c(48, 16, 9),
    r(40, 28, 16, 26, rx=5),            # torso
    r(30, 30, 8, 22, rx=3), r(58, 30, 8, 22, rx=3),   # arms down
    r(22, 52, 24, 14, rx=4), r(50, 52, 24, 14, rx=4), # two loads
    r(40, 56, 7, 32, rx=3), r(49, 56, 7, 32, rx=3),
]

ICONS['farmer_carry'] = [
    c(48, 14, 8),
    r(41, 24, 14, 24, rx=5),
    r(20, 46, 20, 12, rx=4), r(56, 46, 20, 12, rx=4),
    r(26, 40, 8, 10, rx=3), r(62, 40, 8, 10, rx=3),   # handles
    r(38, 50, 8, 20, rx=3, rot=(14, 42, 60)),
    r(50, 50, 8, 20, rx=3, rot=(-14, 54, 60)),
    r(30, 76, 16, 8, rx=3), r(50, 76, 16, 8, rx=3),
]

ICONS['rack_carry'] = [
    c(48, 16, 9),
    r(24, 32, 48, 13, rx=5),            # load racked at the shoulders
    r(38, 46, 20, 24, rx=6),
    r(38, 70, 8, 18, rx=3), r(50, 70, 8, 18, rx=3),
]

ICONS['rotation'] = [
    ring(48, 50, 30, 9),
    poly([(48, 6), (70, 22), (48, 34)]),         # arrowhead closing the loop
    c(48, 50, 9),
]

ICONS['locomotion'] = [
    c(60, 16, 9),
    r(38, 28, 26, 11, rx=5, rot=(-18, 51, 33)),  # leaning torso
    r(28, 30, 18, 8, rx=4, rot=(24, 37, 34)),    # trailing arm
    r(60, 26, 18, 8, rx=4, rot=(-28, 69, 30)),   # leading arm
    r(46, 44, 11, 26, rx=5, rot=(16, 51, 57)),
    r(30, 60, 11, 26, rx=5, rot=(-32, 35, 73)),
    r(58, 62, 22, 9, rx=4, rot=(12, 69, 66)),
]

ICONS['ballistic'] = [
    # A swing arc with the bell at the top of the float.
    path('M14 84 A46 46 0 0 1 82 42 l-11 6 A34 34 0 0 0 26 84 Z'),
    r(64, 14, 16, 8, rx=4),             # handle
    c(72, 34, 15),                      # bell
]

ICONS['olympic_lift'] = barbell(10, x0=8, x1=88, bar=9, plate_h=30) + [
    r(26, 18, 9, 26, rx=4, rot=(10, 30, 31)),
    r(61, 18, 9, 26, rx=4, rot=(-10, 65, 31)),
    c(48, 50, 9),
    r(39, 60, 18, 14, rx=5),
    r(28, 74, 18, 9, rx=4, rot=(16, 37, 78)),
    r(50, 74, 18, 9, rx=4, rot=(-16, 59, 78)),
]

ICONS['isometric'] = [
    # Plank: a held horizontal line, with a timer ring.
    r(8, 52, 64, 10, rx=5),
    c(18, 40, 9),
    r(26, 42, 34, 10, rx=5, rot=(8, 43, 47)),
    r(58, 58, 10, 26, rx=4, rot=(-10, 63, 71)),
    ring(74, 26, 18, 7),
    r(72, 14, 5, 14, rx=2),
]

ICONS['aerobic_monostructural'] = [
    # Pulse trace inside a ring.
    ring(48, 48, 38, 8),
    path('M16 48 h14 l7 -18 l10 36 l8 -22 l6 4 h19 v8 H58 l-8 -5 l-11 28 l-9 -37 '
         'l-4 10 H16 Z'),
]

ICONS['hip_flexion'] = [
    c(30, 18, 9),
    r(22, 30, 16, 26, rx=5),            # torso
    r(36, 40, 30, 11, rx=5, rot=(-16, 51, 45)),  # raised thigh
    r(60, 30, 11, 24, rx=5, rot=(20, 65, 42)),   # shin
    r(22, 58, 12, 30, rx=5),            # standing leg
]

ICONS['knee_extension'] = [
    r(12, 24, 34, 12, rx=5),            # seat back
    r(12, 36, 44, 12, rx=5),            # seat
    c(26, 14, 9),
    r(50, 40, 12, 26, rx=5),            # thigh
    r(56, 54, 30, 11, rx=5, rot=(-20, 71, 59)),  # extending shin
    c(84, 44, 9),                       # pad
]

ICONS['step_up'] = [
    r(10, 60, 44, 28, rx=4),            # box
    c(68, 16, 9),
    r(60, 28, 16, 22, rx=5),
    r(46, 46, 26, 11, rx=5, rot=(18, 59, 51)),   # lead leg onto the box
    r(64, 54, 11, 30, rx=5),
]

# ── slot types ───────────────────────────────────────────────────────────────

ICONS['slot_sets_reps'] = [
    r(8, 38, 12, 20, rx=4), r(22, 30, 12, 36, rx=5),
    r(34, 42, 28, 12),
    r(62, 30, 12, 36, rx=5), r(76, 38, 12, 20, rx=4),
]
ICONS['slot_time_domain'] = [ring(48, 52, 36, 9), r(44, 26, 8, 30, rx=4), r(48, 48, 24, 8, rx=4)]
ICONS['slot_emom'] = [
    ring(48, 54, 32, 9), r(36, 8, 24, 10, rx=4), r(44, 14, 8, 12),
    r(44, 30, 8, 26, rx=4),
]
ICONS['slot_amrap'] = [
    path('M48 14 a38 38 0 1 1 -27 11 l9 9 a25 25 0 1 0 18 -7 Z'),
    poly([(42, 4), (68, 18), (42, 32)]),
]
ICONS['slot_amrap_movement'] = [
    r(14, 26, 58, 10, rx=5), poly([(64, 16), (88, 31), (64, 46)]),
    r(24, 60, 58, 10, rx=5), poly([(32, 50), (8, 65), (32, 80)]),
]
ICONS['slot_for_time'] = [
    r(16, 8, 9, 80, rx=4),
    path('M28 12 h52 l-12 16 l12 16 H28 Z'),
]
ICONS['slot_distance'] = [
    path('M30 6 a22 22 0 0 1 22 22 c0 16 -22 38 -22 38 S8 44 8 28 A22 22 0 0 1 30 6 Z'),
    c(30, 28, 9), c(72, 70, 16),
    path('M40 70 h16 v10 H40 Z'),
]
ICONS['slot_static_hold'] = [r(26, 16, 15, 64, rx=6), r(55, 16, 15, 64, rx=6)]
ICONS['slot_skill_practice'] = [
    path('M48 6 l9 26 l26 9 l-26 9 l-9 26 l-9 -26 l-26 -9 l26 -9 Z'),
    path('M78 58 l5 13 l13 5 l-13 5 l-5 13 l-5 -13 l-13 -5 l13 -5 Z'),
]

# ── archetype categories ─────────────────────────────────────────────────────

ICONS['cat_strength'] = ICONS['slot_sets_reps']
ICONS['cat_conditioning'] = ICONS['aerobic_monostructural']
ICONS['cat_kettlebell'] = [
    path('M34 30 a14 14 0 0 1 28 0 h-10 a4 4 0 0 0 -8 0 Z'),
    path('M48 28 c22 0 32 18 32 34 a32 32 0 0 1 -64 0 c0 -16 10 -34 32 -34 Z'),
]
ICONS['cat_gpp_durability'] = [
    r(30, 18, 36, 14, rx=5),            # pack
    path('M22 30 h52 a10 10 0 0 1 10 10 v34 a10 10 0 0 1 -10 10 H22 a10 10 0 0 1 -10 -10 '
         'V40 a10 10 0 0 1 10 -10 Z'),
    r(34, 50, 28, 10, rx=4),
]
ICONS['cat_movement_skill'] = [
    c(48, 14, 9),
    r(10, 32, 76, 10, rx=5, rot=(-12, 48, 37)),
    r(42, 40, 12, 22, rx=5),
    r(28, 60, 12, 28, rx=5, rot=(18, 34, 74)),
    r(56, 60, 12, 28, rx=5, rot=(-18, 62, 74)),
]
ICONS['cat_combat_sport'] = [
    path('M20 30 a16 16 0 0 1 16 -16 h30 a18 18 0 0 1 18 18 v20 a20 20 0 0 1 -20 20 H38 '
         'a18 18 0 0 1 -18 -18 Z'),
    r(26, 60, 46, 14, rx=6),
]
ICONS['cat_recovery'] = [
    ring(48, 48, 36, 9),
    path('M30 44 h14 l-14 20 h16 v9 H24 v-8 l14 -20 H30 Z'),
    path('M54 34 h16 l-16 22 h18 v9 H46 v-8 l15 -21 H54 Z'),
]

# ── UI glyphs ────────────────────────────────────────────────────────────────

ICONS['ui_heart'] = [path(
    'M48 84 C20 64 8 50 8 34 A22 22 0 0 1 48 22 A22 22 0 0 1 88 34 C88 50 76 64 48 84 Z')]
ICONS['ui_check'] = [path('M12 50 l10 -11 l16 16 l36 -37 l10 11 l-46 47 Z')]
ICONS['ui_chevron_left'] = [path('M62 10 l12 12 l-26 26 l26 26 l-12 12 l-38 -38 Z')]
ICONS['ui_chevron_right'] = [path('M34 10 l-12 12 l26 26 l-26 26 l12 12 l38 -38 Z')]
ICONS['ui_pack'] = ICONS['cat_gpp_durability']
ICONS['ui_lap'] = [
    ring(48, 48, 34, 9),
    r(44, 8, 8, 22, rx=3),
    poly([(48, 6), (72, 20), (48, 34)]),
]
ICONS['ui_side_left'] = [
    c(34, 18, 10), r(24, 30, 20, 30, rx=6), r(24, 62, 8, 26, rx=3), r(36, 62, 8, 26, rx=3),
    poly([(84, 32), (60, 48), (84, 64)]),
]
ICONS['ui_side_right'] = [
    c(62, 18, 10), r(52, 30, 20, 30, rx=6), r(52, 62, 8, 26, rx=3), r(64, 62, 8, 26, rx=3),
    poly([(12, 32), (36, 48), (12, 64)]),
]
ICONS['ui_deload'] = [
    r(10, 42, 76, 12, rx=6),
    poly([(48, 90), (22, 62), (74, 62)]),
    r(28, 14, 40, 12, rx=6),
]
ICONS['ui_flame'] = [path(
    'M48 6 c14 18 6 24 16 32 c6 5 10 -2 10 -8 c10 14 10 26 4 36 a30 30 0 0 1 -56 -14 '
    'c0 -16 12 -22 18 -32 c5 -8 6 -10 8 -14 Z')]
ICONS['ui_sync'] = [
    path('M48 12 a36 36 0 0 1 34 24 l-13 5 A22 22 0 0 0 48 26 Z'),
    path('M48 84 a36 36 0 0 1 -34 -24 l13 -5 A22 22 0 0 0 48 70 Z'),
    poly([(74, 4), (94, 24), (66, 30)]),
    poly([(22, 92), (2, 72), (30, 66)]),
]
ICONS['ui_generic'] = [ring(48, 48, 32, 9), c(48, 48, 10)]


def write(name, shapes):
    body = '\n  '.join(shapes)
    svg = (f'<?xml version="1.0" encoding="UTF-8"?>\n'
           f'<svg xmlns="http://www.w3.org/2000/svg" width="{VB}" height="{VB}" '
           f'viewBox="0 0 {VB} {VB}">\n  {body}\n</svg>\n')
    sub = 'cat' if (name.startswith('slot_') or name.startswith('cat_')
                    or name.startswith('ui_')) else 'pattern'
    d = os.path.join(OUT, sub)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + '.svg'), 'w') as f:
        f.write(svg)
    return sub


def main():
    counts = {}
    entries = []
    for name, shapes in ICONS.items():
        sub = write(name, shapes)
        counts[sub] = counts.get(sub, 0) + 1
        rez = 'Ic' + ''.join(p.capitalize() for p in name.split('_'))
        # Hero size for movement patterns, chip size for slot/category/UI glyphs.
        pct = '13%' if sub == 'pattern' else '6.7%'
        entries.append((rez, f'icons/{sub}/{name}.svg', pct))
    print(f'wrote {sum(counts.values())} icons {counts}')
    return entries


if __name__ == '__main__':
    for rez, fn, pct in main():
        print(f'  {rez:26s} {fn:40s} {pct}')
