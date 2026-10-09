package cc.hafa.subtube.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.roundToIntRect
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import cc.hafa.subtube.R
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.MINIMIZED_MARGIN
import cc.hafa.subtube.core.MIN_PLAYER_SIDE
import cc.hafa.subtube.core.Playback
import cc.hafa.subtube.core.PlayerPlace
import cc.hafa.subtube.core.PlayerState
import cc.hafa.subtube.core.Playlist
import cc.hafa.subtube.core.Video
import cc.hafa.subtube.core.ProgressUpload
import cc.hafa.subtube.core.minimizedSize
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The origin the player page claims, as its base URL and to the embed: YouTube
 * wants a native app's to be its application id, and rejects a page that
 * sends no referrer at all (error 153).
 */
private fun playerOrigin(context: Context): String = "https://${context.packageName}"

/** The name the player page calls [PlayerBridge] by. */
private const val BRIDGE_NAME = "SubtubePlayer"

/** How often the playing position is saved on this device. */
private const val PROGRESS_EVERY_MS = 5000L

/** How often the player page reports its position while playing. */
private const val REPORT_EVERY_MS = 1000

/** How tall the bar above the video is while the frame shows. */
private val PlayerBarHeight: Dp = 48.dp

/** How far the frame reaches past the video's other three sides. */
private val FrameEdge = 1.dp

/** The gap between the minimized player and the screen's trailing edge. */
private val MinimizedSideGap = 24.dp

/** The gap between the minimized player and the navigation bar or keyboard under it. */
private val MinimizedBottomGap = 8.dp

/** How long the frame takes to fade in or out. */
private const val FRAME_FADE_MS = 150

/** The corner radius of a card, of the minimized player and of the frame. */
private val PlayerCorner = 12.dp

/** How high the bottom navigation bar is taken to be until it has been measured. */
private val NavigationBarHeight = 80.dp

private const val PAUSE_SCRIPT = "player && player.pauseVideo && player.pauseVideo()"
private const val PLAY_SCRIPT = "player && player.playVideo && player.playVideo()"

/**
 * The IFrame API page, for one video ([kind] "video", started [startSeconds]
 * in) or a real playlist ("playlist"). The video is loaded with loadPlaylist
 * in onReady: combining videoId with the `playlist` parameter drops the first id.
 * Every report is one JSON message carrying [token], which only this page knows.
 */
private fun playerHtml(kind: String, videoId: String, playlistId: String, startSeconds: Double, origin: String, token: String): String = """
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html, body { margin: 0; height: 100%; background: #000; } #player { width: 100%; height: 100%; }</style>
</head>
<body>
<div id="player"></div>
<script>
var kind = ${Json.encodeToString(kind)};
var queue = ${Json.encodeToString(listOf(videoId))};
var playlistId = ${Json.encodeToString(playlistId)};
var startSeconds = ${Json.encodeToString(startSeconds)};
var appOrigin = ${Json.encodeToString(origin)};
var token = ${Json.encodeToString(token)};
var player = null;
function report(kind, fields) {
  fields.kind = kind;
  fields.token = token;
  $BRIDGE_NAME.postMessage(JSON.stringify(fields));
}
function onYouTubeIframeAPIReady() {
  var vars = kind === "playlist"
    ? { autoplay: 1, rel: 0, playsinline: 1, fs: 1, listType: "playlist", list: playlistId }
    : { rel: 0, playsinline: 1, fs: 1 };
  vars.origin = appOrigin;
  vars.widget_referrer = appOrigin;
  player = new YT.Player("player", {
    width: "100%",
    height: "100%",
    playerVars: vars,
    events: {
      onReady: function (event) {
        if (kind === "video") {
          event.target.loadPlaylist(queue, 0, startSeconds);
        }
      },
      onStateChange: function (event) {
        var loaded = event.target.getPlaylist();
        var last = !!loaded && event.target.getPlaylistIndex() === loaded.length - 1;
        report("state", { code: event.data, time: event.target.getCurrentTime() || 0, duration: event.target.getDuration() || 0, last: last });
      },
      onError: function (event) {
        report("error", { code: event.data });
      }
    }
  });
  setInterval(function () {
    if (player.getPlayerState && player.getPlayerState() === YT.PlayerState.PLAYING) {
      report("position", { time: player.getCurrentTime() || 0, duration: player.getDuration() || 0 });
    }
  }, $REPORT_EVERY_MS);
}
</script>
<script src="https://www.youtube.com/iframe_api" onerror="report('failed', {})"></script>
</body>
</html>
"""

/** A `YT.PlayerState` number as the state playback reacts to. */
private fun playerState(code: Int): PlayerState = when (code) {
    0 -> PlayerState.ENDED
    1 -> PlayerState.PLAYING
    2 -> PlayerState.PAUSED
    else -> PlayerState.OTHER
}

/**
 * The page the one web view has loaded: what its reports go to, and whether
 * it may play. It may not while something lies over the player ([cover]) or
 * the app is off the screen ([stop]); a page that starts playing then is
 * paused at once.
 */
internal class PlayerPage {
    /** What this load's reports carry: a report with anything else is not this page's. */
    var token: String = ""
        private set

    private var playback: Playback? = null
    private var playing = false
    private var covered = false
    private var stopped = false

    // paused because something came to lie over it, and so plays again once clear
    private var pausedForCover = false

    /** Whether the IFrame API script didn't load. */
    var failed: Boolean by mutableStateOf(false)
        private set

    /** Pauses the video; set by the host that owns the web view. */
    var pause: () -> Unit = {}

    /** Plays the video; set by the host that owns the web view. */
    var resume: () -> Unit = {}

    /** A new page is loaded for [playback]: returns the token its reports must carry. */
    fun load(playback: Playback): String {
        token = UUID.randomUUID().toString()
        this.playback = playback
        playing = false
        pausedForCover = false
        failed = false
        return token
    }

    /** The web view is gone: no report is taken any more. */
    fun close() {
        playback = null
    }

    /** Something came to lie over the player ([covered]) or left: the video pauses, and plays again if that is what paused it. */
    fun cover(covered: Boolean) {
        this.covered = covered
        if (covered) {
            if (playing) {
                pausedForCover = true
                pause()
            }
        } else if (pausedForCover) {
            pausedForCover = false
            if (!stopped) {
                resume()
            }
        }
    }

    /** The app left the screen: the position is saved at once and the video pauses, as YouTube's terms require. */
    fun stop() {
        stopped = true
        playback?.save(ProgressUpload.NOW)
        pause()
    }

    /** The app is on the screen again; the video stays paused. */
    fun start() {
        stopped = false
    }

    private fun current(token: String): Playback? = playback.takeIf { token == this.token }

    /** The page with [token] reports that its player changed state. */
    fun stateChanged(token: String, state: PlayerState, time: Double, duration: Double, last: Boolean) {
        current(token)?.let { playback ->
            playing = state == PlayerState.PLAYING
            if (playing && (covered || stopped)) {
                pausedForCover = covered
                pause()
            }
            playback.stateChanged(state, time, duration, last)
        }
    }

    /** The page with [token] reports where its player is. */
    fun positionChanged(token: String, time: Double, duration: Double) {
        current(token)?.positionChanged(time, duration)
    }

    /** The page with [token] reports that its player can't play the video, which ends it as its end does. */
    fun playerFailed(token: String) {
        current(token)?.failed()
    }

    /** The page with [token] reports that the IFrame API script didn't load. */
    fun loadFailed(token: String) {
        if (current(token) != null) {
            failed = true
        }
    }
}

/** One message from the player page. */
@Serializable
private class PlayerReport(
    val token: String,
    val kind: String,
    val code: Int = -1,
    val time: Double = 0.0,
    val duration: Double = 0.0,
    val last: Boolean = false,
)

private val reportJson = Json { ignoreUnknownKeys = true }

/**
 * What the player page reports, as JSON messages, passed on to [page] on the
 * main thread. Anything that doesn't read as a report is dropped.
 */
internal class PlayerBridge(private val page: PlayerPage) {
    private val main = Handler(Looper.getMainLooper())

    /** A message from the page; this is called on WebView's bridge thread. */
    @JavascriptInterface
    fun postMessage(message: String) {
        main.post {
            runCatching { reportJson.decodeFromString<PlayerReport>(message) }.getOrNull()?.let { report ->
                when (report.kind) {
                    "state" -> page.stateChanged(report.token, playerState(report.code), report.time, report.duration, report.last)
                    "position" -> page.positionChanged(report.token, report.time, report.duration)
                    "error" -> page.playerFailed(report.token)
                    "failed" -> page.loadFailed(report.token)
                }
            }
        }
    }
}

/**
 * Let the page at [origin] reach [bridge] as `SubtubePlayer.postMessage`.
 * Where the WebView can, only that page's own frame is given it, so the
 * YouTube frames inside can't call it; an older WebView gives it to every
 * frame, and the page's token is what keeps their calls out.
 */
private fun WebView.listenTo(bridge: PlayerBridge, origin: String) {
    if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
        WebViewCompat.addWebMessageListener(this, BRIDGE_NAME, setOf(origin)) { _, message, _, isMainFrame, _ ->
            val data = message.data
            if (isMainFrame && data != null) {
                bridge.postMessage(data)
            }
        }
    } else {
        addJavascriptInterface(bridge, BRIDGE_NAME)
    }
}

private fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** What the screens under the player tell it: where the bottom navigation bar's top edge is, in the window's pixels. */
internal class PlayerDock {
    /** The top edge of the bottom navigation bar; null before one is laid out. */
    var barTop: Float? by mutableStateOf(null)
}

/** The [PlayerDock] of the [PlayerHost] above. */
internal val LocalPlayerDock = staticCompositionLocalOf { PlayerDock() }

/**
 * Pauses the player while this is shown: call it from a sheet or a dialog,
 * which lies over the whole app and so over the player.
 */
@Composable
internal fun CoversPlayer(viewModel: SubtubeViewModel) {
    DisposableEffect(viewModel) {
        viewModel.coverPlayer(true)
        onDispose { viewModel.coverPlayer(false) }
    }
}

/**
 * The room a scrolling screen keeps under its last row while the player is in
 * the corner, so the row can be brought out from behind it; none otherwise.
 */
internal fun minimizedPlayerRoom(viewModel: SubtubeViewModel): Dp =
    if (viewModel.playing?.place == PlayerPlace.MINIMIZED) MIN_PLAYER_SIDE.dp + MinimizedBottomGap + MINIMIZED_MARGIN.dp else 0.dp

/**
 * The playing card's thumbnail box: empty, at least as high as YouTube
 * allows a player to be, and reporting where it is so the [PlayerHost] can
 * lay the player over it. Leaving the list's rows gives the player to the corner.
 */
@Composable
internal fun PlayerCardSlot(viewModel: SubtubeViewModel, id: String, modifier: Modifier = Modifier) {
    DisposableEffect(viewModel, id) {
        onDispose { viewModel.playerSlotGone(id) }
    }
    Box(
        modifier
            .fillMaxWidth()
            .layout { measurable, constraints ->
                val width = constraints.maxWidth
                val height = max(ceil(MIN_PLAYER_SIDE * density).toInt(), (width * 9f / 16f).roundToInt())
                val placeable = measurable.measure(Constraints.fixed(width, height))
                layout(width, height) { placeable.place(0, 0) }
            }
            .background(PlayerBackdrop)
            // the whole box, not boundsInRoot's, which is only the part the list shows
            .onGloballyPositioned { coordinates -> viewModel.playerSlotMoved(id, Rect(coordinates.positionInRoot(), coordinates.size.toSize())) },
    )
}

/** Fill the parent and put the content at [box], given in the parent's pixels, whatever the layout direction. */
private fun Modifier.placedAt(box: () -> IntRect): Modifier = layout { measurable, constraints ->
    val target = box()
    val placeable = measurable.measure(Constraints.fixed(max(0, target.width), max(0, target.height)))
    layout(constraints.maxWidth, constraints.maxHeight) { placeable.place(target.left, target.top) }
}

/**
 * The minimized player's video in a window of [window] pixels: the size
 * [minimizedSize] gives, in the bottom trailing corner of what is left
 * between the system bars, [MinimizedSideGap] in and [MinimizedBottomGap] above [floor] (the top of the bottom
 * navigation bar or of the keyboard).
 */
private fun Density.cornerBox(window: IntSize, startInset: Int, endInset: Int, floor: Int, direction: LayoutDirection): IntRect {
    val size = minimizedSize(((window.width - startInset - endInset) / density).toInt())
    // rounded up, so the video is never a pixel under what YouTube allows
    val width = ceil(size.width * density).toInt()
    val height = ceil(size.height * density).toInt()
    val side = MinimizedSideGap.roundToPx()
    val below = MinimizedBottomGap.roundToPx()
    val left = if (direction == LayoutDirection.Ltr) window.width - endInset - side - width else startInset + side
    return IntRect(left, floor - below - height, left + width, floor - below)
}

/** Where the player is drawn. */
private enum class Shown {
    /** Over its card's thumbnail. */
    CARD,

    /** In the bottom corner. */
    CORNER,

    /** Not at all: its card has not been laid out yet. */
    NOWHERE,
}

/** Where the player and its frame go, in the window's pixels; [window] is the window's size. */
private class PlayerBoxes(
    private val viewModel: SubtubeViewModel,
    private val dock: PlayerDock,
    private val density: Density,
    private val direction: LayoutDirection,
    private val safeArea: WindowInsets,
    private val keyboard: WindowInsets,
    private val window: () -> IntSize,
) {
    /** Where the player is drawn; null with no player. */
    val shown: Shown? by derivedStateOf {
        val playing = viewModel.playing
        if (playing == null) {
            null
        } else if (playing.place != PlayerPlace.CARD) {
            Shown.CORNER
        } else if (viewModel.playerSlot?.id == playing.item.id) {
            Shown.CARD
        } else {
            Shown.NOWHERE
        }
    }

    private fun whole(): IntRect = IntRect(0, 0, window().width, window().height)

    /** The part of the window the video may show in: its card's list, or all of it. */
    fun pane(): IntRect = (if (shown == Shown.CARD) viewModel.playerView?.roundToIntRect() else null) ?: whole()

    /** The minimized player's video. */
    fun corner(): IntRect = with(density) {
        val size = window()
        val navigationTop = dock.barTop?.toInt() ?: (size.height - safeArea.getBottom(this) - NavigationBarHeight.roundToPx())
        val floor = min(navigationTop, size.height - keyboard.getBottom(this))
        val startInset = if (direction == LayoutDirection.Ltr) safeArea.getLeft(this, direction) else safeArea.getRight(this, direction)
        val endInset = if (direction == LayoutDirection.Ltr) safeArea.getRight(this, direction) else safeArea.getLeft(this, direction)
        cornerBox(size, startInset, endInset, floor, direction)
    }

    /** The video: its card's whole thumbnail, the corner's box, or nothing. */
    fun video(): IntRect = when (shown) {
        Shown.CARD -> viewModel.playerSlot?.box?.roundToIntRect() ?: IntRect.Zero
        Shown.CORNER -> corner()
        else -> IntRect.Zero
    }

    /** [video] inside [pane]. */
    fun videoInPane(): IntRect {
        val origin = pane().topLeft
        return video().translate(-origin.x, -origin.y)
    }

    /** The frame around the minimized player's video. */
    fun frame(): IntRect {
        val inner = corner()
        val edge = with(density) { FrameEdge.roundToPx() }
        val bar = with(density) { PlayerBarHeight.roundToPx() }
        return IntRect(inner.left - edge, inner.top - bar - edge, inner.right + edge, inner.bottom + edge)
    }

    /** A touch went down at [position]: on the minimized video it shows the frame, anywhere but the frame it hides it. */
    fun touched(position: Offset) {
        val point = IntOffset(position.x.toInt(), position.y.toInt())
        if (shown == Shown.CORNER && corner().contains(point)) {
            viewModel.framePlayer(true)
        } else if (shown != null && !(viewModel.playerFramed && frame().contains(point))) {
            viewModel.framePlayer(false)
        }
    }
}

/**
 * The app's screens with the one player over them.
 *
 * The player is a single web view that is never re-created or moved to
 * another parent while something plays: it is laid over the playing card's
 * thumbnail ([PlayerCardSlot], cut off where the card's list ends) or in the
 * bottom trailing corner above the navigation bar, and stays through every
 * change of screen. A card that has not been laid out yet has it nowhere.
 * Nothing is ever drawn over it. See [SubtubeViewModel.playing] for what
 * moves it, and [CoversPlayer] for what pauses it.
 *
 * A touch on the minimized player's video shows a frame around it (a bar
 * above with the title, "Expand" and "Close"); a touch anywhere else, which
 * is also how a scroll starts, hides it. Nothing else shows or hides it. A
 * video in its card never has one. Touches are watched as they pass down to
 * the screens and the web view, never taken.
 */
@Composable
internal fun PlayerHost(viewModel: SubtubeViewModel, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val dock = remember { PlayerDock() }
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val safeArea = WindowInsets.safeDrawing
    val keyboard = WindowInsets.ime
    var window by remember { mutableStateOf(IntSize.Zero) }
    val boxes = remember(viewModel, dock, density, direction, safeArea, keyboard) {
        PlayerBoxes(viewModel, dock, density, direction, safeArea, keyboard) { window }
    }
    Box(
        modifier
            .fillMaxSize()
            .onSizeChanged { size -> window = size }
            .pointerInput(boxes) {
                awaitEachGesture {
                    // on the way down, before any screen or the web view has it, and left for them
                    boxes.touched(awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial).position)
                }
            },
    ) {
        CompositionLocalProvider(LocalPlayerDock provides dock, content = content)
        val item = viewModel.playing?.item
        if (item != null && window != IntSize.Zero) {
            PlayerOverlay(viewModel, item, boxes)
        }
    }
}

/**
 * The player playing [item], laid out by [boxes], and the frame behind it
 * while [SubtubeViewModel.playerFramed]. Where the IFrame API didn't load,
 * a text says so in the web view's place.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun PlayerOverlay(viewModel: SubtubeViewModel, item: FeedItem, boxes: PlayerBoxes) {
    val context = LocalContext.current
    val page = remember { PlayerPage() }
    var fullscreen by remember { mutableStateOf<Pair<View, WebChromeClient.CustomViewCallback>?>(null) }
    val webView = remember {
        WebView(context).apply {
            // without them a web view wraps its content, and the page's 100% height is then 0: the video has no height
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(android.graphics.Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            listenTo(PlayerBridge(page), playerOrigin(context))
            webViewClient = object : WebViewClient() {
                // unhandled, a web view whose renderer the system killed or that crashed takes the whole app down with it
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    viewModel.closePlayer()
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                    fullscreen = view to callback
                }

                override fun onHideCustomView() {
                    fullscreen = null
                }
            }
        }
    }
    DisposableEffect(webView) {
        page.pause = { webView.evaluateJavascript(PAUSE_SCRIPT, null) }
        page.resume = { webView.evaluateJavascript(PLAY_SCRIPT, null) }
        onDispose {
            page.close()
            webView.destroy()
        }
    }
    val playback = remember(item.id) {
        Playback(item.id, item is Playlist, viewModel) { viewModel.playbackEnded(item.id) }
    }
    DisposableEffect(playback) {
        val token = page.load(playback)
        val origin = playerOrigin(context)
        val html = if (item is Playlist) {
            playerHtml("playlist", "", item.id, 0.0, origin, token)
        } else {
            playerHtml("video", item.id, "", viewModel.resumeAt(item.id), origin, token)
        }
        // the same web view takes each entry in turn: only its page is replaced
        webView.loadDataWithBaseURL(origin, html, "text/html", "utf-8", null)
        onDispose { playback.save(ProgressUpload.SOON) }
    }
    LaunchedEffect(playback) {
        while (true) {
            delay(PROGRESS_EVERY_MS)
            playback.tick()
        }
    }
    val covered = viewModel.playerCovers > 0
    LaunchedEffect(covered) {
        page.cover(covered)
    }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, webView) {
        val lifecycle = lifecycleOwner.lifecycle
        if (!lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            page.stop()
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    page.stop()
                    webView.onPause()
                }
                Lifecycle.Event.ON_START -> {
                    page.start()
                    webView.onResume()
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val shownFullscreen = fullscreen
    val activity = context.findActivity()
    DisposableEffect(shownFullscreen != null) {
        viewModel.playerFullscreen(shownFullscreen != null)
        onDispose { viewModel.playerFullscreen(false) }
    }
    // a Short is upright: turning the screen for it would lay it on its side
    val turns = (item as? Video)?.isShort != true
    DisposableEffect(shownFullscreen, activity) {
        val window = activity?.window
        val decor = window?.decorView as? ViewGroup
        val controller = window?.let { activityWindow -> WindowCompat.getInsetsController(activityWindow, activityWindow.decorView) }
        val priorOrientation = activity?.requestedOrientation
        // the WebView stays attached underneath, or playback would stop
        val cover = shownFullscreen?.let { (view, _) ->
            FrameLayout(context).apply {
                setBackgroundColor(android.graphics.Color.BLACK)
                addView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            }
        }
        if (cover != null) {
            decor?.addView(cover, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller?.hide(WindowInsetsCompat.Type.systemBars())
            if (turns) {
                activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
        }
        onDispose {
            if (cover != null) {
                cover.removeAllViews()
                decor?.removeView(cover)
                controller?.show(WindowInsetsCompat.Type.systemBars())
                if (priorOrientation != null) {
                    activity.requestedOrientation = priorOrientation
                }
            }
        }
    }
    BackHandler(enabled = shownFullscreen != null) {
        shownFullscreen?.second?.onCustomViewHidden()
        fullscreen = null
    }
    val minimized = boxes.shown == Shown.CORNER
    val framed = minimized && viewModel.playerFramed
    // the frame rounds the corners it shares with the video; a card rounds only its top ones
    val shape = when {
        framed -> RoundedCornerShape(bottomStart = PlayerCorner - FrameEdge, bottomEnd = PlayerCorner - FrameEdge)
        minimized -> RoundedCornerShape(PlayerCorner)
        else -> RoundedCornerShape(topStart = PlayerCorner, topEnd = PlayerCorner)
    }
    val moves = motionAllowed()
    AnimatedVisibility(
        visible = framed,
        enter = if (moves) fadeIn(tween(FRAME_FADE_MS)) else EnterTransition.None,
        exit = if (moves) fadeOut(tween(FRAME_FADE_MS)) else ExitTransition.None,
        modifier = Modifier.placedAt(boxes::frame),
    ) {
        PlayerFrame(
            title = item.title,
            onExpand = viewModel::expandPlayer,
            onClose = viewModel::closePlayer,
            modifier = Modifier.fillMaxSize(),
        )
    }
    val name = item.title.ifEmpty { stringResource(R.string.player) }
    val expandOrMinimize = if (minimized) {
        CustomAccessibilityAction(stringResource(R.string.expand)) {
            viewModel.expandPlayer()
            true
        }
    } else {
        CustomAccessibilityAction(stringResource(R.string.minimize)) {
            viewModel.minimizePlayer()
            true
        }
    }
    val close = CustomAccessibilityAction(stringResource(R.string.close)) {
        viewModel.closePlayer()
        true
    }
    Box(Modifier.placedAt(boxes::pane).clipToBounds()) {
        Box(
            Modifier
                .placedAt(boxes::videoInPane)
                .shadow(if (minimized && !framed) 6.dp else 0.dp, shape, clip = true)
                .background(PlayerBackdrop)
                .semantics {
                    contentDescription = name
                    customActions = listOf(expandOrMinimize, close)
                },
        ) {
            AndroidView(
                factory = { webView },
                modifier = Modifier.fillMaxSize(),
                update = { view -> view.visibility = if (page.failed) View.INVISIBLE else View.VISIBLE },
            )
            if (page.failed) {
                Text(
                    stringResource(R.string.player_failed),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                )
            }
        }
    }
}

/**
 * The frame behind the minimized player's video: the surface colour reaching
 * a hairline past its sides and bottom, and above it a bar with [title],
 * "Expand" and "Close".
 * The video is drawn over the rest of it, so nothing here is ever over the video.
 */
@Composable
private fun PlayerFrame(
    title: String,
    onExpand: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = RoundedCornerShape(PlayerCorner),
        shadowElevation = 6.dp,
        modifier = modifier,
    ) {
        // a surface hands its own size down as the least its content may be: the box takes that, not the bar
        Box {
            Row(
                Modifier.fillMaxWidth().padding(top = FrameEdge).height(PlayerBarHeight).padding(start = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onExpand) {
                    Icon(SubtubeIcons.Expand, contentDescription = stringResource(R.string.expand))
                }
                IconButton(onClick = onClose) {
                    Icon(SubtubeIcons.Close, contentDescription = stringResource(R.string.close))
                }
            }
        }
    }
}
