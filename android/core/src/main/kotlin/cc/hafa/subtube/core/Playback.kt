package cc.hafa.subtube.core

/** When a saved position goes to Drive. */
enum class ProgressUpload {
    /** Only with the next upload, whatever starts it. */
    LATER,

    /** After the usual pause. */
    SOON,

    /** At once. */
    NOW,
}

/** The player states playback reacts to. */
enum class PlayerState { PLAYING, PAUSED, ENDED, OTHER }

/** What a playing entry reads from and saves to the feed. */
interface PlaybackFeed {
    /**
     * Save how far a video has been played: [position] of [playerDuration]
     * seconds, [ended] when the player reported the end. For a playlist,
     * [place] is where in it the player is.
     */
    fun recordProgress(id: String, position: Double, playerDuration: Double, ended: Boolean, upload: ProgressUpload, place: PlaylistPlace? = null)

    /** Mark a video or playlist watched. */
    fun setWatched(id: String, watched: Boolean)

    /** A loaded entry by id. */
    fun findItem(id: String): FeedItem?

    /** Where a playlist starts when opened, among the [videos] its player loaded. */
    fun playlistStart(id: String, videos: List<String>): PlaylistStart
}

/**
 * One entry in one player, wherever the player is drawn: saves the position
 * of a video, or of a playlist's video, as it plays and marks it watched at
 * the player's reported end.
 *
 * The player reports through [positionChanged] and [stateChanged]. Nothing is
 * saved for a live broadcast; a playlist is marked when its last video ends. [onEnded] runs once the entry is over, also when the player
 * reports that it can't play the video ([failed]).
 */
class Playback(
    private val id: String,
    private val isPlaylist: Boolean,
    private val feed: PlaybackFeed,
    private val onEnded: () -> Unit,
) {
    private var position = 0.0
    private var duration = 0.0

    // the playlist's video that is playing, and its place among those the player loaded
    private var video: String? = null
    private var playlistIndex = 0
    private var playlistCount = 0
    private var playing = false

    // from the first time the video plays until it ends: while set, its position is worth saving
    private var tracking = false

    // the whole second last saved, and whether an upload was asked for with it; null when nothing saved stands
    private var savedSecond: Long? = null
    private var savedUpload = ProgressUpload.LATER

    /** Whether the position is saved: not for a live broadcast. */
    private fun savesPosition(): Boolean = (feed.findItem(id) as? Video)?.liveStatus != LiveStatus.LIVE

    /** Where the playlist starts, among the [videos] its player loaded. */
    fun playlistStart(videos: List<String>): PlaylistStart = feed.playlistStart(id, videos)

    /**
     * The player is [position] seconds into a video [duration] seconds long;
     * for a playlist, [video] is the id of its playing video, at
     * [playlistIndex] of the [playlistCount] the player loaded.
     */
    fun positionChanged(position: Double, duration: Double, video: String? = null, playlistIndex: Int = 0, playlistCount: Int = 0) {
        if (video != this.video) {
            // the same second of another video is not saved yet
            savedSecond = null
        }
        this.position = position
        this.duration = duration
        this.video = video
        this.playlistIndex = playlistIndex
        this.playlistCount = playlistCount
    }

    /** Save the position of a video that has played, unless that second is saved already. */
    fun save(upload: ProgressUpload) {
        val second = position.toLong()
        // saving the same second again would only make it newer than what another device saved since
        val alreadySaved = second == savedSecond && (upload == ProgressUpload.LATER || savedUpload != ProgressUpload.LATER)
        val playing = video
        if (tracking && savesPosition() && !alreadySaved && (!isPlaylist || playing != null)) {
            if (isPlaylist) {
                // a playlist has no length, so its video's is not passed as one
                val progress = playlistProgress(playlistIndex, playlistCount, position, duration)
                feed.recordProgress(id, position, 0.0, ended = false, upload, PlaylistPlace(checkNotNull(playing), progress))
            } else {
                feed.recordProgress(id, position, duration, ended = false, upload)
            }
            savedSecond = second
            savedUpload = upload
        }
    }

    /** The regular save while playing, kept on this device only. */
    fun tick() {
        if (playing) {
            save(ProgressUpload.LATER)
        }
    }

    private fun finish() {
        tracking = false
        savedSecond = null
        if (!isPlaylist && savesPosition()) {
            feed.recordProgress(id, position, duration, ended = true, ProgressUpload.SOON)
        } else {
            feed.setWatched(id, true)
        }
        onEnded()
    }

    /** The player can't play the video: it is over, without being marked. A playlist's player skips such a video itself. */
    fun failed() {
        if (!isPlaylist) {
            tracking = false
            onEnded()
        }
    }

    /**
     * The player changed state, [position] seconds into a video [duration]
     * seconds long; for a playlist, [video] is the id of its playing video,
     * at [playlistIndex] of the [playlistCount] the player loaded, the last
     * of which ends the playlist.
     */
    fun stateChanged(state: PlayerState, position: Double, duration: Double, video: String? = null, playlistIndex: Int = 0, playlistCount: Int = 0) {
        positionChanged(position, duration, video, playlistIndex, playlistCount)
        val lastOfPlaylist = playlistCount > 0 && playlistIndex == playlistCount - 1
        val wasPlaying = playing
        playing = state == PlayerState.PLAYING
        tracking = tracking || playing
        if (state == PlayerState.ENDED && (!isPlaylist || lastOfPlaylist)) {
            finish()
        } else if (state == PlayerState.PAUSED && wasPlaying) {
            save(ProgressUpload.SOON)
        }
    }
}
