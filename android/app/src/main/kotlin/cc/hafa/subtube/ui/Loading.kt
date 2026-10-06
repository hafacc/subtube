package cc.hafa.subtube.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.progressSemantics
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** How long the shimmer's band takes to cross. */
private const val SHIMMER_SWEEP_MS = 1400

/** The band's width, as a share of what it crosses. */
private const val SHIMMER_BAND = 0.4f

/** How many skeleton cards stand in for a list of videos: enough to fill a phone. */
const val SKELETON_CARDS: Int = 4

/** How many skeleton rows stand in for a list of channels. */
const val SKELETON_ROWS: Int = 16

/** Whether the system allows animation, so the shimmer runs; "Remove animations" sets the animator scale to 0. */
@Composable
internal fun motionAllowed(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f
}

/**
 * The loading shimmer: a band sweeping left to right every 1.4 seconds.
 *
 * On skeletons it is a lighter band cut to what they draw. With [overCards],
 * for real content greyed out while it reloads, it is a darker band on light
 * and a lighter one on dark, across the whole area, gaps included. With
 * [active] false, or when the system asks for no animation, it draws nothing
 * extra.
 */
@Composable
fun Modifier.shimmer(active: Boolean = true, overCards: Boolean = false): Modifier =
    if (active && motionAllowed()) {
        val progress by rememberInfiniteTransition(label = "shimmer").animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(SHIMMER_SWEEP_MS, easing = LinearEasing)),
            label = "shimmer",
        )
        val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
        val band = when {
            !overCards -> Color.White.copy(alpha = if (dark) 0.09f else 0.65f)
            dark -> Color.White.copy(alpha = 0.22f)
            else -> Color.Black.copy(alpha = 0.16f)
        }
        val sweep = Modifier.drawWithContent {
            drawContent()
            val width = size.width * SHIMMER_BAND
            val start = -width + (size.width + width) * progress
            drawRect(
                brush = Brush.horizontalGradient(listOf(Color.Transparent, band, Color.Transparent), startX = start, endX = start + width),
                blendMode = if (overCards) BlendMode.SrcOver else BlendMode.SrcAtop,
            )
        }
        if (overCards) {
            then(sweep)
        } else {
            // offscreen, so the band lands only on what was drawn and not on the gaps between
            graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.then(sweep)
        }
    } else {
        this
    }

/** Marks skeletons as one "loading" for screen readers, with nothing inside to read. */
fun Modifier.loadingPlaceholder(): Modifier = clearAndSetSemantics { progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate }

@Composable
private fun SkeletonBar(width: Float, height: Dp) {
    Box(Modifier.fillMaxWidth(width).height(height).background(MaterialTheme.brand.placeholder, RoundedCornerShape(4.dp)))
}

/** A feed card's shape with nothing in it: thumbnail block, two title lines, then the channel and date line. */
@Composable
fun SkeletonCard(modifier: Modifier = Modifier) {
    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        modifier = modifier.fillMaxWidth(),
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(MaterialTheme.brand.placeholder))
        Column(Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SkeletonBar(width = 0.9f, height = 16.dp)
            SkeletonBar(width = 0.6f, height = 16.dp)
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Box(Modifier.fillMaxWidth(0.4f)) { SkeletonBar(width = 1f, height = 12.dp) }
                Box(Modifier.fillMaxWidth(0.25f)) { SkeletonBar(width = 1f, height = 12.dp) }
            }
        }
    }
}

/** [count] skeleton cards with the shimmer, standing in for a list of videos that is loading. */
@Composable
fun SkeletonCards(modifier: Modifier = Modifier, count: Int = SKELETON_CARDS) {
    Column(modifier.loadingPlaceholder().shimmer(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        repeat(count) { SkeletonCard() }
    }
}

/** A channel row's shape with nothing in it: avatar, name line, summary line. */
@Composable
private fun SkeletonChannelRow() {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(40.dp).background(MaterialTheme.brand.placeholder, CircleShape))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SkeletonBar(width = 0.5f, height = 16.dp)
            SkeletonBar(width = 0.35f, height = 12.dp)
        }
    }
}

/** [count] skeleton channel rows with the shimmer, standing in for a list of channels that is loading. */
@Composable
fun SkeletonChannelRows(modifier: Modifier = Modifier, count: Int = SKELETON_ROWS) {
    Column(modifier.loadingPlaceholder().shimmer()) {
        repeat(count) { SkeletonChannelRow() }
    }
}

/** How thick the bar that shows a full load's progress is. */
private val LoadBarHeight = 3.dp

/** How long the load bar takes to reach a new value. */
private const val LOAD_BAR_STEP_MS = 200

/** How long the load bar takes to fade out once it has reached the end. */
private const val LOAD_BAR_FADE_MS = 300

/**
 * A full load's progress as a thin Sunflower bar growing from the left edge:
 * [progress] from 0 to 1 while the load runs, null when none does. It moves
 * to each new value, runs to the end when the load finishes and then fades
 * out; where the system asks for no animation it jumps and vanishes instead.
 * It takes up its height wherever it is put, so lay it over the content.
 * Screen readers get it as a progress bar while the load runs.
 */
@Composable
fun LoadProgressBar(progress: Double?, modifier: Modifier = Modifier) {
    val animated = motionAllowed()
    val fraction = remember { Animatable(0f) }
    val opacity = remember { Animatable(0f) }
    LaunchedEffect(progress, animated) {
        if (progress != null) {
            val target = progress.toFloat().coerceIn(0f, 1f)
            opacity.snapTo(1f)
            // a bar still at the end of the load before starts over rather than running back
            if (animated && target >= fraction.value) {
                fraction.animateTo(target, tween(LOAD_BAR_STEP_MS))
            } else {
                fraction.snapTo(target)
            }
        } else if (opacity.value > 0f) {
            if (animated) {
                fraction.animateTo(1f, tween(LOAD_BAR_STEP_MS))
                opacity.animateTo(0f, tween(LOAD_BAR_FADE_MS))
            } else {
                opacity.snapTo(0f)
            }
            fraction.snapTo(0f)
        }
    }
    val semantics = if (progress != null) Modifier.progressSemantics(progress.toFloat().coerceIn(0f, 1f)) else Modifier
    Box(
        modifier.fillMaxWidth().height(LoadBarHeight).then(semantics).drawBehind {
            drawRect(Sunflower, size = Size(size.width * fraction.value, size.height), alpha = opacity.value)
        },
    )
}
