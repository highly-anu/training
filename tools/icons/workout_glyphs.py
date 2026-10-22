"""The session workout icons' glyphs (data/commons/workout_icons.json).

One family: the app's `kettlebell` (ios/tools/make_kettlebell_symbol.py),
reduced, plus one motion mark that names the lift — a pendulum for the swing,
an arc overhead for the snatch, a hooked arrow for the clean and press, a
stepped floor-to-standing line for the get-up, a down-and-up arrow for the
squat. Objects and marks only, never a human figure (ios/docs/custom-icons.md
§2). Drawn on the 100 grid, y down, every solid clockwise; nonzero fill makes
overlapping solids one shape.

tools/icons/gen_workout_icons.py writes them for every client.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'ios', 'tools'))
from symbol_template import Glyph  # noqa: E402
import make_kettlebell_symbol as _kb  # noqa: E402

BAND = 10.0      # a motion mark's width (custom-icons.md: strokes 9–10 units)


# ── geometry helpers ─────────────────────────────────────────────────────────

def _map(glyph: Glyph, f) -> Glyph:
    """`glyph` with every point passed through `f` (exact for an affine f)."""
    out = Glyph()
    for sp in glyph.subpaths:
        out.subpaths.append({'start': f(sp['start']),
                             'segs': [tuple(f(p) for p in s) for s in sp['segs']]})
    return out


def _signed_area(sp) -> float:
    pts = [sp['start']] + [s[-1] for s in sp['segs']]
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts))) / 2


def _reversed(sp) -> dict:
    """The same subpath walked the other way."""
    pts = [sp['start']] + [s[-1] for s in sp['segs']]
    segs = []
    for i in range(len(sp['segs']) - 1, -1, -1):
        s, end = sp['segs'][i], pts[i]
        segs.append((end,) if len(s) == 1 else (s[1], s[0], end))
    return {'start': pts[-1], 'segs': segs}


def _solid(glyph: Glyph) -> Glyph:
    """Every subpath clockwise on screen (positive area with y down), so a
    primitive is a solid whichever way it was drawn."""
    glyph.subpaths = [sp if _signed_area(sp) > 0 else _reversed(sp) for sp in glyph.subpaths]
    return glyph


def merge(*glyphs: Glyph) -> Glyph:
    out = Glyph()
    for g in glyphs:
        out.subpaths.extend(g.subpaths)
    return out


def bell(cx: float, cy: float, height: float, turn: float = 0.0) -> Glyph:
    """The `kettlebell` glyph, `height` tall, its ink centred on (cx, cy),
    turned `turn` degrees clockwise. Its window stays a hole."""
    base = _kb.kettlebell()
    left, top, right, bottom = base.bounds()
    s = height / (bottom - top)
    mx, my = (left + right) / 2, (top + bottom) / 2
    c, si = math.cos(math.radians(turn)), math.sin(math.radians(turn))

    def f(p):
        x, y = (p[0] - mx) * s, (p[1] - my) * s
        return (cx + x * c - y * si, cy + x * si + y * c)
    return _map(base, f)


def arc_band(cx: float, cy: float, r: float, a0: float, a1: float, w: float = BAND,
             round_start: bool = True, round_end: bool = True) -> Glyph:
    """A band of width `w` along the circle (cx, cy, r) from a0 to a1 degrees
    (y down: 0° east, 90° south), its ends rounded unless told otherwise."""
    ro, ri, h = r + w / 2, r - w / 2, w / 2
    sign = 1 if a1 > a0 else -1
    g = Glyph()
    g.move(cx + ro * math.cos(math.radians(a0)), cy + ro * math.sin(math.radians(a0)))
    g.arc(cx, cy, ro, a0, a1)
    ex, ey = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    if round_end:
        g.arc(ex, ey, h, a1, a1 + 180 * sign)
    else:
        g.line(cx + ri * math.cos(math.radians(a1)), cy + ri * math.sin(math.radians(a1)))
    g.arc(cx, cy, ri, a1, a0)
    sx, sy = cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))
    if round_start:
        g.arc(sx, sy, h, a0 + 180 * sign, a0 + 360 * sign)
    return _solid(g)


def bar(x0: float, y0: float, x1: float, y1: float, w: float = BAND,
        round_start: bool = True, round_end: bool = True) -> Glyph:
    """A straight band from (x0, y0) to (x1, y1), its ends rounded unless told."""
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    px, py = -uy * w / 2, ux * w / 2
    ang = math.degrees(math.atan2(dy, dx))
    g = Glyph().move(x0 + px, y0 + py).line(x1 + px, y1 + py)
    if round_end:
        g.arc(x1, y1, w / 2, ang + 90, ang - 90)
    else:
        g.line(x1 - px, y1 - py)
    g.line(x0 - px, y0 - py)
    if round_start:
        g.arc(x0, y0, w / 2, ang - 90, ang - 270)
    return _solid(g)


def arrowhead(tx: float, ty: float, direction: float, length: float = 20.0,
              width: float = 24.0) -> Glyph:
    """A filled triangle whose tip is (tx, ty), pointing `direction` degrees."""
    a = math.radians(direction)
    ux, uy = math.cos(a), math.sin(a)
    bx, by = tx - ux * length, ty - uy * length
    px, py = -uy * width / 2, ux * width / 2
    return _solid(Glyph().move(tx, ty).line(bx + px, by + py).line(bx - px, by - py))


def steps(x0: float, y: float, run: float, rise: float, count: int, w: float = BAND) -> Glyph:
    """A staircase line rising left to right: `count` treads of `run`, each
    `rise` above the last, drawn as one band of width `w`."""
    pts = [(x0, y)]
    x, yy = x0, y
    for i in range(count):
        x += run
        pts.append((x, yy))
        if i < count - 1:
            yy -= rise
            pts.append((x, yy))
    # Offset the polyline by ±w/2 with square joins: the outline's upper edge
    # walks left to right, the lower edge back.
    h = w / 2
    upper, lower = [], []
    for i, (px, py) in enumerate(pts):
        if i == 0:
            upper.append((px, py - h)); lower.append((px, py + h))
        elif i == len(pts) - 1:
            upper.append((px, py - h)); lower.append((px, py + h))
        else:
            # A tread end then a riser up: the corner turns left (up).
            prev, nxt = pts[i - 1], pts[i + 1]
            if prev[1] == py and nxt[0] == px:      # tread → riser
                upper.append((px - h, py - h)); lower.append((px + h, py + h))
            else:                                   # riser → tread
                upper.append((px - h, py - h)); lower.append((px + h, py + h))
    g = Glyph().move(*upper[0])
    for p in upper[1:]:
        g.line(*p)
    for p in reversed(lower):
        g.line(*p)
    return _solid(g)


# ── the icons ────────────────────────────────────────────────────────────────

def kettlebell() -> Glyph:
    return _kb.kettlebell()


def swing() -> Glyph:
    """A pendulum: the bell at the top of its swing, out front at chest
    height, and the arc it came up through below it. No arrowhead — the
    swing goes back and forth."""
    return merge(
        bell(66, 26, 48),
        arc_band(40, 40, 28, 175, 60),
    )


def snatch() -> Glyph:
    """The bell overhead at the end of an arc that rises from low behind,
    with an arrowhead: up and over, finishing high."""
    return merge(
        bell(70, 22, 46),
        arc_band(66, 80, 46, 178, 228, round_end=False),
        arrowhead(*_on(66, 80, 46, 240), direction=240 + 90, length=18, width=24),
    )


def clean_press() -> Glyph:
    """A short hook up into the rack, then a straight shaft and an arrowhead
    beside the bell: clean, then press."""
    return merge(
        bell(64, 56, 46),
        arc_band(34, 78, 14, 90, 180, round_end=False, round_start=True),
        bar(20, 78, 20, 26, round_start=False, round_end=False),
        arrowhead(20, 6, -90, length=20, width=26),
    )


def getup() -> Glyph:
    """The bell held up over a stepped line that climbs from the floor to
    standing."""
    return merge(
        bell(64, 24, 44),
        bar(64, 50, 64, 64, round_start=False, round_end=True),
        steps(12, 90, 26, 18, 3),
    )


def squat() -> Glyph:
    """The bell at the chest beside a down-and-up arrow."""
    return merge(
        bell(62, 50, 54),
        bar(18, 30, 18, 70, round_start=False, round_end=False),
        arrowhead(18, 8, -90, length=20, width=26),
        arrowhead(18, 92, 90, length=20, width=26),
    )


def _on(cx, cy, r, a):
    return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))


GLYPHS = {
    'kettlebell': kettlebell,
    'kettlebell.swing': swing,
    'kettlebell.snatch': snatch,
    'kettlebell.clean.press': clean_press,
    'kettlebell.getup': getup,
    'kettlebell.squat': squat,
}


def normalized_d(glyph: Glyph, box: float = 100.0, height: float = 86.0) -> str:
    """The glyph as an SVG path on a `box` square, its ink `height` tall (or
    as wide, whichever is larger) and centred — the web's and Garmin's form."""
    left, top, right, bottom = glyph.bounds()
    s = height / max(bottom - top, right - left)
    x0 = box / 2 - (left + right) / 2 * s
    y0 = box / 2 - (top + bottom) / 2 * s

    def pt(p):
        return f'{x0 + p[0] * s:.2f} {y0 + p[1] * s:.2f}'
    out = []
    for sp in glyph.subpaths:
        out.append(f'M{pt(sp["start"])}')
        for seg in sp['segs']:
            out.append(f'L{pt(seg[0])}' if len(seg) == 1 else f'C{pt(seg[0])} {pt(seg[1])} {pt(seg[2])}')
        out.append('Z')
    return ''.join(out)
