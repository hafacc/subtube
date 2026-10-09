package cc.hafa.subtube.core

import java.io.IOException
import java.util.logging.Level
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Where a [SyncStore] keeps this device's edits until they're uploaded. */
interface SyncStorage {
    /** The value saved under [key], or null. */
    fun read(key: String): String?

    /** Save [value] under [key], replacing what was there. */
    fun write(key: String, value: String)

    /** Forget what is saved under [key]. */
    fun remove(key: String)
}

/** The profile was deleted from another device; this device's copy of it has been dropped. */
class ProfileDeletedException : Exception("The profile was deleted on another device")

/** A burst of edits goes up as one upload. */
const val SAVE_DELAY_MS: Long = 2000

/** Another device's file as last downloaded. */
private data class RemoteDeviceFile(val deviceId: String, val modifiedTime: String, val file: DeviceFile?)

/**
 * The channel filters, watched marks and settings, synced through the Drive app folder.
 * Each device writes only its own file and reads everyone's, so two devices
 * never write the same file. Edits apply in memory at once, are written to
 * [storage] off the caller's thread, one at a time and in the order made (so
 * a killed app loses at most the write in hand), and go up after
 * [saveDelayMs] of quiet; an upload that fails is tried again after the next
 * [load], and [saveUnsent] tries at once. A token Google refuses is replaced
 * once and the call made again. Once the profile is deleted, here or from
 * another device, the store keeps nothing and uploads nothing.
 */
class SyncStore(
    accountId: String,
    private val deviceId: String,
    private val getToken: suspend () -> String,
    private val drive: DriveClient,
    private val storage: SyncStorage,
    /** Runs the delayed uploads; it should outlive any one screen. */
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
    private val saveDelayMs: Long = SAVE_DELAY_MS,
    /** Gives a token in place of one Google refused. */
    private val replaceToken: suspend (refused: String) -> String = { getToken() },
) {
    private val ownName = deviceFileName(deviceId)
    private val localKey = "subtube.sync.$accountId"

    // present once this device's file has been uploaded
    private val uploadedKey = "subtube.uploaded.$accountId"
    private val lock = Any()
    private val saveMutex = Mutex()

    // storage is written one call at a time, in the order asked, never on the caller's thread
    private val writes = Dispatchers.IO.limitedParallelism(1)

    // guarded by lock: whether this device's file has been uploaded, as storage also holds
    private var uploaded = storage.read(uploadedKey) != null

    // guarded by lock
    private var own: DeviceFile = parseDeviceFile(storage.read(localKey)) ?: DeviceFile()
    private var ownFileId: String? = null

    // Drive's time for this device's file as last downloaded or uploaded; a listing with the same needs no download
    private var ownModifiedTime: String? = null

    // whether ownFileId is known; saving before then would create a second file
    private var listed = false

    // a newer client's own file this version can't read; never overwritten
    private var ownUnreadable = false
    private val others = HashMap<String, RemoteDeviceFile>()
    private var saveTimer: Job? = null

    // the profile was deleted; nothing more is kept or uploaded
    private var ended = false

    // this device's file holds edits its Drive copy doesn't
    private var unsent = false

    @Volatile
    private var merged: DeviceFile = own

    private val syncedAt = MutableStateFlow<Long?>(null)

    /** When Drive last answered a load or a save (ms since the epoch); null until it has. */
    val lastSynced: StateFlow<Long?> = syncedAt.asStateFlow()

    private fun remerge() {
        val files = HashMap<String, DeviceFile>()
        for (remote in others.values) {
            remote.file?.let { file -> files[remote.deviceId] = file }
        }
        files[deviceId] = own
        merged = mergeDeviceFiles(files)
    }

    private val deleted = MutableStateFlow(false)

    /** Whether a load found the profile deleted from another device. */
    val deletedElsewhere: StateFlow<Boolean> = deleted.asStateFlow()

    // call with lock held, so storage is written in the order the calls were made
    private fun store(write: () -> Unit) {
        scope.launch(writes) {
            try {
                write()
            } catch (caught: IOException) {
                logger.log(Level.WARNING, "this device's copy couldn't be written", caught)
            }
        }
    }

    // call with lock held
    private fun writeLocal() {
        val file = own
        store { storage.write(localKey, encodeDeviceFile(file)) }
    }

    // call with lock held
    private fun markUploaded() {
        if (!uploaded) {
            uploaded = true
            store { storage.write(uploadedKey, "true") }
        }
    }

    /** Wait until every edit made so far is in storage. */
    internal suspend fun awaitWrites() {
        withContext(writes) { }
    }

    private fun dropLocal() {
        synchronized(lock) {
            ended = true
            saveTimer?.cancel()
            own = DeviceFile()
            ownFileId = null
            ownModifiedTime = null
            others.clear()
            listed = false
            uploaded = false
            remerge()
            store {
                storage.remove(localKey)
                storage.remove(uploadedKey)
            }
        }
    }

    /** Run [block] with a token; when Google refuses it, once more with the one that replaces it. */
    private suspend inline fun <Result> withFreshToken(block: (String) -> Result): Result {
        val token = getToken()
        return try {
            block(token)
        } catch (_: TokenExpiredException) {
            block(replaceToken(token))
        }
    }

    /**
     * A listing lacked this device's uploaded file: look again before
     * believing it, since a listing can trail a file just made. Gives the
     * folder as it is now when the file is there after all, null when it is gone.
     */
    private suspend fun folderUnlessDeleted(token: String): List<DriveFile>? {
        val fileId = synchronized(lock) { ownFileId }
        return if (fileId != null && !drive.exists(fileId, token)) {
            null
        } else {
            drive.listAppFiles(token).takeIf { folder -> fileId != null || folder.any { entry -> entry.name == ownName } }
        }
    }

    /**
     * Read every device's file, downloading only the ones that changed since
     * the last load, this device's own among them. [listing] is the app
     * folder when the caller has just listed it, so it isn't listed again.
     *
     * @throws ProfileDeletedException when this device's uploaded file is gone from the folder,
     * which a second look has to confirm.
     */
    suspend fun load(listing: List<DriveFile>? = null) {
        // reading and merging the files is kept off a caller on the main thread
        withContext(Dispatchers.Default) {
            withFreshToken { token -> loadWith(token, listing) }
        }
    }

    private suspend fun loadWith(token: String, given: List<DriveFile>?) {
        // as it was before the listing was asked for: a file first uploaded meanwhile isn't in it
        val uploadedBefore = synchronized(lock) { uploaded }
        val firstListing = given ?: drive.listAppFiles(token)
        val folder = if (wasDeletedElsewhere(uploadedBefore, firstListing.map(DriveFile::name), ownName)) {
            folderUnlessDeleted(token) ?: run {
                dropLocal()
                deleted.value = true
                throw ProfileDeletedException()
            }
        } else {
            firstListing
        }
        if (folder.any { entry -> entry.name == ownName }) {
            synchronized(lock) { markUploaded() }
        }
        val listing = folder.filter { entry -> deviceIdOf(entry.name) != null }
        val known = synchronized(lock) {
            others.mapValues { (_, remote) -> remote.modifiedTime } + listOfNotNull(ownFileId?.let { fileId -> ownModifiedTime?.let { time -> fileId to time } })
        }
        val downloads = coroutineScope {
            listing.filter { entry -> known[entry.id] != entry.modifiedTime }
                .map { entry -> async { entry to parseDeviceFile(drive.download(entry.id, token)) } }
                .awaitAll()
        }
        synchronized(lock) {
            for ((entry, file) in downloads) {
                if (entry.name == ownName) {
                    ownFileId = entry.id
                    ownModifiedTime = entry.modifiedTime
                    ownUnreadable = file == null
                    // the stored copy may hold edits the last upload never carried
                    if (file != null) {
                        val both = mergeDeviceFiles(mapOf("drive" to file, "local" to own))
                        own = both.copy(
                            // a file that never held settings is written back without them
                            settings = both.settings.takeIf { file.settings != null || own.settings != null },
                            extra = file.extra + own.extra,
                        )
                        unsent = unsent || own != file
                    }
                } else {
                    others[entry.id] = RemoteDeviceFile(deviceIdOf(entry.name).orEmpty(), entry.modifiedTime, file)
                }
            }
            val live = listing.filter { entry -> entry.name != ownName }.map(DriveFile::id).toSet()
            others.keys.retainAll(live)
            listed = true
            if (listing.none { entry -> entry.name == ownName } && own != DeviceFile()) {
                unsent = true
            }
            remerge()
            if (unsent && !ownUnreadable) {
                scheduleSave()
            }
        }
        syncedAt.value = clock()
    }

    /** The merged view of every device's file. */
    fun merged(): DeviceFile = merged

    /** The channels the feed reads, given the account's YouTube subscriptions and the followed channels' names. */
    fun channels(subscriptions: List<Subscription>, followedIdentities: Map<String, ChannelIdentity> = emptyMap()): Map<String, ChannelFilter> =
        channelsFor(merged, subscriptions, followedIdentities)

    /** A video's or playlist's watched entry as last saved on any device; [isWatchedEntry] and its neighbours read it. */
    fun watchedEntry(id: String): JsonObject? = merged.watched[id]

    /** Save a channel's filter; fields this version doesn't know are written back as they were, and a pattern that is not built from phrases is dropped. */
    fun setFilter(filter: ChannelFilter) {
        setFilters(listOf(filter))
    }

    /** Save several channels' filters as one edit, so one upload. */
    fun setFilters(filters: Collection<ChannelFilter>) {
        if (filters.isEmpty()) {
            return
        }
        edit { file ->
            val at = JsonPrimitive(clock())
            val entries = filters.associate { filter ->
                filter.channelId to JsonObject(file.channels[filter.channelId].orEmpty() + mapOf("at" to at, "filter" to filterToJson(editedFilter(filter))))
            }
            file.copy(channels = file.channels + entries)
        }
    }

    /** Mark a video or playlist watched, or unmark it, which also forgets its position. */
    fun setWatched(id: String, watched: Boolean) {
        setWatched(listOf(id), watched)
    }

    /** Mark several videos or playlists watched or unwatched as one edit, so one upload. */
    fun setWatched(ids: Collection<String>, watched: Boolean) {
        if (ids.isEmpty()) {
            return
        }
        edit { file ->
            val at = clock()
            file.copy(watched = file.watched + ids.associateWith { id -> markedEntry(file.watched[id], at, watched) })
        }
    }

    /**
     * Save how far a video has been played, in whole seconds; [ended] when its
     * player reported the end. It is kept on this device at once and goes to
     * Drive with the next upload, which this starts only when [upload] is set.
     */
    fun setProgress(id: String, position: Long, ended: Boolean, upload: Boolean) {
        edit(upload) { file -> file.copy(watched = file.watched + (id to playedEntry(file.watched[id], clock(), position, ended))) }
    }

    /**
     * Note the videos and playlists a full load just returned: this device's
     * entries for them are kept another 30 days, and its entries past that
     * are dropped, here and in Drive. Nothing is uploaded when nothing changed.
     */
    fun noteLoaded(ids: Collection<String>) {
        val now = clock()
        synchronized(lock) {
            val kept = pruneDeviceFile(refreshSeen(own, ids.toSet(), now), now)
            if (!ended && kept != own) {
                own = kept
                unsent = true
                remerge()
                scheduleSave()
                writeLocal()
            }
        }
    }

    /** Every synced setting's entry (`{at, value}`) as last saved on any device, by name; [readSettings] gives them meaning. */
    fun settingEntries(): Map<String, JsonObject> = merged.settings.orEmpty()

    /** The synced settings the app acts on. */
    fun settings(): Settings = readSettings(settingEntries())

    /** Save a synced setting under [name] (see [SettingName]); fields its entry had that this version doesn't know are kept. */
    fun setSetting(name: String, value: JsonElement) {
        edit { file ->
            val entries = file.settings.orEmpty()
            val entry = JsonObject(entries[name].orEmpty() + mapOf("at" to JsonPrimitive(clock()), "value" to value))
            file.copy(settings = entries + (name to entry))
        }
    }

    private fun edit(upload: Boolean = true, change: (DeviceFile) -> DeviceFile) {
        synchronized(lock) {
            if (!ended) {
                own = change(own)
                unsent = true
                remerge()
                if (upload) {
                    scheduleSave()
                }
                writeLocal()
            }
        }
    }

    // call with lock held
    private fun scheduleSave() {
        saveTimer?.cancel()
        saveTimer = scope.launch {
            delay(saveDelayMs)
            // once the pause is over, a newer edit must not cancel the upload itself
            withContext(NonCancellable) {
                try {
                    saveUnsent()
                } catch (caught: Exception) {
                    // still unsent: tried again after the next load
                    logger.log(Level.WARNING, "upload failed", caught)
                }
            }
        }
    }

    /** Upload this device's file now if it holds edits its Drive copy doesn't; a failed upload is tried again after the next load. */
    suspend fun saveUnsent() {
        save(onlyUnsent = true)
    }

    /** Upload this device's file now; a save already running is waited for first. */
    suspend fun save() {
        save(onlyUnsent = false)
    }

    private suspend fun save(onlyUnsent: Boolean) {
        saveMutex.withLock {
            // asked again here: the save this one waited for may have sent everything
            val wanted = synchronized(lock) { !ended && (unsent || !onlyUnsent) }
            if (wanted) {
                if (!synchronized(lock) { listed }) {
                    load()
                }
                withFreshToken { token -> upload(token) }
            }
        }
    }

    // call with saveMutex held
    private suspend fun upload(token: String) {
        val (snapshot, fileId) = synchronized(lock) {
            own = pruneDeviceFile(own, clock())
            (own to ownFileId).takeUnless { ownUnreadable || ended }
        } ?: return
        val content = encodeDeviceFile(snapshot)
        val saved = if (fileId != null) drive.updateJson(fileId, content, token) else drive.createJson(ownName, content, token)
        synchronized(lock) {
            ownFileId = saved.id
            ownModifiedTime = saved.modifiedTime
            // an edit made while this upload ran is still unsent
            unsent = own != snapshot
            writeLocal()
            markUploaded()
        }
        syncedAt.value = clock()
    }

    /**
     * Delete the profile: every file in the Drive app folder, then everything
     * kept on this device. A failed Drive call throws and leaves this device's
     * copy as it was, to be uploaded again by the next save.
     */
    suspend fun deleteProfile() {
        synchronized(lock) { saveTimer?.cancel() }
        saveMutex.withLock {
            try {
                withFreshToken { token ->
                    for (file in drive.listAppFiles(token)) {
                        drive.delete(file.id, token)
                    }
                }
            } catch (caught: Exception) {
                // this device's file may be among those already deleted: the next save lists the folder again and makes a new one
                synchronized(lock) {
                    ownFileId = null
                    ownModifiedTime = null
                    listed = false
                    unsent = true
                    uploaded = false
                    store { storage.remove(uploadedKey) }
                }
                throw caught
            }
            dropLocal()
        }
    }
}
