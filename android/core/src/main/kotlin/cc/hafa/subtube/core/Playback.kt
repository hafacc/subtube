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
    /** Save how far a video has been played: [position] of [playerDuration] seconds, [ended] when the player reported the end. */
    fun recordProgress(id: String, position: Double, playerDuration: Double, ended: Boolean, upload: ProgressUpload)

    /** Mark a video or playlist watched. */
    fun setWatched(id: String, watched: Boolean)

    /** A loaded entry by id. */
    fun findItem(id: String): FeedItem?
}

/**
 * One entry in one player, wherever the player is drawn: saves a video's
 * position as it plays and marks it watched at the player's reported end.
 *
 * The player reports through [positionChanged] and [stateChanged]. Nothing is
 * saved for a playlist or a live broadcast; a playlist is marked when its last
 * video ends. [onEnded] runs once the entry is over.
 */
class Playback(
    private val id: String,
    private val isPlaylist: Boolean,
    private val feed: PlaybackFeed,
    private val onEnded: () -> Unit,
) {
    private var position = 0.0
    private var duration = 0.0
    private var playing = false

    // from the first time the video plays until it ends: while set, its position is worth saving
    private var tracking = false

    /** Whether the position is saved: not for a playlist or a live broadcast. */
    private fun savesPosition(): Boolean = !isPlaylist && (feed.findItem(id) as? Video)?.liveStatus != LiveStatus.LIVE

    /** The player is [position] seconds into a video [duration] seconds long. */
    fun positionChanged(position: Double, duration: Double) {
        this.position = position
        this.duration = duration
    }

    /** Save the position of a video that has played. */
    fun save(upload: ProgressUpload) {
        if (tracking && savesPosition()) {
            feed.recordProgress(id, position, duration, ended = false, upload)
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
        if (savesPosition()) {
            feed.recordProgress(id, position, duration, ended = true, ProgressUpload.SOON)
        } else {
            feed.setWatched(id, true)
        }
        onEnded()
    }

    /**
     * The player changed state, [position] seconds into a video [duration]
     * seconds long; [lastOfPlaylist] when a playlist is on its last video.
     */
    fun stateChanged(state: PlayerState, position: Double, duration: Double, lastOfPlaylist: Boolean = false) {
        positionChanged(position, duration)
        val wasPlaying = playing
        playing = state == PlayerState.PLAYING
        tracking = tracking || playing
        if (isPlaylist) {
            if (state == PlayerState.ENDED && lastOfPlaylist) {
                finish()
            }
        } else if (state == PlayerState.ENDED) {
            finish()
        } else if (state == PlayerState.PAUSED && wasPlaying) {
            save(ProgressUpload.SOON)
        }
    }
}
