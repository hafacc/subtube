import Foundation

/// A point of the logo's drawing.
public struct LogoPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double
}

/// A circle of the logo's drawing.
public struct LogoCircle: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var radius: Double
}

/// Where the logo's drawing sits in its 24 by 24 box.
public struct LogoFraming: Equatable, Sendable {
  public let scale: Double
  public let across: Double
  public let down: Double

  /// Center a box of the drawing in the 24 by 24 box.
  init(left: Double, top: Double, right: Double, bottom: Double, scale: Double) {
    self.scale = scale
    across = 12 - scale * (left + right) / 2
    down = 12 - scale * (top + bottom) / 2
  }
}

/// The logo's drawing, as `design/icons/make.py` has it: a submarine with
/// YouTube's shape for a body, a tail fin, a slanted tower, two bubbles
/// over the tail and the play triangle. Everything is in the drawing's own
/// coordinates, which ``beside`` places in a 24 by 24 box.
public enum Logo {
  /// The outline of body, fin and tower together.
  public static let hull = points(hullPath)
  /// The body's center line, which the triangle and the windows sit on.
  public static let midline = 15.4
  /// The two bubbles, low to high.
  public static let bubbles = [
    LogoCircle(x: 3.2, y: 7.6, radius: 1.5), LogoCircle(x: 5.8, y: 4.2, radius: 1.1),
  ]
  /// The play triangle's corners.
  public static let triangle: [LogoPoint] = {
    let half = (triangleRight - triangleLeft) / 3.0.squareRoot()
    return [
      LogoPoint(x: triangleLeft, y: midline - half), LogoPoint(x: triangleRight, y: midline),
      LogoPoint(x: triangleLeft, y: midline + half),
    ]
  }()

  /// The framing beside the name: fin and body centered across, the body
  /// centered down, the tower and bubbles above.
  public static let beside = LogoFraming(
    left: left, top: top, right: right, bottom: bottom, scale: besideScale)
  /// The share of the box's width that fin and body take in ``beside``.
  public static let besideWidth = besideScale * (right - left) / 24
  /// The share of the box's height that the body takes in ``beside``.
  public static let besideHeight = besideScale * (bottom - top) / 24

  static let triangleLeft = 11.648
  static let triangleRight = 17.248
  static let triangleCenter = (2 * triangleLeft + triangleRight) / 3
  static let triangleInradius = (triangleRight - triangleCenter) / 2

  // the fin's tip and the body's other three sides
  static let left = 1.1
  static let top = 9.2
  static let right = 22.6
  static let bottom = 21.6
  private static let besideScale = 0.95

  private static func points(_ path: String) -> [LogoPoint] {
    path.dropFirst().dropLast().components(separatedBy: " L").compactMap { pair in
      let numbers = pair.split(separator: " ").compactMap { Double($0) }
      return numbers.count == 2 ? LogoPoint(x: numbers[0], y: numbers[1]) : nil
    }
  }

  // make.py's `HULL`: the yellow path of sub-play-centred.svg, less its framing
  private static let hullPath =
    "M17.8 4.8 L17.773 4.593 L17.693 4.4 L17.566 4.234 L17.4 4.107 L17.207 4.027 L17 4 L11.8 4 L11.584 4.03 L11.384 4.117 L11.215 4.254 L11.089 4.432 L11.017 4.638 L10.056 9.281 L9.85 9.29 L9.468 9.31 L9.095 9.332 L8.737 9.356 L7.784 9.448 L7.52 9.485 L7.292 9.526 L7.102 9.57 L7.01 9.598 L6.918 9.63 L6.83 9.665 L6.742 9.704 L6.657 9.747 L6.574 9.794 L6.493 9.844 L6.415 9.898 L6.339 9.955 L6.266 10.015 L6.195 10.078 L6.127 10.144 L6.062 10.213 L6 10.285 L5.941 10.359 L5.886 10.436 L5.833 10.516 L5.784 10.599 L5.738 10.684 L5.695 10.769 L5.657 10.859 L5.622 10.949 L5.591 11.042 L5.564 11.136 L5.52 11.317 L5.48 11.51 L5.444 11.716 L5.411 11.932 L5.38 12.156 L5.353 12.385 L5.352 12.4 L4.009 13.742 L2.133 11.785 L2.01 11.686 L1.865 11.623 L1.709 11.6 L1.552 11.619 L1.405 11.678 L1.279 11.773 L1.182 11.898 L1.121 12.043 L1.1 12.2 L1.1 18.6 L1.121 18.757 L1.182 18.902 L1.279 19.027 L1.405 19.122 L1.552 19.181 L1.709 19.2 L1.865 19.177 L2.01 19.114 L2.133 19.015 L4.009 17.058 L5.352 18.4 L5.353 18.415 L5.38 18.644 L5.411 18.868 L5.444 19.084 L5.48 19.29 L5.52 19.483 L5.564 19.664 L5.591 19.758 L5.622 19.851 L5.657 19.941 L5.695 20.031 L5.738 20.117 L5.784 20.201 L5.833 20.284 L5.886 20.364 L5.941 20.441 L6 20.515 L6.062 20.587 L6.127 20.656 L6.195 20.722 L6.266 20.785 L6.339 20.845 L6.415 20.902 L6.493 20.956 L6.574 21.006 L6.657 21.053 L6.742 21.096 L6.83 21.135 L6.918 21.17 L7.01 21.202 L7.102 21.23 L7.292 21.274 L7.52 21.315 L7.784 21.352 L8.076 21.386 L8.396 21.417 L8.737 21.444 L9.095 21.468 L9.468 21.49 L9.85 21.51 L10.236 21.526 L10.625 21.542 L11.01 21.554 L11.388 21.565 L12.106 21.581 L12.748 21.591 L13.277 21.596 L13.793 21.6 L14.007 21.6 L15.052 21.591 L15.361 21.587 L16.045 21.573 L16.791 21.554 L17.175 21.542 L17.564 21.526 L17.951 21.51 L18.332 21.49 L18.705 21.468 L19.063 21.444 L19.404 21.417 L19.724 21.386 L20.016 21.352 L20.28 21.315 L20.508 21.274 L20.698 21.23 L20.79 21.202 L20.882 21.17 L20.97 21.135 L21.058 21.096 L21.144 21.053 L21.226 21.006 L21.307 20.956 L21.385 20.902 L21.461 20.845 L21.534 20.785 L21.605 20.722 L21.673 20.656 L21.738 20.587 L21.8 20.515 L21.859 20.441 L21.914 20.364 L21.967 20.284 L22.016 20.201 L22.062 20.117 L22.105 20.031 L22.143 19.941 L22.178 19.851 L22.209 19.758 L22.236 19.664 L22.28 19.483 L22.32 19.29 L22.356 19.084 L22.389 18.868 L22.42 18.644 L22.447 18.415 L22.47 18.181 L22.492 17.945 L22.511 17.708 L22.528 17.473 L22.543 17.241 L22.555 17.014 L22.565 16.795 L22.581 16.385 L22.587 16.199 L22.595 15.872 L22.6 15.458 L22.6 15.342 L22.597 15.064 L22.59 14.773 L22.581 14.415 L22.564 14.005 L22.554 13.786 L22.542 13.559 L22.527 13.327 L22.51 13.092 L22.491 12.855 L22.47 12.619 L22.446 12.385 L22.419 12.156 L22.389 11.932 L22.356 11.716 L22.32 11.51 L22.28 11.317 L22.236 11.136 L22.209 11.042 L22.178 10.949 L22.143 10.859 L22.105 10.769 L22.062 10.684 L22.016 10.599 L21.967 10.516 L21.914 10.436 L21.859 10.359 L21.8 10.285 L21.738 10.213 L21.673 10.144 L21.605 10.078 L21.534 10.015 L21.461 9.955 L21.385 9.898 L21.307 9.844 L21.226 9.794 L21.144 9.747 L21.058 9.704 L20.97 9.665 L20.882 9.63 L20.79 9.598 L20.698 9.57 L20.508 9.526 L20.28 9.485 L20.016 9.448 L19.063 9.356 L18.705 9.332 L18.332 9.31 L17.951 9.29 L17.8 9.284Z"
}

/// The play triangle on its way to or from being a window: a circle cut by
/// a triangle around its center.
public struct LogoPiece: Equatable, Sendable {
  /// The circle; radius 0 when the piece does not show.
  public var circle: LogoCircle
  /// The cutting triangle's inradius, in circle radii.
  public var cut: Double

  /// The cutting triangle's corners.
  public var corners: [LogoPoint] {
    let reach = circle.radius * cut
    return [
      LogoPoint(x: circle.x + 2 * reach, y: circle.y),
      LogoPoint(x: circle.x - reach, y: circle.y + 3.0.squareRoot() * reach),
      LogoPoint(x: circle.x - reach, y: circle.y - 3.0.squareRoot() * reach),
    ]
  }
}

/// The inside of the logo at one moment.
public struct LogoMotion: Equatable, Sendable {
  /// Whether the still play triangle shows.
  public let triangle: Bool
  /// The rolling windows; radius 0 when one does not show.
  public let windows: [LogoCircle]
  /// The triangle in motion.
  public let piece: LogoPiece
}

/// The logo at one moment: its inside and its bubbles.
public struct LogoFrame: Equatable, Sendable {
  public let motion: LogoMotion
  public let bubbles: [LogoCircle]

  /// The logo when nothing loads.
  public static let still = LogoFrame(motion: logoMotion(steps: -1), bubbles: Logo.bubbles)
}

// seconds for a window to reach the next one's place
private let step = 0.5
// each window's x and radius: grown from nothing at the tail, through the
// three places windows stand still at, gone past the nose
private let windowTrack = [(5.4, 0.0), (9.3, 1.15), (13.0, 1.55), (17.6, 2.0), (22.6, 2.4)]
// steps past the last window's place for it to shrink away
private let shrink = 0.6
// steps before a window is back where it started
private let lap = windowTrack.count - 1
// steps for the triangle to become a window
private let startBlend = 1.5
// steps for a window to settle as the triangle
private let endBlend = 1.0
// out from behind the tail, through the two resting places, gone
private let bubbleTrack =
  [LogoCircle(x: 2.2, y: 10.8, radius: 0)] + Logo.bubbles + [LogoCircle(x: 7.4, y: 2.9, radius: 0)]
private let bubbleLap = bubbleTrack.count - 1
// seconds a resting bubble takes to float off: a base, and more per place it has left
private let leave = (base: 0.25, perPlace: 0.45)
// seconds into a load for the first puff, and from one puff to the next
private let puffFirst = 0.1
private let puffEvery = 2.0
// seconds a puff's bubble takes to rise and vanish
private let puffRise = 1.5
// a puff's largest bubble, in track radii
private let puffSize = 1.1
// each bubble of a puff: its size, its sway and how many seconds late it leaves
private let puff = [
  (size: 1.0, sway: 0.0, late: 0.0), (size: 0.65, sway: 0.9, late: 0.13),
  (size: 0.5, sway: -0.8, late: 0.26),
]
// the last bubbles: the place each rises to, seconds after the load ends, seconds to get there
private let settle = [(place: 2.0, late: 0.0, span: 1.0), (place: 1.0, late: 0.35, span: 0.8)]
// the cutting triangle's inradius, in circle radii, when the piece is the
// play triangle and once the circle sits wholly inside it
private let cutTriangle = 0.48
private let cutCircle = 1.06

/// Catmull-Rom through equally spaced points; `fraction` from 0 to 1.
func spline(_ points: [Double], _ fraction: Double) -> Double {
  let count = points.count
  let padded =
    [2 * points[0] - points[1]] + points + [2 * points[count - 1] - points[count - 2]]
  let position = fraction * Double(count - 1)
  let segment = min(Int(position), count - 2)
  let local = position - Double(segment)
  let before = padded[segment]
  let start = padded[segment + 1]
  let end = padded[segment + 2]
  let after = padded[segment + 3]
  return 0.5
    * (2 * start
      + (end - before) * local
      + (2 * before - 5 * start + 4 * end - after) * local * local
      + (3 * start - before - 3 * end + after) * local * local * local)
}

/// Ease from 0 to 1.
func smoothstep(_ value: Double) -> Double {
  let clamped = min(max(value, 0), 1)
  return clamped * clamped * (3 - 2 * clamped)
}

private func mix(_ start: Double, _ end: Double, _ weight: Double) -> Double {
  start + (end - start) * weight
}

/// A window `position` steps along its track.
func logoWindow(at position: Double) -> LogoCircle {
  let fraction = position / Double(lap)
  var radius = max(spline(windowTrack.map { $0.1 }, fraction), 0)
  if position > Double(lap - 1) {
    radius *= 1 - smoothstep((position - Double(lap - 1)) / shrink)
  }
  return LogoCircle(x: spline(windowTrack.map { $0.0 }, fraction), y: Logo.midline, radius: radius)
}

/// A bubble `position` places along its track, `size` times as large.
func logoBubble(at position: Double, size: Double = 1) -> LogoCircle {
  let fraction = min(max(position, 0), Double(bubbleLap)) / Double(bubbleLap)
  return LogoCircle(
    x: spline(bubbleTrack.map(\.x), fraction),
    y: spline(bubbleTrack.map(\.y), fraction),
    radius: max(spline(bubbleTrack.map(\.radius), fraction), 0) * size)
}

/// The seven bubbles `seconds` after a load began.
///
/// The two resting bubbles float off. Puffs of three follow, one every two
/// seconds, each bubble fast at first and slowing as it shrinks away.
/// `endedSeconds` is how long the load took, nil while it runs: no puff
/// begins after it, and two last bubbles rise into the resting places. A
/// bubble that does not show has radius 0.
func logoBubbles(seconds: Double, endedSeconds: Double? = nil) -> [LogoCircle] {
  let gone = LogoCircle(x: bubbleTrack[0].x, y: bubbleTrack[0].y, radius: 0)
  let top = Double(bubbleLap)
  let resting = [1.0, 2.0].map { place -> LogoCircle in
    let left = seconds / (leave.base + leave.perPlace * (top - place))
    if seconds < 0 {
      return logoBubble(at: place)
    } else if left < 1 {
      return logoBubble(at: place + (top - place) * pow(left, 1.5))
    } else {
      return gone
    }
  }
  let began = puffFirst + puffEvery * ((seconds - puffFirst) / puffEvery).rounded(.down)
  let begins = seconds >= puffFirst && endedSeconds.map { began <= $0 } ?? true
  let puffed = puff.map { bubble -> LogoCircle in
    let risen = (seconds - began - bubble.late) / puffRise
    if begins && risen >= 0 && risen < 1 {
      var circle = logoBubble(at: top * (1 - pow(1 - risen, 2.2)), size: bubble.size * puffSize)
      circle.x += bubble.sway * sin(.pi * risen)
      return circle
    } else {
      return gone
    }
  }
  let last = settle.map { bubble -> LogoCircle in
    if let endedSeconds, seconds >= endedSeconds + bubble.late {
      let arrived = min((seconds - endedSeconds - bubble.late) / bubble.span, 1)
      return logoBubble(at: bubble.place * (1 - pow(1 - arrived, 2.4)))
    } else {
      return gone
    }
  }
  return resting + puffed + last
}

/// How many seconds after it began the bubbles of a load that took
/// `endedSeconds` have come to rest.
func logoBubblesRest(endedSeconds: Double) -> Double {
  let settled = endedSeconds + (settle.map { $0.late + $0.span }.max() ?? 0)
  if endedSeconds < puffFirst {
    return settled
  } else {
    let last = puffFirst + puffEvery * ((endedSeconds - puffFirst) / puffEvery).rounded(.down)
    return max(settled, last + puffRise + (puff.map(\.late).max() ?? 0))
  }
}

/// The step at which a load that ended `ended` steps in starts back to the
/// play triangle: the next whole step, once the start has played out.
private func turnsBack(ended: Double) -> Double {
  max(ended.rounded(.up), 2)
}

/// The logo's inside `steps` steps after a load began.
///
/// The play triangle rounds into a window headed for the nose while windows
/// grow in at the tail; they then roll, a lap every four steps. `ended` is
/// how many steps in the load finished: from the step it turns back at, the
/// window in the first place becomes the triangle as the others shrink.
func logoMotion(steps: Double, ended: Double? = nil) -> LogoMotion {
  let back = ended.map(turnsBack)
  let resting = LogoPiece(
    circle: LogoCircle(x: Logo.triangleCenter, y: Logo.midline, radius: 0), cut: cutTriangle)
  if steps < 0 || back.map({ steps >= $0 + endBlend }) ?? false {
    return LogoMotion(
      triangle: true,
      windows: Array(repeating: LogoCircle(x: 0, y: Logo.midline, radius: 0), count: lap),
      piece: resting)
  } else {
    let grow = smoothstep(steps / startBlend)
    let windows = (0..<lap).map { index in
      // at the start the windows stand at places 2, 3, 0 and 1; the one at 2 is the triangle
      let start = (index + 2) % lap
      var window = logoWindow(
        at: (steps + Double(start)).truncatingRemainder(dividingBy: Double(lap)))
      if start >= 2 && steps < Double(lap - start) {
        // the piece stands in for it, or it would start ahead of the piece
        window.radius = 0
      }
      window.radius *= grow
      if let back, steps >= back {
        let first = (Int(back) + start) % lap == 1
        window.radius = first ? 0 : window.radius * (1 - smoothstep((steps - back) / endBlend))
      }
      return window
    }
    let scale = Logo.triangleInradius / cutTriangle
    var piece = resting
    if steps < 2 {
      let window = logoWindow(at: min(steps + 2, Double(lap)))
      piece.circle.x = mix(Logo.triangleCenter, window.x, grow)
      piece.circle.radius = mix(scale, window.radius, grow)
      piece.cut = mix(cutTriangle, cutCircle, grow)
    } else if let back, steps >= back {
      let settle = smoothstep((steps - back) / endBlend)
      let window = logoWindow(at: 1 + steps - back)
      piece.circle.x = mix(window.x, Logo.triangleCenter, settle)
      piece.circle.radius = mix(window.radius, scale, settle)
      piece.cut = mix(cutCircle, cutTriangle, settle)
    }
    return LogoMotion(triangle: false, windows: windows, piece: piece)
  }
}

/// The logo `seconds` after a load began.
///
/// While the load runs the play triangle becomes one of four windows that
/// roll from tail to nose, and puffs of bubbles rise behind the tail.
/// `endedSeconds` is how long the load took, nil while it runs: the windows
/// then give way to the triangle and two last bubbles rise into the resting
/// places, and from ``logoSettles(endedSeconds:)`` on the logo is still.
public func logoFrame(seconds: Double, endedSeconds: Double? = nil) -> LogoFrame {
  LogoFrame(
    motion: logoMotion(steps: seconds / step, ended: endedSeconds.map { $0 / step }),
    bubbles: logoBubbles(seconds: seconds, endedSeconds: endedSeconds).filter { $0.radius > 0 })
}

/// How many seconds after it began the logo of a load that took
/// `endedSeconds` is still again.
public func logoSettles(endedSeconds: Double) -> Double {
  max(
    (turnsBack(ended: endedSeconds / step) + endBlend) * step,
    logoBubblesRest(endedSeconds: endedSeconds))
}
