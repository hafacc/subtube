"""Draw the logo and its animations into this folder.

The logo is drawn once, in a 24 by 24 box, and written in two framings:
beside the name (`sub-play.svg`: fin and body centered across, body centered
down, tower and bubbles above the line) and standing alone (the `-centred`
files: everything centered). `sub-play-centred-small.svg` has one large
bubble, for icons 16 points and under.

`motion()` and `bubbles()` are the animation every client draws while it
loads; the two animated files play it in a loop.

Needs shapely. Run `python make.py`.
"""

import math
from dataclasses import dataclass
from pathlib import Path

from shapely import Polygon, unary_union

HERE = Path(__file__).parent
YELLOW = "#FFC20E"
INK = "#1B1E24"
SQRT3 = math.sqrt(3)

# the body alone, YouTube's shape; the windows are cut to it
BODY = "M22.209 11.042 L22.178 10.949 L22.143 10.859 L22.105 10.769 L22.062 10.684 L22.016 10.599 L21.967 10.516 L21.914 10.436 L21.859 10.359 L21.8 10.285 L21.738 10.213 L21.673 10.144 L21.605 10.078 L21.534 10.015 L21.461 9.955 L21.385 9.898 L21.307 9.844 L21.226 9.794 L21.144 9.747 L21.058 9.704 L20.97 9.665 L20.882 9.63 L20.79 9.598 L20.698 9.57 L20.508 9.526 L20.28 9.485 L20.016 9.448 L19.063 9.356 L18.705 9.332 L18.332 9.31 L17.951 9.29 L17.512 9.272 L17.554 9.337 L15.627 9.349 L15.672 9.278 L15.714 9.219 L15.052 9.209 L14.007 9.2 L13.793 9.2 L13.277 9.204 L12.439 9.213 L11.755 9.227 L11.388 9.235 L10.625 9.258 L10.236 9.274 L9.85 9.29 L9.468 9.31 L9.095 9.332 L8.737 9.356 L7.784 9.448 L7.52 9.485 L7.292 9.526 L7.102 9.57 L7.01 9.598 L6.918 9.63 L6.83 9.665 L6.742 9.704 L6.657 9.747 L6.574 9.794 L6.493 9.844 L6.415 9.898 L6.339 9.955 L6.266 10.015 L6.195 10.078 L6.127 10.144 L6.062 10.213 L6 10.285 L5.941 10.359 L5.886 10.436 L5.833 10.516 L5.784 10.599 L5.738 10.684 L5.695 10.769 L5.657 10.859 L5.622 10.949 L5.591 11.042 L5.564 11.136 L5.52 11.317 L5.48 11.51 L5.444 11.716 L5.411 11.932 L5.38 12.156 L5.353 12.385 L5.33 12.619 L5.308 12.855 L5.289 13.092 L5.257 13.559 L5.235 14.005 L5.226 14.216 L5.213 14.601 L5.209 14.773 L5.202 15.18 L5.2 15.342 L5.202 15.62 L5.209 16.027 L5.213 16.199 L5.226 16.584 L5.235 16.795 L5.257 17.241 L5.289 17.708 L5.308 17.945 L5.33 18.181 L5.353 18.415 L5.38 18.644 L5.411 18.868 L5.444 19.084 L5.48 19.29 L5.52 19.483 L5.564 19.664 L5.591 19.758 L5.622 19.851 L5.657 19.941 L5.695 20.031 L5.738 20.117 L5.784 20.201 L5.833 20.284 L5.886 20.364 L5.941 20.441 L6 20.515 L6.062 20.587 L6.127 20.656 L6.195 20.722 L6.266 20.785 L6.339 20.845 L6.415 20.902 L6.493 20.956 L6.574 21.006 L6.657 21.053 L6.742 21.096 L6.83 21.135 L6.918 21.17 L7.01 21.202 L7.102 21.23 L7.292 21.274 L7.52 21.315 L7.784 21.352 L8.076 21.386 L8.396 21.417 L8.737 21.444 L9.095 21.468 L9.468 21.49 L9.85 21.51 L10.236 21.526 L10.625 21.542 L11.01 21.554 L11.388 21.565 L12.106 21.581 L12.748 21.591 L13.277 21.596 L13.793 21.6 L14.007 21.6 L15.052 21.591 L15.361 21.587 L16.045 21.573 L16.791 21.554 L17.175 21.542 L17.564 21.526 L17.951 21.51 L18.332 21.49 L18.705 21.468 L19.063 21.444 L19.404 21.417 L19.724 21.386 L20.016 21.352 L20.28 21.315 L20.508 21.274 L20.698 21.23 L20.79 21.202 L20.882 21.17 L20.97 21.135 L21.058 21.096 L21.144 21.053 L21.226 21.006 L21.307 20.956 L21.385 20.902 L21.461 20.845 L21.534 20.785 L21.605 20.722 L21.673 20.656 L21.738 20.587 L21.8 20.515 L21.859 20.441 L21.914 20.364 L21.967 20.284 L22.016 20.201 L22.062 20.117 L22.105 20.031 L22.143 19.941 L22.178 19.851 L22.209 19.758 L22.236 19.664 L22.28 19.483 L22.32 19.29 L22.356 19.084 L22.389 18.868 L22.42 18.644 L22.447 18.415 L22.47 18.181 L22.492 17.945 L22.511 17.708 L22.528 17.473 L22.543 17.241 L22.555 17.014 L22.565 16.795 L22.581 16.385 L22.587 16.199 L22.595 15.872 L22.6 15.458 L22.6 15.342 L22.597 15.064 L22.59 14.773 L22.581 14.415 L22.564 14.005 L22.554 13.786 L22.542 13.559 L22.527 13.327 L22.51 13.092 L22.491 12.855 L22.47 12.619 L22.446 12.385 L22.419 12.156 L22.389 11.932 L22.356 11.716 L22.32 11.51 L22.28 11.317 L22.236 11.136Z"
# the tail: the body narrows, then flares
FIN = [(6.4, 12.2), (4.0, 14.6), (1.7, 12.2), (1.7, 18.6), (4.0, 16.2), (6.4, 18.6)]
TOWER = [(10.6, 10.6), (11.8, 4.8), (17.0, 4.8), (17.0, 10.6)]
# how far the fin and tower are grown, which rounds their corners
FIN_ROUNDING = 0.6
TOWER_ROUNDING = 0.8
MIDLINE = 15.4  # the body's center line, which the triangle and windows sit on

# play triangle: equilateral, pointing at the nose
TRIANGLE_LEFT = 11.648
TRIANGLE_RIGHT = 17.248
TRIANGLE_CENTER = (2 * TRIANGLE_LEFT + TRIANGLE_RIGHT) / 3
TRIANGLE_INRADIUS = (TRIANGLE_RIGHT - TRIANGLE_CENTER) / 2

WINDOWS = [(9.3, 1.15), (13.0, 1.55), (17.6, 2.0)]  # (x, radius), tail to nose
BUBBLES = [(3.2, 7.6, 1.5), (5.8, 4.2, 1.1)]  # (x, y, radius), low to high
LARGE_BUBBLE = (4.8, 5.4, 2.8)

STEP = 0.5  # seconds for a window to reach the next one's place
WINDOW_TRACK = [(5.4, 0.0), *WINDOWS, (22.6, 2.4)]  # grown from nothing at the tail, gone past the nose
SHRINK = 0.6  # steps past the last window's place for it to shrink away
LAP = len(WINDOW_TRACK) - 1  # steps before a window is back where it started
START_BLEND = 1.5  # steps for the triangle to become a window
END_BLEND = 1.0  # steps for a window to settle as the triangle
# (x, y, radius): out from behind the tail, through the two resting places, gone
BUBBLE_TRACK = [(2.2, 10.8, 0.0), *BUBBLES, (7.4, 2.9, 0.0)]
BUBBLE_LAP = len(BUBBLE_TRACK) - 1
LEAVE = (0.25, 0.45)  # seconds a resting bubble takes to float off: this, and this per place it has left
PUFF_FIRST = 0.1  # seconds into a load for the first puff
PUFF_EVERY = 2.0  # seconds from one puff to the next
PUFF_RISE = 1.5  # seconds a puff's bubble takes to rise and vanish
PUFF_SIZE = 1.1  # a puff's largest bubble, in track radii
PUFF = [(1.0, 0.0, 0.0), (0.65, 0.9, 0.13), (0.5, -0.8, 0.26)]  # each bubble's (size, sway, seconds late)
SETTLE = [(2, 0.0, 1.0), (1, 0.35, 0.8)]  # the last bubbles: (place, seconds after the load ends, seconds to get there)
# the triangle in motion is a circle cut by a triangle; these are the triangle's inradius, in
# circle radii, when the piece is the play triangle and once the circle sits wholly inside it
CUT_TRIANGLE = 0.48
CUT_CIRCLE = 1.06


def number(value: float) -> str:
    """Format a coordinate."""
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def body_points() -> list[tuple[float, float]]:
    """Read the body's corners."""
    pairs = [pair.split() for pair in BODY[1:-1].split(" L")]
    return [(float(x), float(y)) for x, y in pairs]


def hull_points() -> list[tuple[float, float]]:
    """Join the body, fin and tower into one outline."""
    grown = [
        Polygon(shape).buffer(rounding, quad_segs=6)
        for shape, rounding in ((FIN, FIN_ROUNDING), (TOWER, TOWER_ROUNDING))
    ]
    outline = unary_union([Polygon(body_points()), *grown]).exterior
    return list(outline.coords)[:-1]


@dataclass(frozen=True)
class Framing:
    """Where the drawing sits in the 24 by 24 box."""

    scale: float
    across: float
    down: float

    def point(self, x: float, y: float) -> tuple[float, float]:
        """Place a point of the drawing."""
        return self.scale * x + self.across, self.scale * y + self.down

    def path(self, points: list[tuple[float, float]]) -> str:
        """Write corners as path data."""
        placed = [self.point(x, y) for x, y in points]
        return "M" + " L".join(f"{number(x)} {number(y)}" for x, y in placed) + "Z"

    def circle(self, x: float, y: float, radius: float, attributes: str = "") -> str:
        """Write a circle."""
        center_x, center_y = self.point(x, y)
        return f'<circle cx="{number(center_x)}" cy="{number(center_y)}" r="{number(radius * self.scale)}"{attributes}/>'

    def transform(self, x: float, y: float, size: float) -> str:
        """Write the CSS transform that puts a unit shape at a point, at a size."""
        center_x, center_y = self.point(x, y)
        return f"translate({number(center_x)}px,{number(center_y)}px) scale({number(size * self.scale)})"


def centered(box: tuple[float, float, float, float], scale: float = 1.0) -> Framing:
    """Center a box (left, top, right, bottom) of the drawing in the 24 by 24 box."""
    left, top, right, bottom = box
    return Framing(scale, 12 - scale * (left + right) / 2, 12 - scale * (top + bottom) / 2)


HULL = hull_points()
HULL_LEFT = min(x for x, _ in HULL)
BODY_TOP = min(y for _, y in body_points())
BODY_RIGHT = max(x for x, _ in body_points())
BODY_BOTTOM = max(y for _, y in body_points())
# beside the name: only fin and body take up room, at this share of the box
BESIDE_SCALE = 0.95
BESIDE = centered((HULL_LEFT, BODY_TOP, BODY_RIGHT, BODY_BOTTOM), BESIDE_SCALE)
ALONE = centered((HULL_LEFT, min(y - radius for _, y, radius in BUBBLES), BODY_RIGHT, BODY_BOTTOM))
ALONE_SMALL = centered((HULL_LEFT, LARGE_BUBBLE[1] - LARGE_BUBBLE[2], BODY_RIGHT, BODY_BOTTOM))


def spline(points: list[float], fraction: float) -> float:
    """Catmull-Rom through equally spaced points; fraction in [0, 1]."""
    count = len(points)
    padded = [2 * points[0] - points[1], *points, 2 * points[-1] - points[-2]]
    position = fraction * (count - 1)
    segment = min(int(position), count - 2)
    local = position - segment
    before, start, end, after = padded[segment : segment + 4]
    return 0.5 * (
        2 * start
        + (end - before) * local
        + (2 * before - 5 * start + 4 * end - after) * local**2
        + (3 * start - before - 3 * end + after) * local**3
    )


def smoothstep(value: float) -> float:
    """Ease from 0 to 1."""
    value = min(max(value, 0.0), 1.0)
    return value * value * (3 - 2 * value)


def mix(start: float, end: float, weight: float) -> float:
    """Blend two numbers."""
    return start + (end - start) * weight


def window_at(position: float) -> tuple[float, float]:
    """Give a window's (x, radius) `position` steps along its track."""
    fraction = position / LAP
    radius = max(spline([radius for _, radius in WINDOW_TRACK], fraction), 0.0)
    if position > LAP - 1:
        radius *= 1 - smoothstep((position - (LAP - 1)) / SHRINK)
    return spline([x for x, _ in WINDOW_TRACK], fraction), radius


def bubble_at(position: float, size: float = 1.0) -> tuple[float, float, float]:
    """Give a bubble's (x, y, radius) `position` places along its track."""
    fraction = min(max(position, 0.0), BUBBLE_LAP) / BUBBLE_LAP
    x, y, radius = (spline([point[axis] for point in BUBBLE_TRACK], fraction) for axis in range(3))
    return x, y, max(radius, 0.0) * size


def bubbles(seconds: float, ended: float | None = None) -> list[tuple[float, float, float]]:
    """Give the seven bubbles' (x, y, radius) `seconds` after a load began.

    The two resting bubbles float off. Puffs of three follow, one every
    `PUFF_EVERY` seconds, each bubble fast at first and slowing as it
    shrinks away. `ended` is when the load finished: no puff begins after
    it, and two last bubbles rise into the resting places. A bubble that
    does not show has radius 0.
    """
    x, y, _ = BUBBLE_TRACK[0]
    gone = (x, y, 0.0)
    found = []
    for place in (1, 2):
        base, each = LEAVE
        left = seconds / (base + each * (BUBBLE_LAP - place))
        if seconds < 0:
            found.append(bubble_at(place))
        elif left < 1:
            found.append(bubble_at(place + (BUBBLE_LAP - place) * left**1.5))
        else:
            found.append(gone)
    began = PUFF_FIRST + PUFF_EVERY * math.floor((seconds - PUFF_FIRST) / PUFF_EVERY)
    for size, sway, late in PUFF:
        risen = (seconds - began - late) / PUFF_RISE
        if seconds >= PUFF_FIRST and (ended is None or began <= ended) and 0 <= risen < 1:
            x, y, radius = bubble_at(BUBBLE_LAP * (1 - (1 - risen) ** 2.2), size * PUFF_SIZE)
            found.append((x + sway * math.sin(math.pi * risen), y, radius))
        else:
            found.append(gone)
    for place, late, span in SETTLE:
        if ended is None or seconds < ended + late:
            found.append(gone)
        else:
            arrived = min((seconds - ended - late) / span, 1.0)
            found.append(bubble_at(place * (1 - (1 - arrived) ** 2.4)))
    return found


def bubbles_rest(ended: float) -> float:
    """Give the seconds into a load that ended at `ended` when its bubbles have come to rest."""
    settled = ended + max(late + span for _, late, span in SETTLE)
    if ended < PUFF_FIRST:
        return settled
    else:
        last = PUFF_FIRST + PUFF_EVERY * math.floor((ended - PUFF_FIRST) / PUFF_EVERY)
        return max(settled, last + PUFF_RISE + max(late for _, _, late in PUFF))


@dataclass(frozen=True)
class Motion:
    """The inside of the logo at one moment."""

    triangle: bool
    """Whether the still play triangle shows."""
    windows: list[tuple[float, float]]
    """Each rolling window's (x, radius); radius 0 when it does not show."""
    piece: tuple[float, float, float]
    """The triangle in motion: a circle's (x, radius) and its cut; radius 0 when it does not show."""


def motion(steps: float, ended: float | None = None) -> Motion:
    """Give the logo's inside `steps` steps after a load began.

    The play triangle rounds into a window headed for the nose while windows
    grow in at the tail; they then roll, a lap every `LAP` steps. `ended` is
    how many steps in the load finished: at the next whole step, once the
    start has played out, the window in the first place becomes the triangle
    as the others shrink.
    """
    back = None if ended is None else max(math.ceil(ended), 2)
    if steps < 0 or (back is not None and steps >= back + END_BLEND):
        return Motion(True, [(0.0, 0.0)] * LAP, (TRIANGLE_CENTER, 0.0, CUT_TRIANGLE))
    grow = smoothstep(steps / START_BLEND)
    windows = []
    for index in range(LAP):
        # at the start the windows stand at places 2, 3, 0 and 1; the one at 2 is the triangle
        start = (index + 2) % LAP
        x, radius = window_at((steps + start) % LAP)
        if start >= 2 and steps < LAP - start:
            radius = 0.0  # the piece stands in for it, or it would start ahead of the piece
        radius *= grow
        if back is not None and steps >= back:
            first = round((back + start) % LAP) == 1
            radius = 0.0 if first else radius * (1 - smoothstep((steps - back) / END_BLEND))
        windows.append((x, radius))
    piece = (TRIANGLE_CENTER, 0.0, CUT_TRIANGLE)
    scale = TRIANGLE_INRADIUS / CUT_TRIANGLE
    if steps < 2:
        x, radius = window_at(min(steps + 2, LAP))
        piece = (mix(TRIANGLE_CENTER, x, grow), mix(scale, radius, grow), mix(CUT_TRIANGLE, CUT_CIRCLE, grow))
    elif back is not None and steps >= back:
        settle = smoothstep((steps - back) / END_BLEND)
        x, radius = window_at(1 + steps - back)
        piece = (mix(x, TRIANGLE_CENTER, settle), mix(radius, scale, settle), mix(CUT_CIRCLE, CUT_TRIANGLE, settle))
    return Motion(False, windows, piece)


def triangle_path(framing: Framing) -> str:
    """Write the play triangle."""
    half = (TRIANGLE_RIGHT - TRIANGLE_LEFT) / SQRT3
    corners = [(TRIANGLE_LEFT, MIDLINE - half), (TRIANGLE_RIGHT, MIDLINE), (TRIANGLE_LEFT, MIDLINE + half)]
    return f'<path d="{framing.path(corners)}"/>'


def drawing(framing: Framing, bubbles: str, inside: str, style: str = "", definitions: str = "") -> str:
    """Write one file: the yellow hull and bubbles, and what is cut into the body."""
    styles = f"<style>\n{style}\n</style>" if style else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">{styles}{definitions}'
        f'<g fill="{YELLOW}"><path d="{framing.path(HULL)}"/>{bubbles}</g>'
        f'<g fill="{INK}">{inside}</g></svg>\n'
    )


def still(framing: Framing, bubbles: list[tuple[float, float, float]], windows: bool) -> str:
    """Write a still logo, with the play triangle or the three windows."""
    circles = "".join(framing.circle(*bubble) for bubble in bubbles)
    if windows:
        inside = "".join(framing.circle(x, MIDLINE, radius) for x, radius in WINDOWS)
    else:
        inside = triangle_path(framing)
    return drawing(framing, circles, inside)


REDUCED = "@media (prefers-reduced-motion:reduce){*{animation:none!important}}"
SHAPES = "circle,polygon,g{transform-box:view-box;transform-origin:0 0}"


def keyframes(name: str, stops: list[tuple[float, str]]) -> str:
    """Write a keyframes rule from (fraction, properties) stops."""
    body = "".join(f"{number(fraction * 100)}%{{{properties}}}" for fraction, properties in stops)
    return f"@keyframes {name}{{{body}}}"


def rising(framing: Framing, seconds: float, moments: list[tuple[float, list[tuple[float, float, float]]]]) -> tuple[str, str]:
    """Write the bubbles' rules and circles from (fraction of the loop, bubbles) moments."""
    rules, circles = [], []
    for index in range(len(moments[0][1])):
        stops = [(fraction, f"transform:{framing.transform(*found[index])}") for fraction, found in moments]
        rules.append(keyframes(f"b{index}", stops))
        rules.append(
            f".b{index}{{transform:{framing.transform(*bubbles(-1)[index])};"
            f"animation:b{index} {number(seconds)}s linear infinite}}"
        )
        circles.append(f'<circle class="b{index}" r="1"/>')
    return "\n".join(rules), "".join(circles)


def loading(framing: Framing) -> str:
    """Write the loop a client shows while it loads: windows rolling, puffs of bubbles rising."""
    stops = [
        (index / (LAP * 16), f"transform:{framing.transform(window_at(index / 16)[0], MIDLINE, window_at(index / 16)[1])}")
        for index in range(LAP * 16 + 1)
    ]
    rules = [SHAPES, keyframes("roll", stops)]
    circles = []
    for index, (x, radius) in enumerate(WINDOW_TRACK[:LAP]):
        rules.append(
            f".p{index}{{transform:{framing.transform(x, MIDLINE, radius)};"
            f"animation:roll {number(STEP * LAP)}s linear {number(-STEP * index)}s infinite}}"
        )
        circles.append(f'<circle class="p{index}" r="1"/>')
    # one puff, as it repeats once the resting bubbles are long gone
    puffs = [
        (index / 80, bubbles(PUFF_EVERY * (1 + index / 80))[2 : 2 + len(PUFF)])
        for index in range(81)
    ]
    bubble_rules, bubble_circles = rising(framing, PUFF_EVERY, puffs)
    clip = f'<clipPath id="body"><path d="{framing.path(body_points())}"/></clipPath>'
    inside = f'<g clip-path="url(#body)">{"".join(circles)}</g>'
    return drawing(framing, bubble_circles, inside, "\n".join([*rules, bubble_rules, REDUCED]), clip)


LOOP = 13  # steps in the play-to-loading loop
LOOP_START = 2  # the load begins
LOOP_END = 9.5  # the load ends, so the triangle starts back at step 10


def play_to_loading(framing: Framing) -> str:
    """Write the whole of `motion()` as a loop: play, a load, play again."""
    seconds = STEP * LOOP
    back = max(math.ceil(LOOP_END - LOOP_START), 2) + LOOP_START
    tiny = 0.0002
    times = {round(index / 12, 6) for index in range(LOOP * 12 + 1)}
    for edge in [*range(LOOP + 1), LOOP_START + START_BLEND, back + END_BLEND]:
        times |= {max(edge - tiny, 0), edge, min(edge + tiny, LOOP)}
    moments = [(time, motion(time - LOOP_START, LOOP_END - LOOP_START)) for time in sorted(times)]
    rules = [
        SHAPES,
        f"#triangle{{animation:triangle {number(seconds)}s step-end infinite}}",
        "@keyframes triangle{0%{visibility:visible}"
        f"{number(LOOP_START / LOOP * 100)}%{{visibility:hidden}}"
        f"{number((back + END_BLEND) / LOOP * 100)}%{{visibility:visible}}}}",
    ]
    circles = []
    for index in range(LAP):
        stops = [
            (time / LOOP, f"transform:{framing.transform(moment.windows[index][0], MIDLINE, moment.windows[index][1])}")
            for time, moment in moments
        ]
        rules.append(keyframes(f"w{index}", stops))
        rules.append(f".w{index}{{transform:scale(0);animation:w{index} {number(seconds)}s linear infinite}}")
        circles.append(f'<circle class="w{index}" r="1"/>')
    rules += [
        keyframes("piece", [(time / LOOP, f"transform:{framing.transform(moment.piece[0], MIDLINE, moment.piece[1])}") for time, moment in moments]),
        f"#piece{{transform:scale(0);animation:piece {number(seconds)}s linear infinite}}",
        keyframes("cut", [(time / LOOP, f"transform:scale({number(moment.piece[2])})") for time, moment in moments]),
        f".cut{{transform:scale({CUT_TRIANGLE});animation:cut {number(seconds)}s linear infinite}}",
    ]
    risen = [
        (time / LOOP, bubbles((time - LOOP_START) * STEP, (LOOP_END - LOOP_START) * STEP)) for time, _ in moments
    ]
    bubble_rules, bubble_circles = rising(framing, seconds, risen)
    definitions = (
        f'<clipPath id="body"><path d="{framing.path(body_points())}"/></clipPath>'
        f'<clipPath id="cut"><polygon class="cut" points="2,0 -1,{number(SQRT3)} -1,{number(-SQRT3)}"/></clipPath>'
    )
    inside = (
        triangle_path(framing).replace("<path ", '<path id="triangle" ')
        + f'<g clip-path="url(#body)">{"".join(circles)}'
        + '<g id="piece"><g clip-path="url(#cut)"><circle r="1"/></g></g></g>'
    )
    return drawing(framing, bubble_circles, inside, "\n".join([*rules, bubble_rules, REDUCED]), definitions)


if __name__ == "__main__":
    files = {
        "sub-play.svg": still(BESIDE, BUBBLES, windows=False),
        "sub-play-centred.svg": still(ALONE, BUBBLES, windows=False),
        "sub-play-centred-small.svg": still(ALONE_SMALL, [LARGE_BUBBLE], windows=False),
        "sub-ports.svg": still(ALONE, BUBBLES, windows=True),
        "sub-ports-loading.svg": loading(ALONE),
        "sub-play-to-loading.svg": play_to_loading(ALONE),
    }
    for name, text in files.items():
        (HERE / name).write_text(text)
