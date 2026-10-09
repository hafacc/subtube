import { describe, expect, test } from "bun:test";
import { BUBBLES, TRIANGLE } from "./logo-drawing";
import {
  BESIDE,
  bubblesAt,
  bubblesRest,
  LOGO_STILL,
  logoAt,
  MIDLINE,
  STEP,
  windowAt,
} from "./logo-motion";

// the numbers design/icons/make.py gives
describe("windowAt", () => {
  test.each([
    [0.5, 7.363, 0.622],
    [1.5, 11.106, 1.394],
    [2.5, 15.219, 1.775],
    [3.3, 19.071, 1.062],
    [3.8, 21.594, 0],
  ])("at %d", (position, x, radius) => {
    const found = windowAt(position);
    expect(found.x).toBeCloseTo(x, 3);
    expect(found.radius).toBeCloseTo(radius, 3);
  });
});

describe("bubblesAt", () => {
  function rounded(seconds: number, ended: number | null = null) {
    return bubblesAt(seconds, ended).map(({ x, y, radius }) =>
      [x, y, radius].map((value) => Number(value.toFixed(3))),
    );
  }
  const gone = [2.2, 10.8, 0];

  test("rests as two bubbles before a load", () => {
    expect(rounded(-1)).toEqual([
      [3.2, 7.6, 1.5],
      [5.8, 4.2, 1.1],
      gone,
      gone,
      gone,
      gone,
      gone,
    ]);
  });

  test("floats the resting bubbles off as the first puff leaves", () => {
    expect(rounded(0.4)).toEqual([
      [4.202, 6.115, 1.506],
      [6.561, 3.492, 0.674],
      [3.545, 7.031, 1.706],
      [3.094, 8.583, 0.848],
      [2.286, 10.248, 0.156],
      gone,
      gone,
    ]);
  });

  test("puffs again every two seconds", () => {
    expect(rounded(2.5)).toEqual([
      gone,
      gone,
      [4.415, 5.841, 1.618],
      [3.8, 7.393, 1.093],
      [2.437, 8.953, 0.554],
      gone,
      gone,
    ]);
  });

  test("lets a puff finish while the last two bubbles rise into place", () => {
    expect(rounded(3, 2.6)).toEqual([
      gone,
      gone,
      [6.809, 3.319, 0.52],
      [7.388, 3.547, 0.52],
      [5.255, 3.951, 0.551],
      [4.21, 6.105, 1.505],
      [2.329, 10.343, 0.232],
    ]);
    expect(rounded(4, 2.6)).toEqual([
      gone,
      gone,
      gone,
      gone,
      gone,
      [5.8, 4.2, 1.1],
      [3.2, 7.6, 1.5],
    ]);
  });

  test("starts no puff after the load ends", () => {
    expect(rounded(0.5, 0.05).slice(2, 5)).toEqual([gone, gone, gone]);
  });
});

describe("bubblesRest", () => {
  test.each([
    [0.05, 1.2],
    [0.3, 1.86],
    [2.6, 3.86],
    [4, 5.15],
    [4.2, 5.86],
  ])("after a load of %d seconds", (ended, rest) => {
    expect(bubblesRest(ended)).toBeCloseTo(rest, 6);
  });
});

describe("logoAt", () => {
  function rounded(steps: number, ended: number | null = null) {
    const frame = logoAt(steps * STEP, ended === null ? null : ended * STEP);
    return {
      triangle: frame.triangle,
      windows: frame.windows.map(({ x, radius }) => [
        Number(x.toFixed(3)),
        Number(radius.toFixed(3)),
      ]),
      piece: [frame.piece.x, frame.piece.radius, frame.piece.cut].map((value) =>
        Number(value.toFixed(3)),
      ),
    };
  }

  test("is the still logo before a load", () => {
    expect(logoAt(-0.5)).toEqual(LOGO_STILL);
  });

  test("starts with the piece as the play triangle", () => {
    expect(rounded(0)).toEqual({
      triangle: false,
      windows: [
        [13, 0],
        [17.6, 0],
        [5.4, 0],
        [9.3, 0],
      ],
      piece: [13.515, 3.889, 0.48],
    });
  });

  test("rounds the triangle while windows grow in", () => {
    expect(rounded(0.75)).toEqual({
      triangle: false,
      windows: [
        [16.401, 0],
        [21.341, 0],
        [8.339, 0.458],
        [12.016, 0.732],
      ],
      piece: [14.958, 2.889, 0.77],
    });
    expect(rounded(1.5).piece).toEqual([20.075, 0.163, 1.06]);
  });

  test("rolls the windows", () => {
    expect(rounded(5.25)).toEqual({
      triangle: false,
      windows: [
        [18.822, 1.312],
        [6.38, 0.305],
        [10.218, 1.302],
        [14.077, 1.66],
      ],
      piece: [13.515, 0, 0.48],
    });
  });

  test("turns the first window back into the triangle at the next whole step", () => {
    expect(rounded(5.9, 5.3).piece[1]).toBe(0);
    expect(rounded(6.5, 5.3)).toEqual({
      triangle: false,
      windows: [
        [7.363, 0.311],
        [11.106, 0],
        [15.219, 0.888],
        [20.075, 0.082],
      ],
      piece: [12.31, 2.641, 0.77],
    });
    expect(rounded(7.2, 5.3).triangle).toBe(true);
  });

  test("plays the start out when the load ends at once", () => {
    expect(rounded(0.5, 0.2).piece).toEqual([13.956, 3.341, 0.63]);
    expect(rounded(2.4, 0.2).piece).toEqual([11.724, 2.251, 0.856]);
  });

  test("is done once the bubbles have come to rest", () => {
    expect(logoAt(3.8, 2.6).done).toBe(false);
    const rested = logoAt(3.9, 2.6);
    expect(rested.done).toBe(true);
    expect(rested.triangle).toBe(true);
  });
});

describe("the still logo", () => {
  function placed(x: number, y: number): [number, number] {
    return [BESIDE.scale * x + BESIDE.across, BESIDE.scale * y + BESIDE.down];
  }

  test("has logo.svg's bubbles", () => {
    const still = LOGO_STILL.bubbles.filter(({ radius }) => radius > 0);
    expect(still).toHaveLength(BUBBLES.length);
    for (const [index, [x, y, radius]] of BUBBLES.entries()) {
      const [stillX, stillY] = placed(still[index].x, still[index].y);
      expect(stillX).toBeCloseTo(x, 2);
      expect(stillY).toBeCloseTo(y, 2);
      expect(still[index].radius * BESIDE.scale).toBeCloseTo(radius, 2);
    }
  });

  test("has logo.svg's triangle where the piece starts", () => {
    const { x, radius, cut } = logoAt(0).piece;
    const [tipX, tipY] = placed(x + 2 * cut * radius, MIDLINE);
    expect(TRIANGLE).toContain(`L${tipX.toFixed(3)} ${Math.round(tipY)}`);
  });
});
