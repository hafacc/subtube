package cc.hafa.subtube.core

import kotlin.math.abs

/** The share of a card's width a sideways swipe has to cover to mark its entry. */
const val SWIPE_MARK_SHARE: Float = 0.25f

/** Whether a card [width] wide, [offset] to either side of its place, has been swiped far enough to mark its entry. */
fun swipeMarks(offset: Float, width: Float): Boolean = width > 0f && abs(offset) >= width * SWIPE_MARK_SHARE
