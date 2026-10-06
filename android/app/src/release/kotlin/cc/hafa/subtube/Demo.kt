package cc.hafa.subtube

import android.content.Intent
import cc.hafa.subtube.ui.SubtubeViewModel

/** Demo mode exists in debug builds only; here a launch is always a normal one. */
@Suppress("UNUSED_PARAMETER")
internal fun showDemoIfAsked(intent: Intent, viewModel: SubtubeViewModel) = Unit
