package cc.hafa.subtube.core

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/*
 * The logo's loading animation, a port of `motion()` and `bubbles()` in design/icons/make.py.
 * Everything is in the drawing's own 24 by 24 box, before it is framed.
 */

/** The body's center line, which the play triangle and the windows sit on. */
const val LOGO_MIDLINE: Double = 15.4

private const val TRIANGLE_LEFT = 11.648
private const val TRIANGLE_RIGHT = 17.248

/** The play triangle's center across; it points at the nose. */
const val LOGO_TRIANGLE_CENTER: Double = (2 * TRIANGLE_LEFT + TRIANGLE_RIGHT) / 3

/** The play triangle's inradius. */
const val LOGO_TRIANGLE_INRADIUS: Double = (TRIANGLE_RIGHT - LOGO_TRIANGLE_CENTER) / 2

/** Seconds for a window to reach the next one's place. */
const val LOGO_STEP_SECONDS: Double = 0.5

/** A window in the body: a circle on the midline. */
data class LogoWindow(val x: Double, val radius: Double)

/** A bubble behind the tail. */
data class LogoBubble(val x: Double, val y: Double, val radius: Double)

/**
 * The play triangle in motion: a circle on the midline, cut by a triangle
 * pointing at the nose and centered on it whose inradius is [cut] radii.
 */
data class LogoPiece(val x: Double, val radius: Double, val cut: Double)

/** The inside of the logo at one moment. */
data class LogoMotion(
    /** Whether the still play triangle shows. */
    val triangle: Boolean,
    /** Each rolling window; radius 0 when it does not show. */
    val windows: List<LogoWindow>,
    /** The triangle in motion; radius 0 when it does not show. */
    val piece: LogoPiece,
)

/** The whole logo at one moment: its inside and its bubbles. */
data class LogoFrame(val motion: LogoMotion, val bubbles: List<LogoBubble>)

// the still places, tail to nose
private val WINDOWS = listOf(LogoWindow(9.3, 1.15), LogoWindow(13.0, 1.55), LogoWindow(17.6, 2.0))

// low to high
private val BUBBLES = listOf(LogoBubble(3.2, 7.6, 1.5), LogoBubble(5.8, 4.2, 1.1))

// grown from nothing at the tail, gone past the nose
private val WINDOW_TRACK = listOf(LogoWindow(5.4, 0.0)) + WINDOWS + LogoWindow(22.6, 2.4)

// steps past the last window's place for it to shrink away
private const val SHRINK = 0.6

// steps before a window is back where it started
private val LAP = WINDOW_TRACK.size - 1

// steps for the triangle to become a window
private const val START_BLEND = 1.5

// steps for a window to settle as the triangle
private const val END_BLEND = 1.0

// out from behind the tail, through the two resting places, gone
private val BUBBLE_TRACK = listOf(LogoBubble(2.2, 10.8, 0.0)) + BUBBLES + LogoBubble(7.4, 2.9, 0.0)

private val BUBBLE_LAP = BUBBLE_TRACK.size - 1

// seconds a resting bubble takes to float off: a base, and more per place it has left
private const val LEAVE_BASE = 0.25
private const val LEAVE_PER_PLACE = 0.45

// seconds into a load for the first puff, and from one puff to the next
private const val PUFF_FIRST = 0.1
private const val PUFF_EVERY = 2.0

// seconds a puff's bubble takes to rise and vanish
private const val PUFF_RISE = 1.5

// a puff's largest bubble, in track radii
private const val PUFF_SIZE = 1.1

private data class PuffBubble(val size: Double, val sway: Double, val late: Double)

private val PUFF = listOf(PuffBubble(1.0, 0.0, 0.0), PuffBubble(0.65, 0.9, 0.13), PuffBubble(0.5, -0.8, 0.26))

// a last bubble: the place it rises to, seconds after the load ends, seconds to get there
private data class SettlingBubble(val place: Double, val late: Double, val span: Double)

private val SETTLE = listOf(SettlingBubble(2.0, 0.0, 1.0), SettlingBubble(1.0, 0.35, 0.8))

// the piece's cut when it is the play triangle, and once the circle sits wholly inside the cut
private const val CUT_TRIANGLE = 0.48
private const val CUT_CIRCLE = 1.06

/** Catmull-Rom through equally spaced [points]; [fraction] from 0 to 1. */
fun spline(points: List<Double>, fraction: Double): Double {
    val count = points.size
    val padded = listOf(2 * points[0] - points[1]) + points + (2 * points[count - 1] - points[count - 2])
    val position = fraction * (count - 1)
    val segment = min(position.toInt(), count - 2)
    val local = position - segment
    val (before, start, end, after) = padded.subList(segment, segment + 4)
    return 0.5 * (
        2 * start +
            (end - before) * local +
            (2 * before - 5 * start + 4 * end - after) * local * local +
            (3 * start - before - 3 * end + after) * local * local * local
        )
}

/** Ease from 0 to 1. */
fun smoothstep(value: Double): Double {
    val clamped = value.coerceIn(0.0, 1.0)
    return clamped * clamped * (3 - 2 * clamped)
}

private fun mix(start: Double, end: Double, weight: Double): Double = start + (end - start) * weight

/** A window [position] steps along its track, tail to nose. */
fun logoWindowAt(position: Double): LogoWindow {
    val fraction = position / LAP
    var radius = max(spline(WINDOW_TRACK.map(LogoWindow::radius), fraction), 0.0)
    if (position > LAP - 1) {
        radius *= 1 - smoothstep((position - (LAP - 1)) / SHRINK)
    }
    return LogoWindow(spline(WINDOW_TRACK.map(LogoWindow::x), fraction), radius)
}

/** A bubble [position] places along its track, low to high, [size] times as large. */
fun logoBubbleAt(position: Double, size: Double = 1.0): LogoBubble {
    val fraction = position.coerceIn(0.0, BUBBLE_LAP.toDouble()) / BUBBLE_LAP
    return LogoBubble(
        x = spline(BUBBLE_TRACK.map(LogoBubble::x), fraction),
        y = spline(BUBBLE_TRACK.map(LogoBubble::y), fraction),
        radius = max(spline(BUBBLE_TRACK.map(LogoBubble::radius), fraction), 0.0) * size,
    )
}

// the step at which a load that finished [ended] steps in starts back toward the triangle
private fun stepBack(ended: Double): Int = max(ceil(ended).toInt(), 2)

/**
 * The logo's inside [steps] steps after a load began.
 *
 * The play triangle rounds into a window headed for the nose while windows
 * grow in at the tail; they then roll, a lap every four steps. [ended] is how
 * many steps in the load finished: at the next whole step, once the start
 * has played out, the window in the first place becomes the triangle as the
 * others shrink. Before the load, and once that is over, the still triangle
 * shows.
 */
fun logoMotion(steps: Double, ended: Double? = null): LogoMotion {
    val back = ended?.let(::stepBack)
    val resting = LogoPiece(LOGO_TRIANGLE_CENTER, 0.0, CUT_TRIANGLE)
    if (steps < 0 || (back != null && steps >= back + END_BLEND)) {
        return LogoMotion(triangle = true, windows = List(LAP) { LogoWindow(0.0, 0.0) }, piece = resting)
    }
    val grow = smoothstep(steps / START_BLEND)
    val windows = List(LAP) { index ->
        // at the start the windows stand at places 2, 3, 0 and 1; the one at 2 is the triangle
        val start = (index + 2) % LAP
        val window = logoWindowAt((steps + start) % LAP)
        // until it has left, the piece stands in for it, or it would start ahead of the piece
        val shown = if (start >= 2 && steps < LAP - start) 0.0 else window.radius * grow
        val radius = when {
            back == null || steps < back -> shown
            (back + start) % LAP == 1 -> 0.0
            else -> shown * (1 - smoothstep((steps - back) / END_BLEND))
        }
        LogoWindow(window.x, radius)
    }
    val scale = LOGO_TRIANGLE_INRADIUS / CUT_TRIANGLE
    val piece = if (steps < 2) {
        val window = logoWindowAt(min(steps + 2, LAP.toDouble()))
        LogoPiece(
            x = mix(LOGO_TRIANGLE_CENTER, window.x, grow),
            radius = mix(scale, window.radius, grow),
            cut = mix(CUT_TRIANGLE, CUT_CIRCLE, grow),
        )
    } else if (back != null && steps >= back) {
        val settle = smoothstep((steps - back) / END_BLEND)
        val window = logoWindowAt(1 + steps - back)
        LogoPiece(
            x = mix(window.x, LOGO_TRIANGLE_CENTER, settle),
            radius = mix(window.radius, scale, settle),
            cut = mix(CUT_CIRCLE, CUT_TRIANGLE, settle),
        )
    } else {
        resting
    }
    return LogoMotion(triangle = false, windows = windows, piece = piece)
}

/**
 * The seven bubbles [seconds] after a load began. The two resting bubbles
 * float off. Puffs of three follow, one every two seconds, each bubble fast
 * at first and slowing as it shrinks away. [endedSeconds] is when the load
 * finished, null while it runs: no puff begins after it, and two last
 * bubbles rise into the resting places. A bubble that does not show has
 * radius 0.
 */
fun logoBubbles(seconds: Double, endedSeconds: Double? = null): List<LogoBubble> {
    val gone = BUBBLE_TRACK.first().copy(radius = 0.0)
    val resting = listOf(1.0, 2.0).map { place ->
        val left = seconds / (LEAVE_BASE + LEAVE_PER_PLACE * (BUBBLE_LAP - place))
        when {
            seconds < 0 -> logoBubbleAt(place)
            left < 1 -> logoBubbleAt(place + (BUBBLE_LAP - place) * left.pow(1.5))
            else -> gone
        }
    }
    val began = PUFF_FIRST + PUFF_EVERY * floor((seconds - PUFF_FIRST) / PUFF_EVERY)
    val begins = seconds >= PUFF_FIRST && (endedSeconds == null || began <= endedSeconds)
    val puffed = PUFF.map { bubble ->
        val risen = (seconds - began - bubble.late) / PUFF_RISE
        if (begins && risen >= 0 && risen < 1) {
            val risenTo = logoBubbleAt(BUBBLE_LAP * (1 - (1 - risen).pow(2.2)), bubble.size * PUFF_SIZE)
            risenTo.copy(x = risenTo.x + bubble.sway * sin(PI * risen))
        } else {
            gone
        }
    }
    val last = SETTLE.map { bubble ->
        if (endedSeconds == null || seconds < endedSeconds + bubble.late) {
            gone
        } else {
            val arrived = min((seconds - endedSeconds - bubble.late) / bubble.span, 1.0)
            logoBubbleAt(bubble.place * (1 - (1 - arrived).pow(2.4)))
        }
    }
    return resting + puffed + last
}

/** The seconds into a load that finished at [endedSeconds] when its bubbles have come to rest. */
fun logoBubblesRest(endedSeconds: Double): Double {
    val settled = endedSeconds + SETTLE.maxOf { bubble -> bubble.late + bubble.span }
    return if (endedSeconds < PUFF_FIRST) {
        settled
    } else {
        val last = PUFF_FIRST + PUFF_EVERY * floor((endedSeconds - PUFF_FIRST) / PUFF_EVERY)
        max(settled, last + PUFF_RISE + PUFF.maxOf(PuffBubble::late))
    }
}

/** The logo as it stands when nothing loads. */
val LOGO_STILL: LogoFrame = LogoFrame(logoMotion(-1.0), logoBubbles(-1.0))

/**
 * The logo [seconds] after a load began. [endedSeconds] is when that load
 * finished, null while it runs: the inside then goes back to the play
 * triangle and two last bubbles rise into the resting places.
 */
fun logoFrame(seconds: Double, endedSeconds: Double? = null): LogoFrame = LogoFrame(
    motion = logoMotion(seconds / LOGO_STEP_SECONDS, endedSeconds?.let { ended -> ended / LOGO_STEP_SECONDS }),
    bubbles = logoBubbles(seconds, endedSeconds),
)

/** Whether the logo is still again [seconds] after a load began, the load having finished at [endedSeconds]. */
fun logoSettled(seconds: Double, endedSeconds: Double): Boolean {
    val triangleBack = (stepBack(endedSeconds / LOGO_STEP_SECONDS) + END_BLEND) * LOGO_STEP_SECONDS
    return seconds >= max(triangleBack, logoBubblesRest(endedSeconds))
}
