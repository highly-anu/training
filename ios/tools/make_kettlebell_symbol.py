#!/usr/bin/env python3
"""The `kettlebell` custom SF Symbol (ios/docs/custom-icons.md).

SF Symbols has no kettlebell. A wide handle whose window's floor is the top
of a round ball with a short flat base; filled, like `dumbbell.fill`. The
first drafts had a narrow handle and a small window and read as a padlock at
list size — the window is what says "kettlebell".

    python3 ios/tools/make_kettlebell_symbol.py
"""
import math

from symbol_template import Glyph, write_symbolset

CX, CY, R = 50.0, 62.0, 34.0         # the ball
LEG, BASE_Y, WIN = 30.0, 92.0, 21.0  # where the handle meets the ball, the base, the window's floor


def on_ball(dx):
    return CY - math.sqrt(R * R - dx * dx)


def angle(dx):
    return math.degrees(math.atan2(on_ball(dx) - CY, dx))


def kettlebell():
    base_half = math.sqrt(R * R - (BASE_Y - CY) ** 2)
    a_base = math.degrees(math.atan2(BASE_Y - CY, base_half))
    g = Glyph()
    # Outline, clockwise: up the handle's left leg, over, down the right,
    # round the ball to the base and back up.
    (g.move(CX - LEG, on_ball(LEG))
      .line(20, 24).quad(20, 7, 37, 7).line(63, 7).quad(80, 7, 80, 24)
      .line(CX + LEG, on_ball(LEG))
      .arc(CX, CY, R, angle(LEG), a_base)
      .line(CX - base_half, BASE_Y)
      .arc(CX, CY, R, 180 - a_base, 180 - angle(LEG)))
    # Window, counter-clockwise so it is a hole; its floor is the ball.
    (g.move(CX + WIN, on_ball(WIN))
      .line(71, 26).quad(71, 16, 61, 16).line(39, 16).quad(29, 16, 29, 26)
      .line(CX - WIN, on_ball(WIN))
      .arc(CX, CY, R, -180 - angle(WIN), angle(WIN)))
    return g


if __name__ == '__main__':
    print(write_symbolset('kettlebell', kettlebell(), script='make_kettlebell_symbol.py'))
