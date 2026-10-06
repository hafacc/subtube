package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SwipeMarksTest {
    @Test
    fun marksFromAQuarterOfTheWidth() {
        assertTrue(swipeMarks(offset = 100f, width = 400f))
        assertTrue(swipeMarks(offset = 399f, width = 400f))
    }

    @Test
    fun doesNothingShortOfAQuarter() {
        assertFalse(swipeMarks(offset = 99.9f, width = 400f))
        assertFalse(swipeMarks(offset = 0f, width = 400f))
    }

    @Test
    fun countsEitherDirectionTheSame() {
        assertTrue(swipeMarks(offset = -100f, width = 400f))
        assertFalse(swipeMarks(offset = -99.9f, width = 400f))
    }

    @Test
    fun aCardNotYetMeasuredIsNeverMarked() {
        assertFalse(swipeMarks(offset = 0f, width = 0f))
        assertFalse(swipeMarks(offset = 50f, width = 0f))
    }
}
