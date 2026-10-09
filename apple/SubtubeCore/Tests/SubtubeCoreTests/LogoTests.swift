import Foundation
import Testing

@testable import SubtubeCore

/// The numbers `design/icons/make.py` gives, to three places.
@Suite struct LogoTests {
  private func near(_ value: Double, _ expected: Double) -> Bool {
    abs(value - expected) < 0.0006
  }

  private func near(_ circle: LogoCircle, _ x: Double, _ radius: Double) -> Bool {
    near(circle.x, x) && near(circle.radius, radius) && circle.y == Logo.midline
  }

  private func near(_ windows: [LogoCircle], _ expected: [(Double, Double)]) -> Bool {
    windows.count == expected.count
      && zip(windows, expected).allSatisfy { window, pair in near(window, pair.0, pair.1) }
  }

  private func near(_ piece: LogoPiece, _ x: Double, _ radius: Double, _ cut: Double) -> Bool {
    near(piece.circle, x, radius) && near(piece.cut, cut)
  }

  @Test func theOutlinesAreReadWhole() {
    #expect(Logo.hull.count == 232)
    #expect(Logo.hull.map(\.x).min() == Logo.left)
    #expect(Logo.hull.map(\.y).min() == 4)
    #expect(Logo.hull.map(\.x).max() == Logo.right)
    #expect(Logo.hull.map(\.y).max() == Logo.bottom)
  }

  @Test func besideTheNameFinAndBodyAreCentered() {
    #expect(Logo.beside.scale == 0.95)
    #expect(near(Logo.beside.across, 0.7425))
    #expect(near(Logo.beside.down, -2.63))
    #expect(near(Logo.besideWidth, 0.851))
    #expect(near(Logo.besideHeight, 0.4908))
  }

  @Test func theTriangleIsEquilateralAroundItsCenter() {
    #expect(near(Logo.triangleCenter, 13.5147))
    #expect(near(Logo.triangleInradius, 1.8667))
    let still = LogoPiece(
      circle: LogoCircle(
        x: Logo.triangleCenter, y: Logo.midline, radius: Logo.triangleInradius / 0.48),
      cut: 0.48)
    let corners = [still.corners[2], still.corners[0], still.corners[1]]
    for (corner, expected) in zip(corners, Logo.triangle) {
      #expect(near(corner.x, expected.x) && near(corner.y, expected.y))
    }
  }

  @Test func aWindowGrowsThroughTheStillPlacesAndShrinksAway() {
    #expect(near(logoWindow(at: 0), 5.4, 0))
    #expect(near(logoWindow(at: 0.5), 7.363, 0.622))
    #expect(near(logoWindow(at: 1), 9.3, 1.15))
    #expect(near(logoWindow(at: 1.5), 11.106, 1.394))
    #expect(near(logoWindow(at: 2), 13, 1.55))
    #expect(near(logoWindow(at: 2.5), 15.219, 1.775))
    #expect(near(logoWindow(at: 3), 17.6, 2))
    #expect(near(logoWindow(at: 3.3), 19.071, 1.062))
    #expect(near(logoWindow(at: 3.8), 21.594, 0))
  }

  @Test func aBubbleRisesAlongItsTrack() {
    let expected = [
      (0.5, 2.6, 9.213, 0.869), (1.5, 4.463, 5.781, 1.462), (2.5, 6.662, 3.419, 0.594),
    ]
    for (position, x, y, radius) in expected {
      let bubble = logoBubble(at: position)
      #expect(near(bubble.x, x) && near(bubble.y, y) && near(bubble.radius, radius))
    }
    #expect(logoBubble(at: 1) == Logo.bubbles[0])
    #expect(logoBubble(at: 2) == Logo.bubbles[1])
  }

  @Test func beforeALoadTheTriangleShows() {
    let motion = logoMotion(steps: -1)
    #expect(motion.triangle)
    #expect(motion.windows.allSatisfy { $0.radius == 0 })
    #expect(motion.piece.circle.radius == 0)
  }

  @Test func theTriangleRoundsIntoAWindowWhileWindowsGrowIn() {
    let start = logoMotion(steps: 0)
    #expect(!start.triangle)
    #expect(near(start.windows, [(13.0, 0), (17.6, 0), (5.4, 0), (9.3, 0)]))
    #expect(near(start.piece, 13.515, 3.889, 0.48))

    let early = logoMotion(steps: 0.75)
    #expect(near(early.windows, [(16.401, 0), (21.341, 0), (8.339, 0.458), (12.016, 0.732)]))
    #expect(near(early.piece, 14.958, 2.889, 0.77))

    let rounded = logoMotion(steps: 1.5)
    #expect(near(rounded.windows, [(20.075, 0), (7.363, 0.622), (11.106, 1.394), (15.219, 1.775)]))
    #expect(near(rounded.piece, 20.075, 0.163, 1.06))
  }

  @Test func theWindowsRoll() {
    let first = logoMotion(steps: 2.5)
    #expect(near(first.windows, [(7.363, 0.622), (11.106, 1.394), (15.219, 1.775), (20.075, 0.163)]))
    #expect(first.piece.circle.radius == 0)

    let later = logoMotion(steps: 5.25)
    #expect(near(later.windows, [(18.822, 1.312), (6.38, 0.305), (10.218, 1.302), (14.077, 1.66)]))
    #expect(later.piece.circle.radius == 0)
    #expect(logoMotion(steps: 6.5).windows == first.windows)
  }

  @Test func afterTheLoadAWindowSettlesAsTheTriangle() {
    #expect(logoMotion(steps: 5.9, ended: 5.3) == logoMotion(steps: 5.9))
    let settling = logoMotion(steps: 6.5, ended: 5.3)
    #expect(!settling.triangle)
    #expect(near(settling.windows, [(7.363, 0.311), (11.106, 0), (15.219, 0.888), (20.075, 0.082)]))
    #expect(near(settling.piece, 12.31, 2.641, 0.77))
    #expect(logoMotion(steps: 7.2, ended: 5.3).triangle)
  }

  @Test func aLoadThatEndsEarlyLetsTheStartPlayOut() {
    let start = logoMotion(steps: 0.5, ended: 0.2)
    #expect(near(start.windows, [(15.219, 0), (20.075, 0), (7.363, 0.161), (11.106, 0.361)]))
    #expect(near(start.piece, 13.956, 3.341, 0.63))

    let settling = logoMotion(steps: 2.4, ended: 0.2)
    #expect(near(settling.windows, [(6.97, 0.321), (10.751, 0), (14.756, 1.12), (19.571, 0.363)]))
    #expect(near(settling.piece, 11.724, 2.251, 0.856))
    #expect(logoMotion(steps: 3, ended: 0.2).triangle)
  }

  @Test func aStepIsHalfASecond() {
    #expect(logoFrame(seconds: 1.25).motion == logoMotion(steps: 2.5))
    #expect(
      logoFrame(seconds: 3.25, endedSeconds: 2.65).motion == logoMotion(steps: 6.5, ended: 5.3))
    #expect(LogoFrame.still.motion.triangle)
    #expect(LogoFrame.still.bubbles == Logo.bubbles)
  }

  private func near(_ bubbles: [LogoCircle], _ expected: [(Double, Double, Double)]) -> Bool {
    bubbles.count == expected.count
      && zip(bubbles, expected).allSatisfy { bubble, numbers in
        near(bubble.x, numbers.0) && near(bubble.y, numbers.1) && near(bubble.radius, numbers.2)
      }
  }

  @Test func puffsOfBubblesRiseAndTwoLastOnesSettle() {
    let gone = (2.2, 10.8, 0.0)
    #expect(
      near(
        logoBubbles(seconds: -1),
        [(3.2, 7.6, 1.5), (5.8, 4.2, 1.1), gone, gone, gone, gone, gone]))
    #expect(
      near(
        logoBubbles(seconds: 0.4),
        [
          (4.202, 6.115, 1.506), (6.561, 3.492, 0.674), (3.545, 7.031, 1.706),
          (3.094, 8.583, 0.848), (2.286, 10.248, 0.156), gone, gone,
        ]))
    #expect(
      near(
        logoBubbles(seconds: 2.5),
        [
          gone, gone, (4.415, 5.841, 1.618), (3.8, 7.393, 1.093), (2.437, 8.953, 0.554), gone,
          gone,
        ]))
    #expect(
      near(
        logoBubbles(seconds: 3, endedSeconds: 2.6),
        [
          gone, gone, (6.809, 3.319, 0.52), (7.388, 3.547, 0.52), (5.255, 3.951, 0.551),
          (4.21, 6.105, 1.505), (2.329, 10.343, 0.232),
        ]))
    #expect(
      near(
        logoBubbles(seconds: 4, endedSeconds: 2.6),
        [gone, gone, gone, gone, gone, (5.8, 4.2, 1.1), (3.2, 7.6, 1.5)]))
    #expect(logoBubbles(seconds: 0.5, endedSeconds: 0.05)[2...4].allSatisfy { $0.radius == 0 })
  }

  @Test func theLogoIsStillOnceTheTriangleIsBackAndTheBubblesRest() {
    for (ended, rest) in [(0.05, 1.2), (0.3, 1.86), (2.6, 3.86), (4, 5.15), (4.2, 5.86)] {
      #expect(near(logoBubblesRest(endedSeconds: ended), rest))
    }
    #expect(near(logoSettles(endedSeconds: 2.65), 3.86))
    #expect(near(logoSettles(endedSeconds: 0.1), 1.86))
    #expect(logoFrame(seconds: 3.85, endedSeconds: 2.65).bubbles.count == 3)
    for ended in [0.1, 2.65, 3, 7.2] {
      let frame = logoFrame(seconds: logoSettles(endedSeconds: ended), endedSeconds: ended)
      #expect(frame.motion.triangle)
      #expect(Set(frame.bubbles.map(\.x)) == Set(Logo.bubbles.map(\.x)))
    }
  }
}
