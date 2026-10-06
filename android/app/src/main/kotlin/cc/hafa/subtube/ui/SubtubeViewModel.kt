package cc.hafa.subtube.ui

import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.annotation.StringRes
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.geometry.Rect
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import cc.hafa.subtube.R
import cc.hafa.subtube.auth.AuthorizeOutcome
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.ChipTitle
import cc.hafa.subtube.core.GroupEdit
import cc.hafa.subtube.core.GroupSelections
import cc.hafa.subtube.core.ChannelIdentityCache
import cc.hafa.subtube.core.ChannelItems
import cc.hafa.subtube.core.ChannelKind
import cc.hafa.subtube.core.ChannelSort
import cc.hafa.subtube.core.ChannelSummary
import cc.hafa.subtube.core.ContentMode
import cc.hafa.subtube.core.DailyLimitException
import cc.hafa.subtube.core.DriveFile
import cc.hafa.subtube.core.DriveUser
import cc.hafa.subtube.core.FETCH_CONCURRENCY
import cc.hafa.subtube.core.FeedData
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.FeedLoader
import cc.hafa.subtube.core.FeedSort
import cc.hafa.subtube.core.InsufficientScopeException
import cc.hafa.subtube.core.NoYouTubeChannelException
import cc.hafa.subtube.core.PlaybackFeed
import cc.hafa.subtube.core.Playlist
import cc.hafa.subtube.core.Prefetch
import cc.hafa.subtube.core.ProfileDeletedException
import cc.hafa.subtube.core.ProgressUpload
import cc.hafa.subtube.core.SettingName
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.core.ShortsFilter
import cc.hafa.subtube.core.StartFrom
import cc.hafa.subtube.core.applyStart
import cc.hafa.subtube.core.channelsByName
import cc.hafa.subtube.core.commonShortsFilter
import cc.hafa.subtube.core.deviceFileName
import cc.hafa.subtube.core.pendingStart
import cc.hafa.subtube.core.Subscription
import cc.hafa.subtube.core.SyncStore
import cc.hafa.subtube.core.TimeChip
import cc.hafa.subtube.core.TokenExpiredException
import cc.hafa.subtube.core.Video
import cc.hafa.subtube.core.WatchedMode
import cc.hafa.subtube.core.afterCardMeasured
import cc.hafa.subtube.core.afterEnd
import cc.hafa.subtube.core.afterPageChange
import cc.hafa.subtube.core.cardHolds
import cc.hafa.subtube.core.expanded
import cc.hafa.subtube.core.minimized
import cc.hafa.subtube.core.played
import cc.hafa.subtube.core.PlayerPlace
import cc.hafa.subtube.core.Playing
import cc.hafa.subtube.core.ScreenBox
import cc.hafa.subtube.core.chipFiltered
import cc.hafa.subtube.core.chipKeptChannels
import cc.hafa.subtube.core.chipTitle
import cc.hafa.subtube.core.deleteGroup
import cc.hafa.subtube.core.entryFilter
import cc.hafa.subtube.core.filterFromJson
import cc.hafa.subtube.core.groupKeptChannels
import cc.hafa.subtube.core.groupNames
import cc.hafa.subtube.core.keptByBoth
import cc.hafa.subtube.core.saveGroup
import cc.hafa.subtube.core.selectedGroups
import cc.hafa.subtube.core.chipRow
import cc.hafa.subtube.core.compileFilter
import cc.hafa.subtube.core.emptiedBySelection
import cc.hafa.subtube.core.entryWatched
import cc.hafa.subtube.core.isAlreadySetUp
import cc.hafa.subtube.core.isWatchedEntry
import cc.hafa.subtube.core.heldOrder
import cc.hafa.subtube.core.keptAfterLoad
import cc.hafa.subtube.core.listedOrder
import cc.hafa.subtube.core.loadProgress
import cc.hafa.subtube.core.markedEntry
import cc.hafa.subtube.core.modeFiltered
import cc.hafa.subtube.core.needsShorts
import cc.hafa.subtube.core.newShuffleSeed
import cc.hafa.subtube.core.newestFetched
import cc.hafa.subtube.core.orderChannels
import cc.hafa.subtube.core.passesFilter
import cc.hafa.subtube.core.passingItems
import cc.hafa.subtube.core.playedEntry
import cc.hafa.subtube.core.progressFraction
import cc.hafa.subtube.core.resumePosition
import cc.hafa.subtube.core.sortFeed
import cc.hafa.subtube.core.unwatchedPassing
import cc.hafa.subtube.data.FileSyncStorage
import cc.hafa.subtube.data.ThemeMode
import cc.hafa.subtube.subtube
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Returning to the app after this long away loads the feed again. */
private const val STALE_AFTER_MS = 15 * 60_000L

/** How many channels the made-up data's running load shows as through. */
private const val DEMO_CHANNELS_LOADED = 3

/** Tag for errors kept out of the interface. */
private const val LOG_TAG = "subtube"

/** Google has no token to give without the user: signed out of Google, or consent withdrawn. */
private class SignInNeededException : Exception("Google sign-in needed")

/** How long after full screen ends a card's player is left in its card, while the window settles back. */
private const val AFTER_FULLSCREEN_MS = 500L

/** Text for a banner or an error line. */
data class UiMessage(
    /** The text's string resource. */
    @param:StringRes val resId: Int,
    /** Whether signing in again fixes what it says, so a "Sign in" button goes with it. */
    val offersSignIn: Boolean = false,
)

/** Where the app is with Google. */
sealed interface Session {
    /** No account; first run or after signing out. */
    data object SignedOut : Session

    /** Signed in as [account], the YouTube channel that keys this account's data. */
    data class SignedIn(val account: ChannelSummary) : Session
}

/** A place in the app's back stack. */
sealed interface Screen {
    /** First run: intro, sign-in, channels, Shorts, where to start, done. */
    data object SetUp : Screen

    /** The feed tab, the root of the stack. */
    data object Feed : Screen

    /** The channels tab. */
    data object Channels : Screen

    /** The settings tab. */
    data object Settings : Screen

    /** One channel's page, over the feed or the channels tab. */
    data class ChannelPage(val channelId: String) : Screen
}

/** A card a page's list is asked to bring into view. */
data class CardRequest(
    /** The entry whose card it is. */
    val id: String,
    /** The page whose list is asked: a channel's id, or null for the feed. */
    val page: String?,
    /** What tells one request from the next. */
    val serial: Int,
)

/** Where the playing card's thumbnail is, in the window's pixels. */
data class PlayerSlot(
    /** The entry whose card it is. */
    val id: String,
    /** The thumbnail's box. */
    val box: Rect,
)

/** The first-run steps, in order. */
enum class SetUpStep {
    /** What SubTube is. */
    INTRO,

    /** Signing in with Google. */
    SIGN_IN,

    /** Choosing which subscriptions are on. */
    CHANNELS,

    /** The Shorts choice for every channel. */
    SHORTS,

    /** Where the feed starts. */
    START,

    /** The last screen, which opens the feed. */
    DONE,
}

/** What a list of cards shows, with the topic chips counted over it. */
data class ShownList(
    /** The cards, in the chosen order. */
    val items: List<FeedItem> = emptyList(),
    /** The topic chips' category ids, in row order. */
    val topics: List<String> = emptyList(),
)

/** The content mode an item belongs to. */
private val FeedItem.contentMode: ContentMode
    get() = if (this is Playlist) ContentMode.PLAYLISTS else ContentMode.VIDEOS

/** A feed item's length in seconds; 0 for a playlist or a video of unknown length. */
private val FeedItem.lengthSeconds: Double
    get() = ((this as? Video)?.durationSeconds ?: 0).toDouble()

/** A channel and content mode, the unit that is fetched. */
private typealias FetchKey = ChannelKind

/** What a channel's filter fetches. */
private val ChannelFilter.fetchKey: FetchKey
    get() = channelId to (contentMode ?: ContentMode.VIDEOS)

/** Made-up data for [SubtubeViewModel.showDemo]. */
data class DemoData(
    /** Null shows the app signed out. */
    val account: ChannelSummary?,
    /** The Google account Settings shows. */
    val user: DriveUser,
    /** The account's YouTube subscriptions. */
    val subscriptions: List<Subscription>,
    /** Every listed channel with its filter. */
    val channels: List<ChannelFilter>,
    /** Everything fetched. */
    val items: List<FeedItem>,
    /** The ids marked watched. */
    val watched: Set<String>,
    /** How far part-watched videos have been played, in seconds, by id. */
    val positions: Map<String, Long> = emptyMap(),
    /** The synced settings the chips show. */
    val settings: Settings = Settings(),
    /** What the watched chip is on. */
    val watchedMode: WatchedMode = WatchedMode.UNWATCHED,
    /** The first-run step to show; null skips first run. */
    val step: SetUpStep?,
    /** The back stack when first run is skipped. */
    val screens: List<Screen>,
    /** Whether the first unwatched card is playing in place. */
    val play: Boolean,
    /** Whether that player is in the corner instead. */
    val minimized: Boolean = false,
    /** Whether a load is shown as running: over [items], or as a first load when there are none. */
    val loading: Boolean = false,
)

/**
 * Session, navigation, feed, first run and player state. The feed is every
 * fetched item that passes the filters and the chips, in the chosen order. A
 * full load (Refresh, startup, coming back after being away) leaves the
 * previous feed in place until it finishes; a filter edit only re-filters,
 * fetching just a channel whose filter needs something not fetched. A video
 * is watched once it is marked, or played into its last 10 seconds (`Progress.kt`).
 */
class SubtubeViewModel(application: Application) : AndroidViewModel(application), PlaybackFeed {
    private val app = application.subtube

    /** Where the app is with Google. */
    var session: Session by mutableStateOf(Session.SignedOut)
        private set

    /** Whether a sign-in is under way. */
    var signingIn: Boolean by mutableStateOf(false)
        private set

    /** Why the last sign-in failed, for first run's sign-in step; null when it didn't. */
    var signInError: UiMessage? by mutableStateOf(null)
        private set

    /** The chosen colour theme. */
    var themeMode: ThemeMode by mutableStateOf(app.prefs.themeMode)
        private set

    /** The screens, root first; the last is shown. */
    val backStack: SnapshotStateList<Screen> = mutableStateListOf()

    /** The account's YouTube subscriptions, as of the last load. */
    var subscriptions: List<Subscription> by mutableStateOf(emptyList())
        private set

    /** Every listed channel with its filter, by channel id. */
    var channels: Map<String, ChannelFilter> by mutableStateOf(emptyMap())
        private set

    /** The ids of the loaded entries that are watched. */
    var watched: Set<String> by mutableStateOf(emptySet())
        private set

    /** Whether a full load is running. */
    var loading: Boolean by mutableStateOf(false)
        private set

    /** How far the full load that is running has come, from 0 to 1; null when none is. */
    var loadFraction: Double? by mutableStateOf(null)
        private set

    /** Whether a profile delete is running. */
    var deletingProfile: Boolean by mutableStateOf(false)
        private set

    /** Why the last load or fetch failed, for the lists' banner; null when it didn't. */
    var error: UiMessage? by mutableStateOf(null)
        private set

    /** Why the last "Delete profile" failed, shown with that button; null when it didn't. */
    var deleteError: UiMessage? by mutableStateOf(null)
        private set

    /** Why the last "Sign out" failed, shown with that button; null when it didn't. */
    var signOutError: UiMessage? by mutableStateOf(null)
        private set

    /** The partial-load or daily-limit notice, until it is dismissed; null for none. */
    var notice: UiMessage? by mutableStateOf(null)
        private set

    /** When Drive last answered (ms since the epoch); null until it has. */
    var lastSynced: Long? by mutableStateOf(null)
        private set

    /** The signed-in Google account's name and address, once asked for. */
    var user: DriveUser? by mutableStateOf(null)
        private set

    /** How full each loaded video's progress bar is, from 0 to 1; videos with no bar are absent. */
    var bars: Map<String, Double> by mutableStateOf(emptyMap())
        private set

    /** The synced settings, as of the last load plus changes made here since. */
    var settings: Settings by mutableStateOf(Settings())
        private set

    /** Which of watched and unwatched entries the lists show; kept for this visit only. */
    var watchedMode: WatchedMode by mutableStateOf(WatchedMode.UNWATCHED)
        private set

    /** What the feed shows. */
    var feed: ShownList by mutableStateOf(ShownList())
        private set

    /** What the open channel page shows; empty when none is open. */
    var channelFeed: ShownList by mutableStateOf(ShownList())
        private set

    /** What the one player plays and where it is drawn; null when there is no player. */
    var playing: Playing? by mutableStateOf(null)
        private set

    /** The playing card's thumbnail box, while the player is in a card that is laid out. */
    var playerSlot: PlayerSlot? by mutableStateOf(null)
        private set

    /** The box of the list the playing card is in, in the window's pixels: what scrolls out of it is cut off. */
    var playerView: Rect? by mutableStateOf(null)
        private set

    /** Whether the frame around the minimized player's video shows: the user's last touch was on the video. */
    var playerFramed: Boolean by mutableStateOf(false)
        private set

    /** How many sheets and dialogs lie over the app, and so over the player, which is paused meanwhile. */
    var playerCovers: Int by mutableIntStateOf(0)
        private set

    /** The card its page's list is asked to bring into view; null once it has. */
    var cardRequest: CardRequest? by mutableStateOf(null)
        private set

    // a card was given the player and its list is still bringing it into view: until then it needn't hold the player
    private var settling = false
    private var cardRequests = 0

    // the video fills the screen, or did a moment ago: its card's box means nothing meanwhile
    private var fullscreenHold = false
    private var fullscreenRelease: Job? = null

    /** The first-run step showing. */
    var setUpStep: SetUpStep by mutableStateOf(SetUpStep.INTRO)
        private set

    /** Whether first run's channel list is loading. */
    var setUpLoading: Boolean by mutableStateOf(false)
        private set

    /** Why first run's channel list couldn't be loaded; null when it could. */
    var setUpError: UiMessage? by mutableStateOf(null)
        private set

    /** Every channel offered on the first-run channel step, by title. */
    var setUpChannels: List<ChannelFilter> by mutableStateOf(emptyList())
        private set

    /** The first-run channel step's switches. */
    var setUpEnabled: Map<String, Boolean> by mutableStateOf(emptyMap())
        private set

    /** First run's Shorts choice for every channel. */
    var setUpShorts: ShortsFilter by mutableStateOf(ShortsFilter.ALL)

    /** The Shorts choice the channels were loaded with; Next applies [setUpShorts] only when it differs. */
    private var setUpShortsStart: ShortsFilter = ShortsFilter.ALL

    /** First run's starting point: older videos are marked watched at the first load. */
    var setUpStart: StartFrom by mutableStateOf(StartFrom.ALL)

    /** Asks the feed to scroll back to its top. */
    val feedTopRequests: MutableSharedFlow<Unit> = MutableSharedFlow(extraBufferCapacity = 1)

    /** Consent screens for the activity to launch. */
    val consentRequests: Flow<PendingIntent> get() = consentChannel.receiveAsFlow()
    private val consentChannel = Channel<PendingIntent>(Channel.BUFFERED)

    private var items: List<FeedItem> by mutableStateOf(emptyList())

    private val itemsById: Map<String, FeedItem> by derivedStateOf { items.associateBy(FeedItem::id) }

    /** How many unwatched entries pass each on channel's filter, by channel id; channels with none are absent. */
    val unwatchedByChannel: Map<String, Int> by derivedStateOf {
        val byChannel = items.groupBy(FeedItem::channelId)
        channels.values.filter(ChannelFilter::enabled)
            .associate { channel -> channel.channelId to unwatchedPassing(channel, byChannel[channel.channelId].orEmpty(), watched).size }
            .filterValues { count -> count > 0 }
    }

    /** Every on channel's fetched entries of the kind it shows that pass its filter, watched or not. */
    private val listedItems: List<FeedItem> by derivedStateOf { passingItems(channels.values, items) }

    /** The channels tab's topic chips, as category ids in row order. */
    val channelTopics: List<String> by derivedStateOf { chipRow(listedItems, settings.channelTopicChips) }

    /** The groups that exist, in chip order. */
    val groups: List<String> by derivedStateOf { groupNames(channels.values) }

    // the channels the channels tab's group, time and topic chips keep; null while they keep every one
    private val chipChannels: Set<String>? by derivedStateOf {
        keptByBoth(
            groupKeptChannels(channels.values, settings.channelGroupChips),
            chipKeptChannels(listedItems, settings.channelTimeChip, settings.channelTopicChips, chipClock),
        )
    }

    /** What the feed's title shows while its row has groups or topics selected. */
    val feedTitle: ChipTitle by derivedStateOf { chipTitle(groups, settings.groupChips, feed.topics, settings.topicChips) }

    /** What the channels tab's title shows while its row has groups or topics selected. */
    val channelsTitle: ChipTitle by derivedStateOf { chipTitle(groups, settings.channelGroupChips, channelTopics, settings.channelTopicChips) }

    /** The topics selected on the open channel's page, which has no groups; its title only gains "Clear" with any. */
    val channelPageTitle: ChipTitle by derivedStateOf { chipTitle(emptyList(), emptyList(), channelFeed.topics, settings.topicChips) }

    // the channel list's rows as last taken; they keep their places whatever changes under them
    private var channelOrder: List<String> by mutableStateOf(emptyList())

    /** Whether a full load has been shown since the session began; the chip rows' "New group" chip waits for it. */
    var loadShown: Boolean by mutableStateOf(false)
        private set

    private val channelsBySort: List<String> by derivedStateOf {
        orderChannels(channels.values, newestFetched(items), settings.channelSort, unwatchedByChannel).map(ChannelFilter::channelId)
    }

    /**
     * The channels the channels tab shows: those its group, time and topic chips
     * keep, by the channel sort, off channels last, as of the last
     * [reorderChannels]; one that has stopped being kept since stays in its
     * place. Each row is the channel as it is now.
     */
    val orderedChannels: List<ChannelFilter> by derivedStateOf {
        heldOrder(channelOrder, channelsBySort, chipChannels).mapNotNull(channels::get)
    }

    /** Whether the channels tab's group, time or topic chips are narrowing it, so an empty list says so; never before the first load is shown. */
    val channelChipsChosen: Boolean by derivedStateOf { loadShown && chipChannels != null }

    // the entries of the channels left on, fetched from first run's "Choose channels" Next; the first load takes it
    private var prefetch: Prefetch? = null

    // channels and modes whose entries are in [items]
    private var fetched: Set<FetchKey> = emptySet()

    // channels whose uploads in [items] were judged with their Shorts list
    private var shortsListed: Set<String> = emptySet()

    // goes up when YouTube's daily limit refuses a request, so fetches still waiting their turn aren't sent
    private var fetchRound = 0

    // channels and modes being fetched on their own
    private var fetching: Set<FetchKey> by mutableStateOf(emptySet())
    private val fetchPermits = Semaphore(FETCH_CONCURRENCY)

    // became watched or unwatched since the lists were last rebuilt afresh; these stay on screen whatever the watched chip lists
    private var staying: Set<String> = emptySet()

    // fixes the random order until the next full load
    private var shuffleSeed: UInt = newShuffleSeed()

    // the time the time chips count back from
    private var chipClock: Long by mutableLongStateOf(System.currentTimeMillis())

    // the watched entries of made-up data, which has no store
    private var demoEntries: Map<String, JsonObject> = emptyMap()

    private val pageChannelId: String?
        get() = backStack.filterIsInstance<Screen.ChannelPage>().lastOrNull()?.channelId
    private var store: SyncStore? = null
    private var identities: ChannelIdentityCache? = null
    private var loader: FeedLoader? = null
    private var loadInFlight = false
    private var loadJob: Job? = null
    private var lastLoadedAt = 0L
    private var syncWatcher: Job? = null

    // goes up with every new store, so a load begun on an older one changes nothing when it ends
    private var sessionEpoch = 0

    // showing made-up data: no account, so nothing is asked of Google or kept
    private var demo = false

    init {
        val account = app.prefs.account
        if (account != null) {
            startSession(account)
        }
        if (account != null && app.prefs.isSetUpDone(account.channelId)) {
            backStack.add(Screen.Feed)
            loadFeed()
        } else {
            backStack.add(Screen.SetUp)
            if (account != null) {
                // first run was cut short after signing in
                setUpStep = SetUpStep.CHANNELS
                loadSetUpChannels()
            }
        }
    }

    /**
     * Replace everything with made-up data and no account behind it, so nothing
     * loads, saves or syncs and sign-in does nothing. The debug build's demo
     * mode calls this at launch.
     */
    fun showDemo(data: DemoData) {
        demo = true
        syncWatcher?.cancel()
        store = null
        identities = null
        loader = null
        sessionEpoch += 1
        clearFeed()
        loading = false
        loadFraction = null
        loadInFlight = false
        // never stale, so coming to the foreground loads nothing
        lastLoadedAt = Long.MAX_VALUE
        lastSynced = System.currentTimeMillis()
        session = data.account?.let(Session::SignedIn) ?: Session.SignedOut
        user = data.user
        subscriptions = data.subscriptions
        channels = data.channels.associateBy(ChannelFilter::channelId)
        items = data.items
        demoEntries = data.watched.associateWith { markedEntry(null, 0, watched = true) } +
            data.positions.mapValues { (_, position) -> playedEntry(null, 0, position, ended = false) }
        fetched = data.channels.mapTo(HashSet(), ChannelFilter::fetchKey)
        shortsListed = channels.keys
        settings = data.settings
        watchedMode = data.watchedMode
        applyWatched(data.items)
        backStack.clear()
        if (data.step != null) {
            setUpChannels = data.channels.sortedWith(channelsByName)
            setUpEnabled = channels.mapValues { (_, filter) -> filter.enabled }
            setUpShortsStart = commonShortsFilter(setUpChannels)
            setUpShorts = setUpShortsStart
            backStack.add(Screen.SetUp)
            setUpStep = data.step
        } else {
            backStack.addAll(data.screens)
        }
        recompute(fresh = true)
        loadShown = data.step == null && (!data.loading || data.items.isNotEmpty())
        reorderChannels()
        loading = data.loading
        loadFraction = if (data.loading) loadProgress(finished = DEMO_CHANNELS_LOADED, total = data.channels.count(ChannelFilter::enabled)) else null
        if (data.play) {
            feed.items.firstOrNull { item -> item.id !in watched }?.let(::play)
            if (data.minimized) {
                minimizePlayer()
            }
        }
    }

    private fun startSession(account: ChannelSummary) {
        val syncStore = SyncStore(
            accountId = account.channelId,
            deviceId = app.prefs.deviceId,
            getToken = { app.auth.silentToken() ?: throw SignInNeededException() },
            replaceToken = { refused -> app.auth.replaceRejected(refused) ?: throw TokenExpiredException() },
            drive = app.drive,
            storage = FileSyncStorage(app),
            scope = app.backgroundScope,
        )
        store = syncStore
        settings = syncStore.settings()
        val identityCache = ChannelIdentityCache(FileSyncStorage(app), account.channelId)
        identities = identityCache
        loader = FeedLoader(app.youtube, syncStore, identityCache, app.shortsProbe::isShort)
        session = Session.SignedIn(account)
        sessionEpoch += 1
        syncWatcher?.cancel()
        syncWatcher = viewModelScope.launch {
            launch { syncStore.lastSynced.collect { at -> lastSynced = at } }
            syncStore.deletedElsewhere.first { deleted -> deleted }
            restartSetUp()
        }
    }

    /** Drop everything kept on this device for the account's profile. */
    private fun forgetProfile() {
        identities?.clear()
        (session as? Session.SignedIn)?.let { signedIn ->
            app.prefs.setSetUpDone(signedIn.account.channelId, false)
            app.prefs.keepPendingStart(signedIn.account.channelId, null)
        }
        clearFeed()
        lastLoadedAt = 0L
        lastSynced = null
    }

    /** The profile is gone but the account is still signed in: first run again, from the channel step. */
    private fun restartSetUp() {
        val account = (session as? Session.SignedIn)?.account ?: return
        forgetProfile()
        startSession(account)
        setUpStep = SetUpStep.CHANNELS
        backStack.clear()
        backStack.add(Screen.SetUp)
        loadSetUpChannels()
    }

    /** Forget the account and show first run at [step]; whether it finished first run here is remembered for its next sign-in. */
    private fun forgetAccount(step: SetUpStep) {
        app.prefs.account = null
        sessionEpoch += 1
        syncWatcher?.cancel()
        store = null
        identities = null
        loader = null
        lastSynced = null
        user = null
        clearFeed()
        session = Session.SignedOut
        setUpStep = step
        backStack.clear()
        backStack.add(Screen.SetUp)
    }

    /**
     * Delete the profile from Drive and from this device, withdraw Google's
     * grant, then sign out to the first setup screen. A failed Drive call
     * leaves everything as it was and says so beside the button.
     */
    fun deleteProfile() {
        val syncStore = store ?: return
        if (deletingProfile) {
            return
        }
        deletingProfile = true
        deleteError = null
        viewModelScope.launch {
            try {
                syncStore.deleteProfile()
                forgetProfile()
                app.auth.revoke()
                forgetAccount(SetUpStep.INTRO)
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                Log.w(LOG_TAG, "profile delete failed", caught)
                deleteError = UiMessage(R.string.delete_profile_failed)
            } finally {
                deletingProfile = false
            }
        }
    }

    /** Run [block] with a token, minting a fresh one once if Google rejects it. */
    private suspend fun <Result> withToken(block: suspend (String) -> Result): Result {
        val token = app.auth.silentToken() ?: throw SignInNeededException()
        return try {
            block(token)
        } catch (_: TokenExpiredException) {
            block(app.auth.replaceRejected(token) ?: throw TokenExpiredException())
        }
    }

    /** What to tell the user about [caught]; what it was is logged, never shown. */
    private fun describe(caught: Exception): UiMessage = when (caught) {
        is SignInNeededException -> UiMessage(R.string.sign_in_again, offersSignIn = true)
        is TokenExpiredException -> UiMessage(R.string.session_ended, offersSignIn = true)
        is InsufficientScopeException -> UiMessage(R.string.needs_permissions, offersSignIn = true)
        is NoYouTubeChannelException -> UiMessage(R.string.no_youtube_channel)
        is DailyLimitException -> UiMessage(R.string.daily_limit)
        else -> {
            if (caught !is IOException) {
                Log.w(LOG_TAG, "Google request failed", caught)
            }
            UiMessage(R.string.cant_reach_google)
        }
    }

    /** Ask Google for the account's name and address, once per sign-in. */
    fun loadUser() {
        if (user != null || session !is Session.SignedIn) {
            return
        }
        viewModelScope.launch {
            try {
                user = withToken { token -> app.drive.about(token) }
            } catch (caught: CancellationException) {
                throw caught
            } catch (_: Exception) {
                // the channel's name stays
            }
        }
    }

    /** Pick the colour theme. */
    fun chooseTheme(mode: ThemeMode) {
        themeMode = mode
        app.prefs.themeMode = mode
    }

    /**
     * Show a tab, with the feed underneath any other tab so Back returns to
     * it; a channel's page over it closes, and a card that is playing goes to
     * the corner. The Feed tab chosen while the feed
     * is already showing scrolls it to the top and refreshes.
     */
    fun selectTab(tab: Screen) {
        val stack = if (tab == Screen.Feed) listOf(Screen.Feed) else listOf(Screen.Feed, tab)
        if (backStack.toList() != stack) {
            channelFeed = ShownList()
            backStack.clear()
            backStack.addAll(stack)
            pageChanged()
            if (tab == Screen.Channels) {
                reorderChannels()
            }
        } else if (tab == Screen.Feed) {
            feedTopRequests.tryEmit(Unit)
            refresh()
        }
    }

    /** Leave the top screen; a card that is playing on it goes to the corner. */
    fun pop() {
        if (backStack.size > 1) {
            if (backStack.removeAt(backStack.lastIndex) is Screen.ChannelPage) {
                channelFeed = ShownList()
            }
            pageChanged()
            if (backStack.lastOrNull() == Screen.Channels) {
                reorderChannels()
            }
        }
    }

    /**
     * Take the channels tab's rows afresh: the channels its chips keep, in
     * the channel sort's order as it is now. The tab calls this when its
     * search text changes; entering the tab, a full load and its chips do it
     * too. Between those the rows stay put.
     */
    fun reorderChannels() {
        channelOrder = listedOrder(channelsBySort, chipChannels)
    }

    /** Keep the channels tab's rows where they are through a change to what orders them. */
    private fun holdChannelOrder() {
        channelOrder = orderedChannels.map(ChannelFilter::channelId)
    }

    /**
     * Open a channel's page over the feed or the channels tab, leaving any
     * other channel's page and sending a card that is playing to the corner. A channel that
     * is off, or whose filter needs something not fetched, is fetched for it.
     */
    fun showChannel(channelId: String) {
        val channel = channels[channelId]
        if (channel != null && pageChannelId != channelId) {
            backStack.removeAll { screen -> screen is Screen.ChannelPage }
            backStack.add(Screen.ChannelPage(channelId))
            recompute()
            // a running load brings a channel that is on
            if (isMissing(channel) && (!channel.enabled || !loadInFlight)) {
                fetchChannelIntoFeed(channel)
            }
        }
    }

    /** Whether [channel]'s entries are being fetched on their own. */
    fun isFetching(channel: ChannelFilter): Boolean = channel.fetchKey in fetching

    /** Move through first run. */
    fun goToStep(step: SetUpStep) {
        setUpStep = step
        if (step == SetUpStep.CHANNELS && setUpChannels.isEmpty()) {
            loadSetUpChannels()
        }
    }

    /**
     * Start interactive sign-in, or reconnect after the token was lost. From
     * signed out, Google is asked to let the user pick the account.
     */
    fun signIn() {
        if (signingIn || demo) {
            return
        }
        signingIn = true
        signInError = null
        viewModelScope.launch {
            try {
                when (val outcome = app.auth.authorize(chooseAccount = session is Session.SignedOut)) {
                    is AuthorizeOutcome.Granted -> finishSignIn(outcome.accessToken)
                    is AuthorizeOutcome.NeedsConsent -> consentChannel.send(outcome.pendingIntent)
                }
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                failSignIn(caught)
            }
        }
    }

    /** The consent screen closed; [data] is null when it was dismissed. */
    fun onConsentResult(approved: Boolean, data: Intent?) {
        if (!approved) {
            signingIn = false
            return
        }
        viewModelScope.launch {
            try {
                finishSignIn(app.auth.completeConsent(data))
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                failSignIn(caught)
            }
        }
    }

    private suspend fun finishSignIn(token: String) {
        val account = app.youtube.fetchMyChannel(token)
        val current = session
        if (current !is Session.SignedIn || current.account.channelId != account.channelId) {
            clearFeed()
            startSession(account)
        }
        app.prefs.account = account
        session = Session.SignedIn(account)
        signingIn = false
        error = null
        if (app.prefs.isSetUpDone(account.channelId)) {
            if (backStack.lastOrNull() == Screen.SetUp) {
                backStack.clear()
                backStack.add(Screen.Feed)
            }
            loadFeed()
        } else {
            // an account that hasn't finished first run here goes through it, wherever it signed in from
            if (backStack.lastOrNull() != Screen.SetUp) {
                backStack.clear()
                backStack.add(Screen.SetUp)
            }
            goToStep(SetUpStep.CHANNELS)
        }
    }

    private fun failSignIn(caught: Exception) {
        signingIn = false
        // closing Google's page is the user's choice, not a failure
        if ((caught as? ApiException)?.statusCode != CommonStatusCodes.CANCELED) {
            val message = describe(caught)
            signInError = message
            if (backStack.lastOrNull() != Screen.SetUp) {
                error = message
            }
        }
    }

    private fun clearFeed() {
        subscriptions = emptyList()
        channels = emptyMap()
        watched = emptySet()
        bars = emptyMap()
        items = emptyList()
        fetched = emptySet()
        shortsListed = emptySet()
        feed = ShownList()
        channelFeed = ShownList()
        channelOrder = emptyList()
        loadShown = false
        fetching = emptySet()
        staying = emptySet()
        closePlayer()
        loadJob?.cancel()
        loadJob = null
        loadInFlight = false
        loading = false
        loadFraction = null
        settings = Settings()
        watchedMode = WatchedMode.UNWATCHED
        demoEntries = emptyMap()
        error = null
        deleteError = null
        signOutError = null
        notice = null
        setUpChannels = emptyList()
        setUpEnabled = emptyMap()
        setUpShorts = ShortsFilter.ALL
        setUpShortsStart = ShortsFilter.ALL
        setUpStart = StartFrom.ALL
        prefetch?.cancel()
        prefetch = null
    }

    /**
     * Upload unsaved edits, then forget the account and its token on this
     * device. Google's grant stands: other devices stay signed in, and the
     * next sign-in here asks for no consent, only which account.
     */
    fun signOut() {
        if (demo) {
            return
        }
        signOutError = null
        viewModelScope.launch {
            try {
                store?.save()
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                // what wasn't sent stays on the device and goes up after the next sign-in
                Log.w(LOG_TAG, "upload before sign-out failed", caught)
            }
            try {
                app.auth.signOut()
                forgetAccount(SetUpStep.SIGN_IN)
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                Log.w(LOG_TAG, "sign-out failed", caught)
                signOutError = UiMessage(R.string.cant_reach_google)
            }
        }
    }

    /**
     * Load the channel step, unless the account's Drive folder shows it is
     * already set up: then first run ends here and the feed opens. Nothing is
     * fetched for a channel yet: [finishSetUpChannels] starts that.
     */
    private fun loadSetUpChannels() {
        val syncStore = store ?: return
        val currentLoader = loader ?: return
        val epoch = sessionEpoch
        setUpLoading = true
        setUpError = null
        viewModelScope.launch {
            try {
                val folder = withToken { token -> app.drive.listAppFiles(token) }
                if (epoch != sessionEpoch) {
                    return@launch
                }
                if (isAlreadySetUp(folder.map(DriveFile::name), deviceFileName(app.prefs.deviceId))) {
                    finishSetUp()
                    return@launch
                }
                val subscribed = withToken { token ->
                    coroutineScope {
                        val fetched = async { app.youtube.fetchSubscriptions(token) }
                        syncStore.load()
                        fetched.await()
                    }
                }
                if (epoch != sessionEpoch) {
                    return@launch
                }
                subscriptions = subscribed
                channels = syncStore.channels(subscribed, identities?.all().orEmpty())
                setUpChannels = channels.values.sortedWith(channelsByName)
                setUpEnabled = channels.mapValues { (_, filter) -> filter.enabled }
                setUpShortsStart = commonShortsFilter(setUpChannels)
                setUpShorts = setUpShortsStart
                prefetch?.cancel()
                prefetch = Prefetch(
                    viewModelScope,
                    fetchAll = { channel -> withToken { token -> currentLoader.fetchChannel(channel, token) } },
                    addShorts = { channel, have -> withToken { token -> currentLoader.addShortsMarks(channel, have, token) } },
                )
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                if (epoch == sessionEpoch) {
                    setUpError = describe(caught)
                }
            } finally {
                if (epoch == sessionEpoch) {
                    setUpLoading = false
                }
            }
        }
    }

    /** Flip one channel on the first-run channel step. */
    fun toggleSetUpChannel(channelId: String) {
        setUpEnabled = setUpEnabled + (channelId to !(setUpEnabled[channelId] ?: true))
    }

    /** Turn every channel on the first-run channel step on or off. */
    fun setAllSetUpChannels(enabled: Boolean) {
        setUpEnabled = setUpChannels.associate { channel -> channel.channelId to enabled }
    }

    /** Save [change]d filters of first run's channels as one edit. */
    private fun saveSetUpFilters(change: (ChannelFilter) -> ChannelFilter) {
        val edited = setUpChannels.mapNotNull { channel ->
            val current = channels[channel.channelId] ?: channel
            change(current).takeIf { updated -> updated != current }
        }
        if (edited.isNotEmpty()) {
            channels = channels + edited.associateBy(ChannelFilter::channelId)
            store?.setFilters(edited)
            recompute(fresh = true)
        }
    }

    /** Have the prefetch fetch exactly the channels left on, with the filters they now have. */
    private fun prefetchOn() {
        prefetch?.fetchOnly(setUpChannels.mapNotNull { channel -> channels[channel.channelId] }.filter(ChannelFilter::enabled))
    }

    /**
     * Save the channel step's switches as one edit, start fetching the
     * channels left on for the first feed load, and go on to the Shorts step.
     * Coming back and pressing Next again fetches only the newly-on ones.
     */
    fun finishSetUpChannels() {
        saveSetUpFilters { channel -> channel.copy(enabled = setUpEnabled[channel.channelId] ?: channel.enabled) }
        prefetchOn()
        goToStep(SetUpStep.SHORTS)
    }

    /**
     * Save the Shorts choice for every channel when it was changed, as one
     * edit, and go on to the starting point. A choice that filters on Shorts
     * adds the Shorts lists the prefetch left out.
     */
    fun finishSetUpShorts() {
        if (setUpShorts != setUpShortsStart) {
            val shorts = setUpShorts.takeUnless { choice -> choice == ShortsFilter.ALL }
            saveSetUpFilters { channel -> channel.copy(shortsFilter = shorts) }
            setUpShortsStart = setUpShorts
        }
        prefetchOn()
        goToStep(SetUpStep.START)
    }

    /**
     * Leave first run for the feed, loading it with what first run already
     * fetched. The starting point waits, with the channels that are on now,
     * for each of them to be loaded.
     */
    fun finishSetUp() {
        if (!demo) {
            (session as? Session.SignedIn)?.let { signedIn ->
                val channelsOn = channels.values.filter(ChannelFilter::enabled).map(ChannelFilter::channelId)
                app.prefs.keepPendingStart(signedIn.account.channelId, pendingStart(setUpStart, System.currentTimeMillis(), channelsOn))
                app.prefs.setSetUpDone(signedIn.account.channelId, true)
            }
        }
        backStack.clear()
        backStack.add(Screen.Feed)
        loadFeed()
    }

    /** The app came to the foreground. */
    fun onForeground() {
        if (backStack.firstOrNull() == Screen.Feed && lastLoadedAt > 0 &&
            System.currentTimeMillis() - lastLoadedAt > STALE_AFTER_MS
        ) {
            loadFeed()
        }
    }

    /** The app left the screen: upload edits not yet sent, while it still can. */
    fun onBackground() {
        val syncStore = store ?: return
        app.backgroundScope.launch {
            try {
                syncStore.saveUnsent()
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                // still unsent: it goes up after the next load
                Log.w(LOG_TAG, "upload on leaving failed", caught)
            }
        }
    }

    /** Load everything again, and the open page's channel when it is off, which a load leaves out. */
    fun refresh() {
        loadFeed()
        pageChannelId?.let(channels::get)?.takeUnless(ChannelFilter::enabled)?.let(::fetchChannelIntoFeed)
    }

    private fun changeSetting(changed: Settings, name: String, value: JsonElement, dropsStaying: Boolean = false) {
        settings = changed
        chipClock = System.currentTimeMillis()
        store?.setSetting(name, value)
        recompute(fresh = dropsStaying)
    }

    /** Turn auto-play on or off, here at once and on every device through Drive. */
    fun setAutoplay(autoplay: Boolean) {
        changeSetting(settings.copy(autoplay = autoplay), SettingName.AUTOPLAY, JsonPrimitive(autoplay))
    }

    /** Choose the feed's order. */
    fun setFeedSort(sort: FeedSort) {
        changeSetting(settings.copy(feedSort = sort), SettingName.FEED_SORT, JsonPrimitive(sort.wire))
    }

    /** Choose the channel list's order. */
    fun setChannelSort(sort: ChannelSort) {
        changeSetting(settings.copy(channelSort = sort), SettingName.CHANNEL_SORT, JsonPrimitive(sort.wire))
        reorderChannels()
    }

    /** Choose how far back the lists reach. */
    fun setTimeChip(chip: TimeChip) {
        changeSetting(settings.copy(timeChip = chip), SettingName.TIME_CHIP, JsonPrimitive(chip.wire), dropsStaying = true)
    }

    /** Select a topic chip by its category id, or deselect it. */
    fun toggleTopicChip(categoryId: String) {
        val selected = if (categoryId in settings.topicChips) settings.topicChips - categoryId else settings.topicChips + categoryId
        changeSetting(settings.copy(topicChips = selected), SettingName.TOPIC_CHIPS, JsonArray(selected.map(::JsonPrimitive)), dropsStaying = true)
    }

    /** Deselect every topic chip of the feed's row, which is all a channel's page can have selected. */
    fun clearTopicChips() {
        if (settings.topicChips.isNotEmpty()) {
            changeSetting(settings.copy(topicChips = emptyList()), SettingName.TOPIC_CHIPS, JsonArray(emptyList()), dropsStaying = true)
        }
    }

    /** Select one of the feed's group chips, or deselect it. */
    fun toggleGroupChip(name: String) {
        val selected = if (name in settings.groupChips) settings.groupChips - name else settings.groupChips + name
        changeSetting(settings.copy(groupChips = selected), SettingName.GROUP_CHIPS, JsonArray(selected.map(::JsonPrimitive)), dropsStaying = true)
    }

    /** Deselect every group and topic chip of the feed's row. */
    fun clearFeedChips() {
        if (settings.groupChips.isNotEmpty()) {
            changeSetting(settings.copy(groupChips = emptyList()), SettingName.GROUP_CHIPS, JsonArray(emptyList()), dropsStaying = true)
        }
        clearTopicChips()
    }

    /** Select one of the channels tab's group chips, or deselect it. */
    fun toggleChannelGroupChip(name: String) {
        val chosen = settings.channelGroupChips
        val selected = if (name in chosen) chosen - name else chosen + name
        changeSetting(settings.copy(channelGroupChips = selected), SettingName.CHANNEL_GROUP_CHIPS, JsonArray(selected.map(::JsonPrimitive)))
        reorderChannels()
    }

    /** Deselect every group and topic chip of the channels tab's row. */
    fun clearChannelChips() {
        if (settings.channelGroupChips.isNotEmpty()) {
            changeSetting(settings.copy(channelGroupChips = emptyList()), SettingName.CHANNEL_GROUP_CHIPS, JsonArray(emptyList()))
        }
        if (settings.channelTopicChips.isNotEmpty()) {
            changeSetting(settings.copy(channelTopicChips = emptyList()), SettingName.CHANNEL_TOPIC_CHIPS, JsonArray(emptyList()))
        }
        reorderChannels()
    }

    /** Every saved filter by channel id, the ones of channels no longer listed too. */
    private fun savedFilters(): Map<String, ChannelFilter> {
        val unlisted = store?.merged()?.channels.orEmpty()
            .filterKeys { channelId -> channelId !in channels }
            .mapValues { (channelId, entry) -> filterFromJson(channelId, channelId, "", entryFilter(entry)) }
        return unlisted + channels
    }

    private val groupSelections: GroupSelections
        get() = GroupSelections(settings.groupChips, settings.channelGroupChips)

    /**
     * Save a group edit's filters as one edit, and its settings; the lists
     * follow without a row moving. An edit that changes nothing leaves them
     * alone, and a card kept on screen since it was marked leaves only when
     * the feed's selected groups changed.
     */
    private fun applyGroupEdit(edit: GroupEdit) {
        if (edit.channels.isNotEmpty()) {
            holdChannelOrder()
            channels = channels + edit.channels.filterKeys { channelId -> channelId in channels }
            store?.setFilters(edit.channels.values)
        }
        for ((name, selected) in edit.settings) {
            settings = if (name == SettingName.GROUP_CHIPS) settings.copy(groupChips = selected) else settings.copy(channelGroupChips = selected)
            store?.setSetting(name, JsonArray(selected.map(::JsonPrimitive)))
        }
        if (edit.channels.isNotEmpty() || edit.settings.isNotEmpty()) {
            recompute(fresh = SettingName.GROUP_CHIPS in edit.settings)
        }
    }

    /**
     * The group editor's "Save": the listed channels in [group] become exactly
     * [members] and it takes [name]; a null [group] is a new one. Nothing is
     * saved without a name and a member.
     */
    fun saveGroup(group: String?, name: String, members: Collection<String>) {
        applyGroupEdit(saveGroup(savedFilters(), channels.keys, groupSelections, group, name, members))
    }

    /** Delete a group: its name leaves every channel and both rows' selections. */
    fun deleteGroup(group: String) {
        applyGroupEdit(deleteGroup(savedFilters(), groupSelections, group))
    }

    /** Choose how far back the channels tab reaches. */
    fun setChannelTimeChip(chip: TimeChip) {
        changeSetting(settings.copy(channelTimeChip = chip), SettingName.CHANNEL_TIME_CHIP, JsonPrimitive(chip.wire))
        reorderChannels()
    }

    /** Select one of the channels tab's topic chips by its category id, or deselect it. */
    fun toggleChannelTopicChip(categoryId: String) {
        val chosen = settings.channelTopicChips
        val selected = if (categoryId in chosen) chosen - categoryId else chosen + categoryId
        changeSetting(settings.copy(channelTopicChips = selected), SettingName.CHANNEL_TOPIC_CHIPS, JsonArray(selected.map(::JsonPrimitive)))
        reorderChannels()
    }

    /** List unwatched entries, watched ones, or both. */
    fun chooseWatchedMode(mode: WatchedMode) {
        watchedMode = mode
        recompute(fresh = true)
    }

    /** Whether an empty list is empty because of the chips, not because nothing is left to watch. */
    val emptiedBySelection: Boolean
        get() = emptiedBySelection(
            watchedMode,
            settings.timeChip,
            settings.topicChips,
            grouped = pageChannelId == null && selectedGroups(groups, settings.groupChips).isNotEmpty(),
        )

    /** Everything fetched for a channel, whatever its filter keeps. */
    fun channelFetched(channelId: String): List<FeedItem> = items.filter { item -> item.channelId == channelId }

    private fun loadFeed() {
        val currentLoader = loader ?: return
        if (loadInFlight) {
            return
        }
        val epoch = sessionEpoch
        val prefetched = prefetch
        prefetch = null
        loadInFlight = true
        loading = true
        loadFraction = loadProgress(finished = 0, total = null)
        error = null
        loadJob = viewModelScope.launch {
            try {
                val data = withToken { token -> loadWith(currentLoader, token, prefetched) }
                if (epoch == sessionEpoch) {
                    finishLoad(data)
                }
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                if (epoch == sessionEpoch) {
                    showFailure(caught)
                }
            } finally {
                // nothing the load still needs can be running
                prefetched?.cancel()
                if (epoch != sessionEpoch) {
                    return@launch
                }
                loading = false
                loadFraction = null
                loadInFlight = false
                lastLoadedAt = System.currentTimeMillis()
            }
        }
    }

    private suspend fun loadWith(currentLoader: FeedLoader, token: String, prefetched: Prefetch?): FeedData = currentLoader.load(
        token,
        prefetched,
        onProgress = { finished, total -> loadFraction = loadProgress(finished, total) },
        onChannels = { subscribed, loaded ->
            subscriptions = subscribed
            if (feed.items.isEmpty()) {
                channels = loaded
            }
        },
    )

    /** Say why a load failed: the daily limit as a notice, anything else as the error. */
    private fun showFailure(caught: Exception) {
        if (caught is DailyLimitException) {
            notice = UiMessage(R.string.daily_limit)
        } else if (caught !is ProfileDeletedException) {
            // a profile deleted elsewhere restarts first run, which says all there is to say
            error = describe(caught)
        }
    }

    /** Whether [filter] needs something not fetched for its channel: its mode's entries, or the Shorts list. */
    private fun isMissing(filter: ChannelFilter): Boolean =
        filter.fetchKey !in fetched || (needsShorts(filter) && filter.channelId !in shortsListed)

    /** The uploads held for a channel, as fetched; null when there are none. */
    private fun heldUploads(channelId: String): ChannelItems? =
        if ((channelId to ContentMode.VIDEOS) in fetched) {
            ChannelItems(ContentMode.VIDEOS, channelId in shortsListed, items.filter { item -> item.channelId == channelId && item is Video })
        } else {
            null
        }

    private fun markShortsListed(channelId: String, fresh: ChannelItems) {
        if (fresh.mode == ContentMode.VIDEOS) {
            shortsListed = if (fresh.shorts) shortsListed + channelId else shortsListed - channelId
        }
    }

    /** Put one channel's freshly fetched entries in place of what was held for it in their mode. */
    private fun mergeItems(channelId: String, fresh: ChannelItems) {
        val key = channelId to fresh.mode
        holdChannelOrder()
        items = items.filter { item -> (item.channelId to item.contentMode) != key } + fresh.items
        fetched = fetched + key
        markShortsListed(channelId, fresh)
        markBeforeStart(setOf(channelId), fresh.items)
        applyWatched(fresh.items)
        recompute()
    }

    private fun entryOf(id: String): JsonObject? = if (demo) demoEntries[id] else store?.watchedEntry(id)

    /** Read what is saved for [id] into [watchedIds] and [fractions]; says whether it is watched. */
    private fun readEntry(id: String, lengthSeconds: Double, watchedIds: MutableSet<String>, fractions: MutableMap<String, Double>): Boolean {
        val entry = entryOf(id)
        val isWatched = isWatchedEntry(entry, lengthSeconds)
        val fraction = progressFraction(entry, lengthSeconds)
        if (isWatched) watchedIds.add(id) else watchedIds.remove(id)
        if (fraction == null) fractions.remove(id) else fractions[id] = fraction
        return isWatched
    }

    private fun applyWatched(batch: List<FeedItem>) {
        val watchedIds = watched.toMutableSet()
        val fractions = bars.toMutableMap()
        for (item in batch) {
            readEntry(item.id, item.lengthSeconds, watchedIds, fractions)
        }
        watched = watchedIds
        bars = fractions
    }

    /** Show an entry as just saved; one that changed sides stays on screen. */
    private fun entryChanged(id: String, lengthSeconds: Double) {
        val wasWatched = id in watched
        val watchedIds = watched.toMutableSet()
        val fractions = bars.toMutableMap()
        val isWatched = readEntry(id, lengthSeconds, watchedIds, fractions)
        bars = fractions
        if (isWatched != wasWatched) {
            holdChannelOrder()
            watched = watchedIds
            staying = staying + id
            recompute()
        }
    }

    /**
     * After first run, mark what the channels just [fetched] in full hold
     * among [fresh] from before its starting point watched, as one save. A
     * channel that was on then and isn't among them keeps waiting for a later load.
     */
    private fun markBeforeStart(fetched: Collection<String>, fresh: List<FeedItem>) {
        val accountId = (session as? Session.SignedIn)?.account?.channelId
        val pending = accountId?.let(app.prefs::pendingStart)
        if (accountId != null && pending != null) {
            val applied = applyStart(pending, fetched, fresh)
            if (applied.pending != pending) {
                app.prefs.keepPendingStart(accountId, applied.pending)
            }
            store?.setWatched(applied.marks.filter { id -> entryOf(id)?.let(::entryWatched) != true }, true)
        }
    }

    private fun finishLoad(data: FeedData) {
        subscriptions = data.subscriptions
        // the store also holds filter edits made while the load ran
        channels = store?.channels(data.subscriptions, identities?.all().orEmpty()) ?: data.channels
        val loaded = data.fetched.mapTo(HashSet()) { (channelId, fresh) -> channelId to fresh.mode }
        // a failed channel keeps what it had; a loaded one keeps nothing of its other kind
        val kept = keptAfterLoad(fetched, loaded, channels.values.mapTo(HashSet(), ChannelFilter::fetchKey))
        items = items.filter { item -> (item.channelId to item.contentMode) in kept } + data.items
        fetched = kept + loaded
        shortsListed = shortsListed.intersect(channels.keys)
        data.fetched.forEach { (channelId, fresh) -> markShortsListed(channelId, fresh) }
        settings = store?.settings() ?: settings
        shuffleSeed = newShuffleSeed()
        chipClock = System.currentTimeMillis()
        markBeforeStart(data.fetched.keys, data.items)
        store?.noteLoaded(data.items.map(FeedItem::id))
        applyWatched(data.items)
        notice = when {
            data.dailyLimit -> UiMessage(R.string.daily_limit)
            data.failed.isNotEmpty() -> UiMessage(R.string.partial_results)
            else -> null
        }
        recompute(fresh = true)
        loadShown = true
        reorderChannels()
        // turned on, or given a filter that needs more, while the load ran after it had read the filters
        channels.values
            .filter { channel -> channel.enabled && isMissing(channel) && channel.channelId !in data.failed }
            .forEach(::fetchChannelIntoFeed)
    }

    /**
     * Rebuild [feed] and [channelFeed] from the items, filters, watched marks
     * and chips, in the chosen order. An entry that became watched or
     * unwatched since the last [fresh] rebuild stays in both, so nothing moves;
     * a full load, a filter or group edit and a change of the watched, time,
     * topic or group chips rebuild afresh. The channel page shows its channel whether or not
     * it is on. A card that is playing and left the list on screen gives the
     * player to the corner.
     */
    private fun recompute(fresh: Boolean = false) {
        if (fresh) {
            staying = emptySet()
        }
        val compiled = channels.mapValues { (_, filter) -> compileFilter(filter) }
        fun passes(item: FeedItem, channel: ChannelFilter): Boolean =
            (channel.contentMode ?: ContentMode.VIDEOS) == item.contentMode && passesFilter(item, compiled.getValue(channel.channelId))

        fun shown(passing: List<FeedItem>, grouped: Set<String>? = null): ShownList {
            val beforeChips = modeFiltered(passing.distinctBy(FeedItem::id), watchedMode, watched, staying)
            val inGroups = if (grouped == null) beforeChips else beforeChips.filter { item -> item.channelId in grouped }
            return ShownList(
                items = sortFeed(chipFiltered(inGroups, settings.timeChip, settings.topicChips, chipClock), settings.feedSort, shuffleSeed),
                topics = chipRow(beforeChips, settings.topicChips),
            )
        }
        feed = shown(
            items.filter { item -> channels[item.channelId]?.let { channel -> channel.enabled && passes(item, channel) } == true },
            groupKeptChannels(channels.values, settings.groupChips),
        )
        val pageChannel = pageChannelId?.let(channels::get)
        channelFeed = if (pageChannel == null) {
            ShownList()
        } else {
            shown(items.filter { item -> item.channelId == pageChannel.channelId && passes(item, pageChannel) })
        }
        pageChanged()
    }

    /** The cards of the page on screen: the feed's, the open channel page's, or none on any other screen. */
    private val cardsShowing: List<FeedItem>
        get() = when (backStack.lastOrNull()) {
            Screen.Feed -> feed.items
            is Screen.ChannelPage -> channelFeed.items
            else -> emptyList()
        }

    /**
     * Edit a channel's filter: it re-filters what is already fetched at once,
     * dropping the cards kept since they changed sides, and syncs through
     * Drive. A channel that is on is fetched only when its filter now needs
     * something not fetched (its mode's entries, or just its Shorts list); so
     * is the open page's channel, on or off.
     */
    fun updateFilter(filter: ChannelFilter) {
        if (filter == channels[filter.channelId]) {
            return
        }
        holdChannelOrder()
        channels = channels + (filter.channelId to filter)
        store?.setFilter(filter)
        recompute(fresh = true)
        // a running load fetches what is missing when it finishes
        val wanted = filter.enabled && !loadInFlight
        if (isMissing(filter) && (wanted || filter.channelId == pageChannelId)) {
            fetchChannelIntoFeed(filter)
        }
    }

    private fun fetchChannelIntoFeed(filter: ChannelFilter) {
        val currentLoader = loader ?: return
        val key = filter.fetchKey
        if (key in fetching) {
            return
        }
        fetching = fetching + key
        val round = fetchRound
        viewModelScope.launch {
            try {
                fetchPermits.withPermit {
                    // the daily limit refused a request since: this one would be refused too
                    if (round == fetchRound) {
                        val have = heldUploads(filter.channelId)
                        mergeItems(filter.channelId, withToken { token -> currentLoader.complete(filter, have, token) })
                    }
                }
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                if (caught is DailyLimitException) {
                    fetchRound += 1
                }
                showFailure(caught)
            } finally {
                fetching = fetching - key
            }
        }
    }

    // every change of what plays or where goes through here, so what belongs to the place left goes with it
    private fun place(next: Playing?) {
        val before = playing
        if (next?.place != before?.place || next?.item?.id != before?.item?.id) {
            playerFramed = false
            settling = false
            cardRequest = null
        }
        if (next?.place != PlayerPlace.CARD || next.item.id != playerSlot?.id) {
            playerSlot = null
        }
        if (next?.place != PlayerPlace.CARD) {
            playerView = null
        }
        playing = next
    }

    // the page or its list changed: a card that is gone or on another page gives the player to the corner
    private fun pageChanged() {
        playing?.let { current -> place(afterPageChange(current, pageChannelId, cardsShowing)) }
    }

    // ask the page's list to bring the card that was given the player into view
    private fun settleInCard(id: String) {
        settling = true
        cardRequests += 1
        cardRequest = CardRequest(id, pageChannelId, cardRequests)
    }

    private fun Rect.inDp(): ScreenBox {
        val density = getApplication<Application>().resources.displayMetrics.density
        // whole sixteenths, so a box laid out 200dp high never reads as a hair under it
        fun dp(pixels: Float): Float = Math.round(pixels / density * 16) / 16f
        return ScreenBox(dp(left), dp(top), dp(width), dp(height))
    }

    // the playing card's thumbnail or its list moved: less than half of it showing gives the player to the corner
    private fun cardMeasured() {
        val current = playing
        val slot = playerSlot
        val view = playerView
        if (current != null && slot != null && view != null && !settling && !fullscreenHold) {
            place(afterCardMeasured(current, slot.id, cardHolds(slot.box.inDp(), view.inDp())))
        }
    }

    /**
     * Play a card of the page showing in place of its thumbnail, whatever was
     * playing and wherever; the page's list and watched chip are kept as
     * they are now for what plays next ([playbackEnded]).
     */
    fun play(item: FeedItem) {
        val next = played(item, pageChannelId, cardsShowing, watchedMode)
        place(next)
        if (next.place == PlayerPlace.CARD) {
            // a pressed card that is mostly off the screen is brought into view rather than losing the player to the corner
            settleInCard(item.id)
        }
    }

    /**
     * The video fills the screen ([fullscreen]) or has stopped doing so. A
     * card's player stays its card's meanwhile and for a moment after,
     * whatever the turned and resized window makes of the card's box.
     */
    fun playerFullscreen(fullscreen: Boolean) {
        fullscreenRelease?.cancel()
        if (fullscreen) {
            fullscreenHold = true
        } else if (fullscreenHold) {
            fullscreenRelease = viewModelScope.launch {
                delay(AFTER_FULLSCREEN_MS)
                fullscreenHold = false
                cardMeasured()
            }
        }
    }

    /** Whether the card of the entry [id] in the list of [page] holds the player. */
    fun playsInCard(id: String, page: String?): Boolean {
        val current = playing
        return current != null && current.place == PlayerPlace.CARD && current.item.id == id && current.page == page
    }

    /** The playing card's thumbnail is at [box], in the window's pixels. */
    fun playerSlotMoved(id: String, box: Rect) {
        if (playing?.place == PlayerPlace.CARD && playing?.item?.id == id && playerSlot != PlayerSlot(id, box)) {
            playerSlot = PlayerSlot(id, box)
            cardMeasured()
        }
    }

    /** The playing card left its list's rows: the player goes to the corner. */
    fun playerSlotGone(id: String) {
        if (playerSlot?.id == id) {
            playerSlot = null
        }
        val current = playing
        if (current != null && !settling && !fullscreenHold) {
            place(afterCardMeasured(current, id, holds = false))
        }
    }

    /** The list of [page] is at [view], in the window's pixels. */
    fun playerViewMoved(page: String?, view: Rect) {
        val current = playing
        if (current != null && current.place == PlayerPlace.CARD && current.page == page && playerView != view) {
            playerView = view
            cardMeasured()
        }
    }

    /**
     * The list of a page finished bringing a requested card into view. A card
     * that still can't hold the player gives it to the corner.
     */
    fun cardShown(request: CardRequest) {
        if (cardRequest == request) {
            cardRequest = null
            settling = false
            if (playerSlot?.id == request.id) {
                cardMeasured()
            } else {
                playing?.let { current -> place(afterCardMeasured(current, request.id, holds = false)) }
            }
        }
    }

    /** Send the player to the corner. */
    fun minimizePlayer() {
        playing?.let { current -> place(minimized(current)) }
    }

    /**
     * Bring the minimized player back into its card: the page the video was
     * started on is shown again and its list brings the card into view. The
     * player stays minimized when that page no longer lists the card.
     */
    fun expandPlayer() {
        val current = playing
        if (current != null && current.place == PlayerPlace.MINIMIZED) {
            val page = current.page
            if (page != null) {
                showChannel(page)
            } else if (backStack.toList() != listOf<Screen>(Screen.Feed)) {
                channelFeed = ShownList()
                backStack.clear()
                backStack.add(Screen.Feed)
            }
            val showsPage = backStack.lastOrNull() == (if (page == null) Screen.Feed else Screen.ChannelPage(page))
            val after = expanded(current, pageChannelId, if (showsPage) cardsShowing else emptyList())
            place(after)
            if (after.place == PlayerPlace.CARD) {
                settleInCard(after.item.id)
            }
        }
    }

    /** Stop playing and remove the player; the position it had reached is saved as it leaves. */
    fun closePlayer() {
        place(null)
    }

    /** Show the frame around the minimized player's video, or hide it; a video in its card has none. */
    fun framePlayer(framed: Boolean) {
        playerFramed = framed && playing?.place == PlayerPlace.MINIMIZED
    }

    /** A sheet or dialog opened over the app ([covered]) or closed. */
    fun coverPlayer(covered: Boolean) {
        playerCovers = maxOf(0, playerCovers + if (covered) 1 else -1)
    }

    /**
     * The playing entry ended. With "Auto-play" on, the next unwatched entry
     * of the list it was started from plays where the player is: in its
     * card, brought into view, or in the corner when the player is there or
     * the page showing has no such card. With nothing next a card's player
     * closes and the minimized one stays, stopped, until it is closed or expanded.
     */
    fun playbackEnded(endedId: String) {
        val current = playing
        if (current != null && current.item.id == endedId) {
            val next = afterEnd(current, watched, settings.autoplay, pageChannelId, cardsShowing)
            place(next)
            if (next != null && next.place == PlayerPlace.CARD && next.item.id != endedId) {
                settleInCard(next.item.id)
            }
        }
    }

    /** Where a video starts when opened, in seconds. */
    fun resumeAt(id: String): Double = resumePosition(entryOf(id), itemsById[id]?.lengthSeconds ?: 0.0)

    override fun findItem(id: String): FeedItem? = itemsById[id]

    /**
     * Save how far a video has been played. It is always kept on this device;
     * [upload] says whether Drive gets it after the usual pause, at once, or
     * only with the next upload.
     */
    override fun recordProgress(id: String, position: Double, playerDuration: Double, ended: Boolean, upload: ProgressUpload) {
        val seconds = maxOf(0.0, position).toLong()
        if (demo) {
            demoEntries = demoEntries + (id to playedEntry(demoEntries[id], System.currentTimeMillis(), seconds, ended))
        }
        store?.setProgress(id, seconds, ended, upload != ProgressUpload.LATER)
        if (upload == ProgressUpload.NOW) {
            onBackground()
        }
        entryChanged(id, itemsById[id]?.lengthSeconds?.takeIf { length -> length > 0 } ?: playerDuration)
    }

    /** Mark a video or playlist watched, or unmark it, which forgets a video's position. */
    override fun setWatched(id: String, watched: Boolean) {
        if (demo) {
            demoEntries = demoEntries + (id to markedEntry(demoEntries[id], System.currentTimeMillis(), watched))
        }
        store?.setWatched(id, watched)
        entryChanged(id, itemsById[id]?.lengthSeconds ?: 0.0)
    }

    /** Dismiss the partial-load or daily-limit banner. */
    fun dismissNotice() {
        notice = null
    }
}
