package cc.hafa.subtube

import android.app.Application
import android.content.Context
import cc.hafa.subtube.auth.GoogleAuth
import cc.hafa.subtube.core.DriveClient
import cc.hafa.subtube.core.ShortsProbe
import cc.hafa.subtube.core.YouTubeClient
import cc.hafa.subtube.data.AccountPrefs
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient

/** Holds the app-wide clients, so every screen shares one HTTP connection pool. */
class SubtubeApp : Application(), SingletonImageLoader.Factory {
    /** The one HTTP client, and so the one connection pool. */
    val http: OkHttpClient by lazy { OkHttpClient() }

    /** The YouTube Data API. */
    val youtube: YouTubeClient by lazy { YouTubeClient(http) }

    /** The Drive app folder. */
    val drive: DriveClient by lazy { DriveClient(http) }

    /** Asks youtube.com whether a video is a Short, for when a channel's Shorts list can't be read. */
    val shortsProbe: ShortsProbe by lazy { ShortsProbe(http) }

    /** Google sign-in and tokens. */
    val auth: GoogleAuth by lazy { GoogleAuth(this, http) }

    /** What this install remembers: the account, its device id, the theme. */
    val prefs: AccountPrefs by lazy { AccountPrefs(this) }

    /** Outlives every screen, so a pending Drive upload isn't cut off when one closes. */
    val backgroundScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { http })) }
            .build()
}

/** The [SubtubeApp] this context belongs to. */
val Context.subtube: SubtubeApp get() = applicationContext as SubtubeApp
