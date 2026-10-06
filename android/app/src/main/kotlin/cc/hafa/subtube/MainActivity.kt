package cc.hafa.subtube

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleStartEffect
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.ui.NavDisplay
import cc.hafa.subtube.ui.ChannelScreen
import cc.hafa.subtube.ui.ChannelsScreen
import cc.hafa.subtube.ui.FeedScreen
import cc.hafa.subtube.ui.PlayerHost
import cc.hafa.subtube.ui.Screen
import cc.hafa.subtube.ui.SetUpScreen
import cc.hafa.subtube.ui.SettingsScreen
import cc.hafa.subtube.ui.SubtubeTheme
import cc.hafa.subtube.ui.SubtubeViewModel
import cc.hafa.subtube.ui.isDark
import kotlinx.coroutines.launch

/** The single activity; the screens are a Navigation 3 back stack kept in [SubtubeViewModel]. */
class MainActivity : ComponentActivity() {
    private val viewModel: SubtubeViewModel by viewModels()

    private val consentLauncher = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        viewModel.onConsentResult(result.resultCode == Activity.RESULT_OK, result.data)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            showDemoIfAsked(intent, viewModel)
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.consentRequests.collect { pendingIntent ->
                    consentLauncher.launch(IntentSenderRequest.Builder(pendingIntent).build())
                }
            }
        }
        setContent {
            val dark = viewModel.themeMode.isDark()
            DisposableEffect(dark) {
                val style = if (dark) {
                    SystemBarStyle.dark(Color.TRANSPARENT)
                } else {
                    SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                }
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
                onDispose { }
            }
            SubtubeTheme(dark) {
                LifecycleStartEffect(viewModel) {
                    viewModel.onForeground()
                    onStopOrDispose { viewModel.onBackground() }
                }
                App(viewModel)
            }
        }
    }
}

/** Tabs cross-fade; everything else uses Navigation 3's default push, pop and predictive back. */
private val tabTransition: Map<String, Any> = NavDisplay.transitionSpec { fadeIn() togetherWith fadeOut() } +
    NavDisplay.popTransitionSpec { fadeIn() togetherWith fadeOut() }

@Composable
private fun App(viewModel: SubtubeViewModel) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Screens(viewModel)
    }
}

@Composable
private fun Screens(viewModel: SubtubeViewModel) {
    // above the screens, so the one player outlives every change of screen
    PlayerHost(viewModel) {
        NavDisplay(
            backStack = viewModel.backStack,
            onBack = viewModel::pop,
            modifier = Modifier.fillMaxSize(),
        ) { screen ->
            when (screen) {
                Screen.SetUp -> NavEntry(screen) { SetUpScreen(viewModel) }
                Screen.Feed -> NavEntry(screen, metadata = tabTransition) { FeedScreen(viewModel) }
                Screen.Channels -> NavEntry(screen, metadata = tabTransition) { ChannelsScreen(viewModel) }
                Screen.Settings -> NavEntry(screen, metadata = tabTransition) { SettingsScreen(viewModel) }
                is Screen.ChannelPage -> NavEntry(screen) { ChannelScreen(viewModel, screen.channelId) }
            }
        }
    }
}
