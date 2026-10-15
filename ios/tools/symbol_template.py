"""Shared writer for the app's custom SF Symbols (ios/docs/custom-icons.md).

An icon script describes its glyph on a 100×100 grid (y down) with `Glyph`
and calls `write_symbolset`, which places it in an SF Symbols 3.0 template:
the three required sources (Ultralight-S, Regular-S, Black-S), centred on the
Small row's cap height, at the house height and sidebearing below. Paths come
out as M/L/C/Z only — the subset Xcode's importer and preview_symbol.swift
both read.
"""
import math
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / 'TrainingCompanion/Assets.xcassets'

# The template's Small row, and the house metrics every custom icon shares.
BASELINE_S, CAPLINE_S = 696.0, 625.541
HEIGHT_S = 74.0          # glyph height in the Small row (about the dumbbell's)
SIDEBEARING = 3.0        # space either side of the glyph, in template units
COLUMNS = {'Ultralight-S': 559.711, 'Regular-S': 1449.71, 'Black-S': 2369.71}


class Glyph:
    """A glyph on the 100 grid as subpaths of cubic segments.

    Draw each solid outline clockwise (on screen, y down) and each hole
    counter-clockwise: the template's non-zero fill makes a reversed subpath
    a hole, and `hole()` reverses one for you.
    """

    def __init__(self):
        self.subpaths = []

    def move(self, x, y):
        self.subpaths.append({'start': (x, y), 'segs': []})
        return self

    @property
    def _cur(self):
        sp = self.subpaths[-1]
        return sp['segs'][-1][-1] if sp['segs'] else sp['start']

    def line(self, x, y):
        self.subpaths[-1]['segs'].append(((x, y),))
        return self

    def quad(self, cx, cy, x, y):
        """A quadratic corner, stored as its exact cubic."""
        p0 = self._cur
        c1 = (p0[0] + 2 / 3 * (cx - p0[0]), p0[1] + 2 / 3 * (cy - p0[1]))
        c2 = (x + 2 / 3 * (cx - x), y + 2 / 3 * (cy - y))
        self.subpaths[-1]['segs'].append((c1, c2, (x, y)))
        return self

    def arc(self, cx, cy, r, a0, a1):
        """Along the circle (cx, cy, r) from angle a0 to a1, in degrees, y down
        (0° is east, 90° south). The current point should be at a0."""
        n = max(1, math.ceil(abs(a1 - a0) / 45))
        for i in range(n):
            t0 = math.radians(a0 + (a1 - a0) * i / n)
            t1 = math.radians(a0 + (a1 - a0) * (i + 1) / n)
            k = 4 / 3 * math.tan((t1 - t0) / 4) * r
            p3 = (cx + r * math.cos(t1), cy + r * math.sin(t1))
            p0 = (cx + r * math.cos(t0), cy + r * math.sin(t0))
            c1 = (p0[0] - k * math.sin(t0), p0[1] + k * math.cos(t0))
            c2 = (p3[0] + k * math.sin(t1), p3[1] - k * math.cos(t1))
            self.subpaths[-1]['segs'].append((c1, c2, p3))
        return self

    def bounds(self):
        """The ink's extent, sampled along each curve — a curve's endpoints
        alone miss the sides of a circle."""
        pts = []
        for sp in self.subpaths:
            p0 = sp['start']
            pts.append(p0)
            for s in sp['segs']:
                if len(s) == 3:
                    for i in range(1, 32):
                        t = i / 32
                        pts.append(tuple((1 - t) ** 3 * p0[k] + 3 * (1 - t) ** 2 * t * s[0][k]
                                         + 3 * (1 - t) * t * t * s[1][k] + t ** 3 * s[2][k] for k in (0, 1)))
                p0 = s[-1]
                pts.append(p0)
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return min(xs), min(ys), max(xs), max(ys)


def _path_d(glyph, scale, x0, y0):
    def pt(p):
        return f'{x0 + p[0] * scale:.3f} {y0 + p[1] * scale:.3f}'
    out = []
    for sp in glyph.subpaths:
        out.append(f'M{pt(sp["start"])}')
        for s in sp['segs']:
            out.append(f'L{pt(s[0])}' if len(s) == 1 else f'C{pt(s[0])} {pt(s[1])} {pt(s[2])}')
        out.append('Z')
    return ''.join(out)


def write_symbolset(name, glyph, *, script, assets=ASSETS):
    """Writes <assets>/<name>.symbolset (SVG + Contents.json); `assets` is the
    phone app's catalog unless another target's is given.

    The glyph's ink is scaled so its height is HEIGHT_S, centred on the cap
    height, with SIDEBEARING either side.
    """
    left, top, right, bottom = glyph.bounds()
    scale = HEIGHT_S / (bottom - top)
    mid = (BASELINE_S + CAPLINE_S) / 2
    y0 = mid - (top + bottom) / 2 * scale
    width = (right - left) * scale
    guides, symbols = [], []
    margin = 'style="fill:none;stroke:#00AC8E;stroke-width:0.5;opacity:1.0;"'
    for col, x in COLUMNS.items():
        guides.append(f'<line id="left-margin-{col}" {margin} x1="{x:.3f}" x2="{x:.3f}" y1="600.785" y2="720.121"/>')
        rx = x + width + 2 * SIDEBEARING
        guides.append(f'<line id="right-margin-{col}" {margin} x1="{rx:.3f}" x2="{rx:.3f}" y1="600.785" y2="720.121"/>')
        x0 = x + SIDEBEARING - left * scale
        symbols.append(f'<g id="{col}"><path d="{_path_d(glyph, scale, x0, y0)}"/></g>')
    line = 'style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263.711" x2="3236.84"'
    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!--Generated by ios/tools/{script} — edit the script, not this file.-->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--glyph: "{name}", point size: 100.0, template writer version: "custom"-->
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" {line} y1="{BASELINE_S}" y2="{BASELINE_S}"/>
  <line id="Capline-S" {line} y1="{CAPLINE_S}" y2="{CAPLINE_S}"/>
  <line id="Baseline-M" {line} y1="1126" y2="1126"/>
  <line id="Capline-M" {line} y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" {line} y1="1556" y2="1556"/>
  <line id="Capline-L" {line} y1="1485.54" y2="1485.54"/>
  {chr(10).join("  " + g for g in guides).lstrip()}
 </g>
 <g id="Symbols">
  {chr(10).join("  " + s for s in symbols).lstrip()}
 </g>
</svg>
'''
    out = Path(assets) / f'{name}.symbolset'
    out.mkdir(parents=True, exist_ok=True)
    (out / f'{name}.svg').write_text(svg)
    (out / 'Contents.json').write_text(
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n'
        f'  "symbols" : [\n    {{\n      "filename" : "{name}.svg",\n      "idiom" : "universal"\n    }}\n  ]\n}}\n')
    return out / f'{name}.svg'
