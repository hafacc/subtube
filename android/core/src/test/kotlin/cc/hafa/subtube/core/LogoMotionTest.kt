package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// the expected numbers are design/icons/make.py's, rounded to three places
private const val ROUNDING = 0.00051

private fun assertWindow(x: Double, radius: Double, actual: LogoWindow) {
    assertEquals(x, actual.x, ROUNDING, "x of $actual")
    assertEquals(radius, actual.radius, ROUNDING, "radius of $actual")
}

private fun assertBubble(x: Double, y: Double, radius: Double, actual: LogoBubble) {
    assertEquals(x, actual.x, ROUNDING, "x of $actual")
    assertEquals(y, actual.y, ROUNDING, "y of $actual")
    assertEquals(radius, actual.radius, ROUNDING, "radius of $actual")
}

private fun assertWindows(expected: List<Pair<Double, Double>>, actual: LogoMotion) {
    assertFalse(actual.triangle)
    assertEquals(expected.size, actual.windows.size)
    for ((want, window) in expected.zip(actual.windows)) {
        val (x, radius) = want
        assertWindow(x, radius, window)
    }
}

private fun assertPiece(x: Double, radius: Double, cut: Double, actual: LogoMotion) {
    assertEquals(x, actual.piece.x, ROUNDING, "x of ${actual.piece}")
    assertEquals(radius, actual.piece.radius, ROUNDING, "radius of ${actual.piece}")
    assertEquals(cut, actual.piece.cut, ROUNDING, "cut of ${actual.piece}")
}

class LogoMotionTest {
    @Test
    fun theTriangleIsWhereTheDrawingHasIt() {
        assertEquals(13.5147, LOGO_TRIANGLE_CENTER, 0.00005)
        assertEquals(1.8667, LOGO_TRIANGLE_INRADIUS, 0.00005)
    }

    @Test
    fun splineGoesThroughItsPoints() {
        val points = listOf(1.0, 4.0, 2.0, 8.0)
        assertEquals(1.0, spline(points, 0.0), 1e-12)
        assertEquals(4.0, spline(points, 1.0 / 3), 1e-12)
        assertEquals(2.0, spline(points, 2.0 / 3), 1e-12)
        assertEquals(8.0, spline(points, 1.0), 1e-12)
    }

    @Test
    fun smoothstepEasesAndStaysWithinItsEnds() {
        assertEquals(0.0, smoothstep(-1.0))
        assertEquals(0.15625, smoothstep(0.25))
        assertEquals(0.5, smoothstep(0.5))
        assertEquals(1.0, smoothstep(2.0))
    }

    @Test
    fun aWindowGrowsFromTheTailAndShrinksAwayPastTheNose() {
        assertWindow(5.4, 0.0, logoWindowAt(0.0))
        assertWindow(7.363, 0.622, logoWindowAt(0.5))
        assertWindow(9.3, 1.15, logoWindowAt(1.0))
        assertWindow(11.106, 1.394, logoWindowAt(1.5))
        assertWindow(13.0, 1.55, logoWindowAt(2.0))
        assertWindow(15.219, 1.775, logoWindowAt(2.5))
        assertWindow(17.6, 2.0, logoWindowAt(3.0))
        assertWindow(19.071, 1.062, logoWindowAt(3.3))
        assertWindow(21.594, 0.0, logoWindowAt(3.8))
    }

    @Test
    fun aBubbleRisesAlongItsTrack() {
        assertBubble(2.6, 9.213, 0.869, logoBubbleAt(0.5))
        assertBubble(4.463, 5.781, 1.462, logoBubbleAt(1.5))
        assertBubble(6.662, 3.419, 0.594, logoBubbleAt(2.5))
    }

    private fun assertBubbles(expected: List<Triple<Double, Double, Double>>, actual: List<LogoBubble>) {
        assertEquals(expected.size, actual.size)
        expected.zip(actual).forEach { (numbers, bubble) -> assertBubble(numbers.first, numbers.second, numbers.third, bubble) }
    }

    @Test
    fun puffsOfBubblesRiseAndTwoLastOnesSettle() {
        val gone = Triple(2.2, 10.8, 0.0)
        assertBubbles(listOf(Triple(3.2, 7.6, 1.5), Triple(5.8, 4.2, 1.1), gone, gone, gone, gone, gone), logoBubbles(-1.0))
        assertBubbles(
            listOf(
                Triple(4.202, 6.115, 1.506), Triple(6.561, 3.492, 0.674), Triple(3.545, 7.031, 1.706),
                Triple(3.094, 8.583, 0.848), Triple(2.286, 10.248, 0.156), gone, gone,
            ),
            logoBubbles(0.4),
        )
        assertBubbles(
            listOf(gone, gone, Triple(4.415, 5.841, 1.618), Triple(3.8, 7.393, 1.093), Triple(2.437, 8.953, 0.554), gone, gone),
            logoBubbles(2.5),
        )
        assertBubbles(
            listOf(
                gone, gone, Triple(6.809, 3.319, 0.52), Triple(7.388, 3.547, 0.52), Triple(5.255, 3.951, 0.551),
                Triple(4.21, 6.105, 1.505), Triple(2.329, 10.343, 0.232),
            ),
            logoBubbles(3.0, endedSeconds = 2.6),
        )
        assertBubbles(
            listOf(gone, gone, gone, gone, gone, Triple(5.8, 4.2, 1.1), Triple(3.2, 7.6, 1.5)),
            logoBubbles(4.0, endedSeconds = 2.6),
        )
        assertTrue(logoBubbles(0.5, endedSeconds = 0.05).subList(2, 5).all { bubble -> bubble.radius == 0.0 })
    }

    @Test
    fun beforeALoadTheTriangleShows() {
        val still = logoMotion(-1.0)
        assertTrue(still.triangle)
        assertTrue(still.windows.all { window -> window.radius == 0.0 })
        assertEquals(0.0, still.piece.radius)
    }

    @Test
    fun aLoadStartsWithTheTriangleRoundingIntoAWindow() {
        val start = logoMotion(0.0)
        assertWindows(listOf(13.0 to 0.0, 17.6 to 0.0, 5.4 to 0.0, 9.3 to 0.0), start)
        assertPiece(13.515, 3.889, 0.48, start)

        val early = logoMotion(0.75)
        assertWindows(listOf(16.401 to 0.0, 21.341 to 0.0, 8.339 to 0.458, 12.016 to 0.732), early)
        assertPiece(14.958, 2.889, 0.77, early)

        val late = logoMotion(1.5)
        assertWindows(listOf(20.075 to 0.0, 7.363 to 0.622, 11.106 to 1.394, 15.219 to 1.775), late)
        assertPiece(20.075, 0.163, 1.06, late)
    }

    @Test
    fun whileItLoadsTheWindowsRoll() {
        val rolling = logoMotion(2.5)
        assertWindows(listOf(7.363 to 0.622, 11.106 to 1.394, 15.219 to 1.775, 20.075 to 0.163), rolling)
        assertEquals(0.0, rolling.piece.radius)

        val later = logoMotion(5.25)
        assertWindows(listOf(18.822 to 1.312, 6.38 to 0.305, 10.218 to 1.302, 14.077 to 1.66), later)
        assertEquals(0.0, later.piece.radius)
    }

    @Test
    fun aFinishedLoadSettlesBackToTheTriangleAtTheNextWholeStep() {
        assertEquals(logoMotion(5.9), logoMotion(5.9, ended = 5.3))

        val settling = logoMotion(6.5, ended = 5.3)
        assertWindows(listOf(7.363 to 0.311, 11.106 to 0.0, 15.219 to 0.888, 20.075 to 0.082), settling)
        assertPiece(12.31, 2.641, 0.77, settling)

        assertTrue(logoMotion(7.2, ended = 5.3).triangle)
    }

    @Test
    fun aLoadFinishedDuringTheStartLetsTheStartPlayOut() {
        val starting = logoMotion(0.5, ended = 0.2)
        assertWindows(listOf(15.219 to 0.0, 20.075 to 0.0, 7.363 to 0.161, 11.106 to 0.361), starting)
        assertPiece(13.956, 3.341, 0.63, starting)

        val settling = logoMotion(2.4, ended = 0.2)
        assertWindows(listOf(6.97 to 0.321, 10.751 to 0.0, 14.756 to 1.12, 19.571 to 0.363), settling)
        assertPiece(11.724, 2.251, 0.856, settling)

        assertTrue(logoMotion(3.0, ended = 0.2).triangle)
    }

    @Test
    fun aFrameCountsStepsAndBubblesFromSeconds() {
        val frame = logoFrame(3.2, endedSeconds = 2.65)
        assertEquals(logoMotion(6.4, ended = 5.3), frame.motion)
        assertEquals(logoBubbles(3.2, endedSeconds = 2.65), frame.bubbles)
        assertEquals(logoMotion(2.5), logoFrame(1.25).motion)
    }

    @Test
    fun theLogoIsSettledOnceTheTriangleIsBackAndTheBubblesRest() {
        listOf(0.05 to 1.2, 0.3 to 1.86, 2.6 to 3.86, 4.0 to 5.15, 4.2 to 5.86).forEach { (ended, rest) ->
            assertEquals(rest, logoBubblesRest(ended), 1e-9)
        }
        // ended 5.3 steps in: the triangle is back at step 7, before the last puff is gone
        assertFalse(logoSettled(3.85, endedSeconds = 2.65))
        assertTrue(logoSettled(3.87, endedSeconds = 2.65))
        assertTrue(logoFrame(3.87, endedSeconds = 2.65).motion.triangle)
        assertFalse(logoSettled(1.85, endedSeconds = 0.1))
        assertTrue(logoSettled(1.87, endedSeconds = 0.1))
    }
}
