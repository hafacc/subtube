package cc.hafa.subtube.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import cc.hafa.subtube.core.LOGO_MIDLINE
import cc.hafa.subtube.core.LOGO_STILL
import cc.hafa.subtube.core.LOGO_TRIANGLE_CENTER
import cc.hafa.subtube.core.LOGO_TRIANGLE_INRADIUS
import cc.hafa.subtube.core.LogoFrame
import cc.hafa.subtube.core.logoFrame
import cc.hafa.subtube.core.logoSettled
import kotlinx.coroutines.flow.first
import kotlin.math.sqrt

/*
 * The logo's shapes are design/icons/make.py's, in its 24 by 24 box before
 * framing: the yellow outline is `sub-play-centred.svg`'s moved back by that
 * file's framing (0.15 across, -0.35 down), the body is `BODY` as written.
 */

/** The body, fin and tower as one outline. */
private const val LOGO_HULL = "M17.8 4.8 L17.773 4.593 L17.693 4.4 L17.566 4.234 L17.4 4.107 L17.207 4.027 L17 4 L11.8 4 L11.584 4.03 L11.384 4.117 L11.215 4.254 L11.089 4.432 L11.017 4.638 L10.056 9.281 L9.85 9.29 L9.468 9.31 L9.095 9.332 L8.737 9.356 L7.784 9.448 L7.52 9.485 L7.292 9.526 L7.102 9.57 L7.01 9.598 L6.918 9.63 L6.83 9.665 L6.742 9.704 L6.657 9.747 L6.574 9.794 L6.493 9.844 L6.415 9.898 L6.339 9.955 L6.266 10.015 L6.195 10.078 L6.127 10.144 L6.062 10.213 L6 10.285 L5.941 10.359 L5.886 10.436 L5.833 10.516 L5.784 10.599 L5.738 10.684 L5.695 10.769 L5.657 10.859 L5.622 10.949 L5.591 11.042 L5.564 11.136 L5.52 11.317 L5.48 11.51 L5.444 11.716 L5.411 11.932 L5.38 12.156 L5.353 12.385 L5.352 12.4 L4.009 13.742 L2.133 11.785 L2.01 11.686 L1.865 11.623 L1.709 11.6 L1.552 11.619 L1.405 11.678 L1.279 11.773 L1.182 11.898 L1.121 12.043 L1.1 12.2 L1.1 18.6 L1.121 18.757 L1.182 18.902 L1.279 19.027 L1.405 19.122 L1.552 19.181 L1.709 19.2 L1.865 19.177 L2.01 19.114 L2.133 19.015 L4.009 17.058 L5.352 18.4 L5.353 18.415 L5.38 18.644 L5.411 18.868 L5.444 19.084 L5.48 19.29 L5.52 19.483 L5.564 19.664 L5.591 19.758 L5.622 19.851 L5.657 19.941 L5.695 20.031 L5.738 20.117 L5.784 20.201 L5.833 20.284 L5.886 20.364 L5.941 20.441 L6 20.515 L6.062 20.587 L6.127 20.656 L6.195 20.722 L6.266 20.785 L6.339 20.845 L6.415 20.902 L6.493 20.956 L6.574 21.006 L6.657 21.053 L6.742 21.096 L6.83 21.135 L6.918 21.17 L7.01 21.202 L7.102 21.23 L7.292 21.274 L7.52 21.315 L7.784 21.352 L8.076 21.386 L8.396 21.417 L8.737 21.444 L9.095 21.468 L9.468 21.49 L9.85 21.51 L10.236 21.526 L10.625 21.542 L11.01 21.554 L11.388 21.565 L12.106 21.581 L12.748 21.591 L13.277 21.596 L13.793 21.6 L14.007 21.6 L15.052 21.591 L15.361 21.587 L16.045 21.573 L16.791 21.554 L17.175 21.542 L17.564 21.526 L17.951 21.51 L18.332 21.49 L18.705 21.468 L19.063 21.444 L19.404 21.417 L19.724 21.386 L20.016 21.352 L20.28 21.315 L20.508 21.274 L20.698 21.23 L20.79 21.202 L20.882 21.17 L20.97 21.135 L21.058 21.096 L21.144 21.053 L21.226 21.006 L21.307 20.956 L21.385 20.902 L21.461 20.845 L21.534 20.785 L21.605 20.722 L21.673 20.656 L21.738 20.587 L21.8 20.515 L21.859 20.441 L21.914 20.364 L21.967 20.284 L22.016 20.201 L22.062 20.117 L22.105 20.031 L22.143 19.941 L22.178 19.851 L22.209 19.758 L22.236 19.664 L22.28 19.483 L22.32 19.29 L22.356 19.084 L22.389 18.868 L22.42 18.644 L22.447 18.415 L22.47 18.181 L22.492 17.945 L22.511 17.708 L22.528 17.473 L22.543 17.241 L22.555 17.014 L22.565 16.795 L22.581 16.385 L22.587 16.199 L22.595 15.872 L22.6 15.458 L22.6 15.342 L22.597 15.064 L22.59 14.773 L22.581 14.415 L22.564 14.005 L22.554 13.786 L22.542 13.559 L22.527 13.327 L22.51 13.092 L22.491 12.855 L22.47 12.619 L22.446 12.385 L22.419 12.156 L22.389 11.932 L22.356 11.716 L22.32 11.51 L22.28 11.317 L22.236 11.136 L22.209 11.042 L22.178 10.949 L22.143 10.859 L22.105 10.769 L22.062 10.684 L22.016 10.599 L21.967 10.516 L21.914 10.436 L21.859 10.359 L21.8 10.285 L21.738 10.213 L21.673 10.144 L21.605 10.078 L21.534 10.015 L21.461 9.955 L21.385 9.898 L21.307 9.844 L21.226 9.794 L21.144 9.747 L21.058 9.704 L20.97 9.665 L20.882 9.63 L20.79 9.598 L20.698 9.57 L20.508 9.526 L20.28 9.485 L20.016 9.448 L19.063 9.356 L18.705 9.332 L18.332 9.31 L17.951 9.29 L17.8 9.284Z"

/** The body alone, which the windows are cut to. */
private const val LOGO_BODY = "M22.209 11.042 L22.178 10.949 L22.143 10.859 L22.105 10.769 L22.062 10.684 L22.016 10.599 L21.967 10.516 L21.914 10.436 L21.859 10.359 L21.8 10.285 L21.738 10.213 L21.673 10.144 L21.605 10.078 L21.534 10.015 L21.461 9.955 L21.385 9.898 L21.307 9.844 L21.226 9.794 L21.144 9.747 L21.058 9.704 L20.97 9.665 L20.882 9.63 L20.79 9.598 L20.698 9.57 L20.508 9.526 L20.28 9.485 L20.016 9.448 L19.063 9.356 L18.705 9.332 L18.332 9.31 L17.951 9.29 L17.512 9.272 L17.554 9.337 L15.627 9.349 L15.672 9.278 L15.714 9.219 L15.052 9.209 L14.007 9.2 L13.793 9.2 L13.277 9.204 L12.439 9.213 L11.755 9.227 L11.388 9.235 L10.625 9.258 L10.236 9.274 L9.85 9.29 L9.468 9.31 L9.095 9.332 L8.737 9.356 L7.784 9.448 L7.52 9.485 L7.292 9.526 L7.102 9.57 L7.01 9.598 L6.918 9.63 L6.83 9.665 L6.742 9.704 L6.657 9.747 L6.574 9.794 L6.493 9.844 L6.415 9.898 L6.339 9.955 L6.266 10.015 L6.195 10.078 L6.127 10.144 L6.062 10.213 L6 10.285 L5.941 10.359 L5.886 10.436 L5.833 10.516 L5.784 10.599 L5.738 10.684 L5.695 10.769 L5.657 10.859 L5.622 10.949 L5.591 11.042 L5.564 11.136 L5.52 11.317 L5.48 11.51 L5.444 11.716 L5.411 11.932 L5.38 12.156 L5.353 12.385 L5.33 12.619 L5.308 12.855 L5.289 13.092 L5.257 13.559 L5.235 14.005 L5.226 14.216 L5.213 14.601 L5.209 14.773 L5.202 15.18 L5.2 15.342 L5.202 15.62 L5.209 16.027 L5.213 16.199 L5.226 16.584 L5.235 16.795 L5.257 17.241 L5.289 17.708 L5.308 17.945 L5.33 18.181 L5.353 18.415 L5.38 18.644 L5.411 18.868 L5.444 19.084 L5.48 19.29 L5.52 19.483 L5.564 19.664 L5.591 19.758 L5.622 19.851 L5.657 19.941 L5.695 20.031 L5.738 20.117 L5.784 20.201 L5.833 20.284 L5.886 20.364 L5.941 20.441 L6 20.515 L6.062 20.587 L6.127 20.656 L6.195 20.722 L6.266 20.785 L6.339 20.845 L6.415 20.902 L6.493 20.956 L6.574 21.006 L6.657 21.053 L6.742 21.096 L6.83 21.135 L6.918 21.17 L7.01 21.202 L7.102 21.23 L7.292 21.274 L7.52 21.315 L7.784 21.352 L8.076 21.386 L8.396 21.417 L8.737 21.444 L9.095 21.468 L9.468 21.49 L9.85 21.51 L10.236 21.526 L10.625 21.542 L11.01 21.554 L11.388 21.565 L12.106 21.581 L12.748 21.591 L13.277 21.596 L13.793 21.6 L14.007 21.6 L15.052 21.591 L15.361 21.587 L16.045 21.573 L16.791 21.554 L17.175 21.542 L17.564 21.526 L17.951 21.51 L18.332 21.49 L18.705 21.468 L19.063 21.444 L19.404 21.417 L19.724 21.386 L20.016 21.352 L20.28 21.315 L20.508 21.274 L20.698 21.23 L20.79 21.202 L20.882 21.17 L20.97 21.135 L21.058 21.096 L21.144 21.053 L21.226 21.006 L21.307 20.956 L21.385 20.902 L21.461 20.845 L21.534 20.785 L21.605 20.722 L21.673 20.656 L21.738 20.587 L21.8 20.515 L21.859 20.441 L21.914 20.364 L21.967 20.284 L22.016 20.201 L22.062 20.117 L22.105 20.031 L22.143 19.941 L22.178 19.851 L22.209 19.758 L22.236 19.664 L22.28 19.483 L22.32 19.29 L22.356 19.084 L22.389 18.868 L22.42 18.644 L22.447 18.415 L22.47 18.181 L22.492 17.945 L22.511 17.708 L22.528 17.473 L22.543 17.241 L22.555 17.014 L22.565 16.795 L22.581 16.385 L22.587 16.199 L22.595 15.872 L22.6 15.458 L22.6 15.342 L22.597 15.064 L22.59 14.773 L22.581 14.415 L22.564 14.005 L22.554 13.786 L22.542 13.559 L22.527 13.327 L22.51 13.092 L22.491 12.855 L22.47 12.619 L22.446 12.385 L22.419 12.156 L22.389 11.932 L22.356 11.716 L22.32 11.51 L22.28 11.317 L22.236 11.136Z"

/** The side of the square the logo is drawn in. */
private const val LOGO_BOX = 24f

/** The logo's size beside the name, as a share of the drawing's. */
private const val BESIDE_SCALE = 0.95f

/** How far the scaled drawing is moved across so fin and body are centered in the square. */
private const val BESIDE_ACROSS = 0.7425f

/** How far the scaled drawing is moved down so the body is centered in the square. */
private const val BESIDE_DOWN = -2.63f

/** The fin and body's share of the square's height beside the name; the tower and bubbles rise above. */
const val LOGO_BODY_HEIGHT: Float = 0.4908f

/** The fin and body's share of the square's width beside the name. */
const val LOGO_BODY_WIDTH: Float = 0.851f

private val SQRT3 = sqrt(3f)

private fun parsedPath(data: String): Path = PathParser().parsePathString(data).toPath()

/** Make [path] the triangle pointing at the nose with this center across and this inradius. */
private fun pointRight(path: Path, center: Float, inradius: Float): Path {
    val midline = LOGO_MIDLINE.toFloat()
    path.rewind()
    path.moveTo(center + 2 * inradius, midline)
    path.lineTo(center - inradius, midline + SQRT3 * inradius)
    path.lineTo(center - inradius, midline - SQRT3 * inradius)
    path.close()
    return path
}

/** The logo's paths, parsed once. */
private class LogoShapes {
    val hull: Path = parsedPath(LOGO_HULL)
    val body: Path = parsedPath(LOGO_BODY)
    val triangle: Path = pointRight(Path(), LOGO_TRIANGLE_CENTER.toFloat(), LOGO_TRIANGLE_INRADIUS.toFloat())

    // the moving triangle's outline, rebuilt for each frame that shows one
    val cut: Path = Path()
}

private fun DrawScope.drawLogo(shapes: LogoShapes, frame: LogoFrame) {
    val midline = LOGO_MIDLINE.toFloat()
    drawPath(shapes.hull, Sunflower)
    for (bubble in frame.bubbles) {
        if (bubble.radius > 0) {
            drawCircle(Sunflower, radius = bubble.radius.toFloat(), center = Offset(bubble.x.toFloat(), bubble.y.toFloat()))
        }
    }
    val motion = frame.motion
    if (motion.triangle) {
        drawPath(shapes.triangle, Ink)
    } else {
        clipPath(shapes.body) {
            for (window in motion.windows) {
                if (window.radius > 0) {
                    drawCircle(Ink, radius = window.radius.toFloat(), center = Offset(window.x.toFloat(), midline))
                }
            }
            val piece = motion.piece
            if (piece.radius > 0) {
                clipPath(pointRight(shapes.cut, piece.x.toFloat(), (piece.radius * piece.cut).toFloat())) {
                    drawCircle(Ink, radius = piece.radius.toFloat(), center = Offset(piece.x.toFloat(), midline))
                }
            }
        }
    }
}

/**
 * What the logo shows now: still, or the loading animation from the frame
 * [loading] turns true until it has settled after [loading] turns false.
 * Where the system asks for no animation it is always still.
 */
@Composable
private fun logoFrameState(loading: Boolean): State<LogoFrame> {
    val moves = motionAllowed()
    val loadingNow = rememberUpdatedState(loading)
    val frame = remember { mutableStateOf(LOGO_STILL) }
    LaunchedEffect(moves) {
        frame.value = LOGO_STILL
        while (moves) {
            snapshotFlow { loadingNow.value }.first { running -> running }
            val began = withFrameNanos { nanos -> nanos }
            var seconds = 0.0
            var ended: Double? = null
            while (ended?.let { finished -> logoSettled(seconds, finished) } != true) {
                seconds = (withFrameNanos { nanos -> nanos } - began) / 1e9
                if (!loadingNow.value) {
                    ended = ended ?: seconds
                }
                frame.value = logoFrame(seconds, ended)
            }
            frame.value = LOGO_STILL
        }
    }
    return frame
}

/**
 * The logo as it stands beside the name, in a square: fin and body centered
 * in it ([LOGO_BODY_WIDTH] by [LOGO_BODY_HEIGHT] of it), tower and bubbles
 * above. While [loading] its windows roll tail to nose in place of the play
 * triangle and its bubbles rise; the change there and back is animated too.
 * Where the system asks for no animation it is the still logo throughout.
 */
@Composable
fun Logo(loading: Boolean, modifier: Modifier = Modifier) {
    val shapes = remember { LogoShapes() }
    val frame = logoFrameState(loading)
    Canvas(modifier) {
        val unit = size.minDimension / LOGO_BOX
        withTransform({
            translate(BESIDE_ACROSS * unit, BESIDE_DOWN * unit)
            scale(BESIDE_SCALE * unit, BESIDE_SCALE * unit, pivot = Offset.Zero)
        }) {
            drawLogo(shapes, frame.value)
        }
    }
}
