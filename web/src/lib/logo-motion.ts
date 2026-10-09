/*
 * The logo's loading animation, as design/icons/make.py's motion() draws it.
 * Everything is in the drawing's own units, a 24 by 24 box before it is
 * framed; BESIDE places it as static/logo.svg does.
 */

/** Where the drawing sits beside the name: sub-play.svg's framing. */
export const BESIDE = { scale: 0.95, across: 0.7425, down: -2.63 };

/** The body's center line, which the triangle and windows sit on. */
export const MIDLINE = 15.4;

/** Seconds for a window to reach the next one's place. */
export const STEP = 0.5;

const TRIANGLE_LEFT = 11.648;
const TRIANGLE_RIGHT = 17.248;
const TRIANGLE_CENTER = (2 * TRIANGLE_LEFT + TRIANGLE_RIGHT) / 3;
const TRIANGLE_INRADIUS = (TRIANGLE_RIGHT - TRIANGLE_CENTER) / 2;

// [x, radius], tail to nose: grown from nothing at the tail, gone past the nose
const WINDOW_TRACK = [
  [5.4, 0],
  [9.3, 1.15],
  [13, 1.55],
  [17.6, 2],
  [22.6, 2.4],
];
// steps past the last window's place for it to shrink away
const SHRINK = 0.6;
// steps before a window is back where it started
const LAP = WINDOW_TRACK.length - 1;
// steps for the triangle to become a window, and for a window to settle as the triangle
const START_BLEND = 1.5;
const END_BLEND = 1;
// [x, y, radius]: out from behind the tail, through the two resting places, gone
const BUBBLE_TRACK = [
  [2.2, 10.8, 0],
  [3.2, 7.6, 1.5],
  [5.8, 4.2, 1.1],
  [7.4, 2.9, 0],
];
const BUBBLE_LAP = BUBBLE_TRACK.length - 1;
// seconds a resting bubble takes to float off: this, and this per place it has left
const LEAVE = [0.25, 0.45];
// seconds into a load for the first puff, and from one puff to the next
const PUFF_FIRST = 0.1;
const PUFF_EVERY = 2;
// seconds a puff's bubble takes to rise and vanish
const PUFF_RISE = 1.5;
// a puff's largest bubble, in track radii
const PUFF_SIZE = 1.1;
// each bubble of a puff: [size, sway, seconds late]
const PUFF = [
  [1, 0, 0],
  [0.65, 0.9, 0.13],
  [0.5, -0.8, 0.26],
];
// the last bubbles: [place, seconds after the load ends, seconds to get there]
const SETTLE = [
  [2, 0, 1],
  [1, 0.35, 0.8],
];
// the triangle in motion is a circle cut by a triangle; these are the triangle's inradius, in
// circle radii, when the piece is the play triangle and once the circle sits wholly inside it
const CUT_TRIANGLE = 0.48;
const CUT_CIRCLE = 1.06;

/** A circle on the body's center line. */
export interface LogoWindow {
  x: number;
  /** 0 when it does not show */
  radius: number;
}

/** A bubble behind the tail. */
export interface LogoBubble {
  x: number;
  y: number;
  radius: number;
}

/** The triangle in motion: a circle cut by a triangle pointing at the nose. */
export interface LogoPiece extends LogoWindow {
  /** the cutting triangle's inradius, in circle radii */
  cut: number;
}

/** The logo at one moment. */
export interface LogoFrame {
  /** whether the still play triangle shows */
  triangle: boolean;
  windows: LogoWindow[];
  piece: LogoPiece;
  bubbles: LogoBubble[];
  /** whether the animation has played out, so the still logo stands */
  done: boolean;
}

// Catmull-Rom through equally spaced points; fraction in [0, 1]
function spline(points: number[], fraction: number): number {
  const padded = [
    2 * points[0] - points[1],
    ...points,
    2 * points[points.length - 1] - points[points.length - 2],
  ];
  const position = fraction * (points.length - 1);
  const segment = Math.min(Math.floor(position), points.length - 2);
  const local = position - segment;
  const [before, start, end, after] = padded.slice(segment, segment + 4);
  return (
    0.5 *
    (2 * start +
      (end - before) * local +
      (2 * before - 5 * start + 4 * end - after) * local ** 2 +
      (3 * start - before - 3 * end + after) * local ** 3)
  );
}

function smoothstep(value: number): number {
  const clamped = Math.min(Math.max(value, 0), 1);
  return clamped * clamped * (3 - 2 * clamped);
}

function mix(start: number, end: number, weight: number): number {
  return start + (end - start) * weight;
}

/** A window `position` steps along its track. */
export function windowAt(position: number): LogoWindow {
  const fraction = position / LAP;
  let radius = Math.max(
    spline(
      WINDOW_TRACK.map(([, trackRadius]) => trackRadius),
      fraction,
    ),
    0,
  );
  if (position > LAP - 1) {
    radius *= 1 - smoothstep((position - (LAP - 1)) / SHRINK);
  }
  return {
    x: spline(
      WINDOW_TRACK.map(([x]) => x),
      fraction,
    ),
    radius,
  };
}

/** A bubble `position` places along its track. */
export function bubbleAt(position: number, size = 1): LogoBubble {
  const fraction = Math.min(Math.max(position, 0), BUBBLE_LAP) / BUBBLE_LAP;
  const [x, y, radius] = [0, 1, 2].map((axis) =>
    spline(
      BUBBLE_TRACK.map((point) => point[axis]),
      fraction,
    ),
  );
  return { x, y, radius: Math.max(radius, 0) * size };
}

/**
 * The seven bubbles `seconds` after a load began.
 *
 * The two resting bubbles float off. Puffs of three follow, one every two
 * seconds, each bubble fast at first and slowing as it shrinks away.
 * `endedSeconds` is when the load finished, null while it runs: no puff
 * begins after it, and two last bubbles rise into the resting places. A
 * bubble that does not show has radius 0.
 */
export function bubblesAt(
  seconds: number,
  endedSeconds: number | null = null,
): LogoBubble[] {
  const [x, y] = BUBBLE_TRACK[0];
  const gone = { x, y, radius: 0 };
  const resting = [1, 2].map((place) => {
    const left = seconds / (LEAVE[0] + LEAVE[1] * (BUBBLE_LAP - place));
    if (seconds < 0) {
      return bubbleAt(place);
    } else if (left < 1) {
      return bubbleAt(place + (BUBBLE_LAP - place) * left ** 1.5);
    } else {
      return gone;
    }
  });
  const began =
    PUFF_FIRST + PUFF_EVERY * Math.floor((seconds - PUFF_FIRST) / PUFF_EVERY);
  const puff = PUFF.map(([size, sway, late]) => {
    const risen = (seconds - began - late) / PUFF_RISE;
    if (
      seconds >= PUFF_FIRST &&
      (endedSeconds === null || began <= endedSeconds) &&
      risen >= 0 &&
      risen < 1
    ) {
      const bubble = bubbleAt(
        BUBBLE_LAP * (1 - (1 - risen) ** 2.2),
        size * PUFF_SIZE,
      );
      return { ...bubble, x: bubble.x + sway * Math.sin(Math.PI * risen) };
    } else {
      return gone;
    }
  });
  const last = SETTLE.map(([place, late, span]) => {
    if (endedSeconds === null || seconds < endedSeconds + late) {
      return gone;
    } else {
      const arrived = Math.min((seconds - endedSeconds - late) / span, 1);
      return bubbleAt(place * (1 - (1 - arrived) ** 2.4));
    }
  });
  return [...resting, ...puff, ...last];
}

/** The seconds into a load that ended at `endedSeconds` when its bubbles have come to rest. */
export function bubblesRest(endedSeconds: number): number {
  const settled =
    endedSeconds + Math.max(...SETTLE.map(([, late, span]) => late + span));
  if (endedSeconds < PUFF_FIRST) {
    return settled;
  } else {
    const last =
      PUFF_FIRST +
      PUFF_EVERY * Math.floor((endedSeconds - PUFF_FIRST) / PUFF_EVERY);
    return Math.max(
      settled,
      last + PUFF_RISE + Math.max(...PUFF.map(([, , late]) => late)),
    );
  }
}

const NO_PIECE: LogoPiece = {
  x: TRIANGLE_CENTER,
  radius: 0,
  cut: CUT_TRIANGLE,
};

/** The still logo. */
export const LOGO_STILL: LogoFrame = {
  triangle: true,
  windows: [],
  piece: NO_PIECE,
  bubbles: bubblesAt(-1),
  done: true,
};

/**
 * The logo `seconds` after a load began.
 *
 * The play triangle rounds into a window headed for the nose while windows
 * grow in at the tail; they then roll, a lap every two seconds, as puffs of
 * bubbles rise behind the tail ({@link bubblesAt}). `endedSeconds` is when
 * the load finished, null while it runs: at the next whole step, once the
 * start has played out, the window in the first place becomes the triangle
 * as the others shrink.
 */
export function logoAt(
  seconds: number,
  endedSeconds: number | null = null,
): LogoFrame {
  const steps = seconds / STEP;
  const back =
    endedSeconds === null ? null : Math.max(Math.ceil(endedSeconds / STEP), 2);
  const bubbles = bubblesAt(seconds, endedSeconds);
  if (steps < 0) {
    return { ...LOGO_STILL, bubbles };
  } else if (back !== null && steps >= back + END_BLEND) {
    return {
      ...LOGO_STILL,
      bubbles,
      done: endedSeconds !== null && seconds >= bubblesRest(endedSeconds),
    };
  } else {
    const grow = smoothstep(steps / START_BLEND);
    const ending = back !== null && steps >= back;
    const fade = ending ? 1 - smoothstep((steps - back) / END_BLEND) : 1;
    const windows = Array.from({ length: LAP }, (_, index) => {
      // at the start the windows stand at places 2, 3, 0 and 1; the one at 2 is the triangle
      const start = (index + 2) % LAP;
      const { x, radius } = windowAt((steps + start) % LAP);
      // the piece stands in for it, or it would start ahead of the piece
      const waiting = start >= 2 && steps < LAP - start;
      const becoming = ending && Math.round((back + start) % LAP) === 1;
      return { x, radius: waiting || becoming ? 0 : radius * grow * fade };
    });
    const scale = TRIANGLE_INRADIUS / CUT_TRIANGLE;
    let piece = NO_PIECE;
    if (steps < 2) {
      const { x, radius } = windowAt(Math.min(steps + 2, LAP));
      piece = {
        x: mix(TRIANGLE_CENTER, x, grow),
        radius: mix(scale, radius, grow),
        cut: mix(CUT_TRIANGLE, CUT_CIRCLE, grow),
      };
    } else if (ending) {
      const { x, radius } = windowAt(1 + steps - back);
      piece = {
        x: mix(x, TRIANGLE_CENTER, 1 - fade),
        radius: mix(radius, scale, 1 - fade),
        cut: mix(CUT_CIRCLE, CUT_TRIANGLE, 1 - fade),
      };
    }
    return { triangle: false, windows, piece, bubbles, done: false };
  }
}
