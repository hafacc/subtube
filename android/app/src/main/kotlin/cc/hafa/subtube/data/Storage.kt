package cc.hafa.subtube.data

import android.content.Context
import android.util.AtomicFile
import androidx.core.content.edit
import cc.hafa.subtube.core.Account
import cc.hafa.subtube.core.PendingStart
import cc.hafa.subtube.core.decodePendingStart
import cc.hafa.subtube.core.encodePendingStart
import cc.hafa.subtube.core.isChannelId
import cc.hafa.subtube.core.SyncStorage
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID

/** Keeps a [cc.hafa.subtube.core.SyncStore]'s unuploaded edits in app-private files, one per key. */
class FileSyncStorage(context: Context) : SyncStorage {
    private val directory = File(context.filesDir, "sync").apply { mkdirs() }

    private fun file(key: String): AtomicFile = AtomicFile(File(directory, "$key.json"))

    override fun read(key: String): String? = try {
        file(key).readFully().decodeToString()
    } catch (_: FileNotFoundException) {
        null
    }

    override fun write(key: String, value: String) {
        val target = file(key)
        val stream = target.startWrite()
        try {
            stream.write(value.encodeToByteArray())
            target.finishWrite(stream)
        } catch (caught: Exception) {
            target.failWrite(stream)
            throw caught
        }
    }

    override fun remove(key: String) {
        file(key).delete()
    }

    /** Every key something is saved under. */
    fun keys(): List<String> = directory.list().orEmpty().filter { name -> name.endsWith(".json") }.map { name -> name.removeSuffix(".json") }
}

/** The app's colour theme. */
enum class ThemeMode {
    /** Light or dark as the system is. */
    SYSTEM,

    /** Always light. */
    LIGHT,

    /** Always dark. */
    DARK,
}

/** The signed-in account, this install's device id, and app settings. */
class AccountPrefs(context: Context) {
    private val prefs = context.getSharedPreferences("subtube", Context.MODE_PRIVATE)

    /** A random id naming this device's Drive file; kept for the life of the install. */
    val deviceId: String by lazy {
        prefs.getString(DEVICE_KEY, null) ?: UUID.randomUUID().toString().also { id ->
            prefs.edit { putString(DEVICE_KEY, id) }
        }
    }

    /** The account last signed in, or null when signed out; saving one drops what an earlier version kept of it. */
    var account: Account?
        get() {
            val id = prefs.getString(ACCOUNT_GOOGLE_ID_KEY, null) ?: return null
            return Account(
                id = id,
                name = prefs.getString(ACCOUNT_NAME_KEY, null).orEmpty(),
                photo = prefs.getString(ACCOUNT_PHOTO_KEY, null),
                email = prefs.getString(ACCOUNT_EMAIL_KEY, null),
            )
        }
        set(value) {
            prefs.edit {
                remove(OLD_ACCOUNT_ID_KEY).remove(OLD_ACCOUNT_TITLE_KEY).remove(OLD_ACCOUNT_THUMBNAIL_KEY).remove(OLD_ACCOUNT_HANDLE_KEY)
                if (value == null) {
                    remove(ACCOUNT_GOOGLE_ID_KEY).remove(ACCOUNT_NAME_KEY).remove(ACCOUNT_PHOTO_KEY).remove(ACCOUNT_EMAIL_KEY)
                } else {
                    putString(ACCOUNT_GOOGLE_ID_KEY, value.id)
                        .putString(ACCOUNT_NAME_KEY, value.name)
                        .putString(ACCOUNT_PHOTO_KEY, value.photo)
                        .putString(ACCOUNT_EMAIL_KEY, value.email)
                }
            }
        }

    /**
     * The account an earlier version kept signed in, filed under its YouTube
     * channel id (here its [Account.id]) with that channel's name and picture;
     * null once [account] is saved.
     */
    val oldAccount: Account?
        get() {
            val channelId = prefs.getString(OLD_ACCOUNT_ID_KEY, null) ?: return null
            return Account(
                id = channelId,
                name = prefs.getString(OLD_ACCOUNT_TITLE_KEY, null).orEmpty(),
                photo = prefs.getString(OLD_ACCOUNT_THUMBNAIL_KEY, null)?.takeIf(String::isNotEmpty),
            )
        }

    /** The YouTube channel ids that entries of earlier versions are still filed under. */
    fun oldAccountIds(): Set<String> =
        prefs.all.keys.flatMap { key -> listOf(SET_UP_KEY_PREFIX, START_KEY_PREFIX).filter(key::startsWith).map(key::removePrefix) }
            .filterTo(HashSet(), ::isChannelId)

    /** File what is kept here under [oldId] under [newId]; what [newId] already has stays. */
    fun moveAccountEntries(oldId: String, newId: String) {
        val done = isSetUpDone(oldId)
        val pending = prefs.getString(START_KEY_PREFIX + oldId, null)
        prefs.edit {
            if (done) {
                putBoolean(SET_UP_KEY_PREFIX + newId, true)
                if (prefs.getString(OLD_ACCOUNT_ID_KEY, null) == oldId) {
                    remove(OLD_SET_UP_KEY)
                }
            }
            if (pending != null && !prefs.contains(START_KEY_PREFIX + newId)) {
                putString(START_KEY_PREFIX + newId, pending)
            }
            remove(SET_UP_KEY_PREFIX + oldId).remove(START_KEY_PREFIX + oldId)
        }
    }

    /** Whether first run was finished on this install for the account; each account has its own mark, and signing out leaves them. */
    fun isSetUpDone(accountId: String): Boolean =
        prefs.getBoolean(SET_UP_KEY_PREFIX + accountId, false) ||
            // the one mark an earlier version kept, which was the signed-in account's
            (prefs.getBoolean(OLD_SET_UP_KEY, false) && prefs.getString(OLD_ACCOUNT_ID_KEY, null) == accountId)

    /** Mark first run finished for the account, or not. */
    fun setSetUpDone(accountId: String, done: Boolean) {
        prefs.edit {
            remove(OLD_SET_UP_KEY)
            if (done) putBoolean(SET_UP_KEY_PREFIX + accountId, true) else remove(SET_UP_KEY_PREFIX + accountId)
        }
    }

    /** The chosen colour theme. */
    var themeMode: ThemeMode
        get() = prefs.getString(THEME_KEY, null)?.let { name -> ThemeMode.entries.firstOrNull { mode -> mode.name == name } }
            ?: ThemeMode.SYSTEM
        set(value) = prefs.edit { putString(THEME_KEY, value.name) }

    /** First run's starting point for the account while channels still wait for it; null when none do. */
    fun pendingStart(accountId: String): PendingStart? = decodePendingStart(prefs.getString(START_KEY_PREFIX + accountId, null))

    /** Keep what still waits of first run's starting point for the account; null drops it. */
    fun keepPendingStart(accountId: String, pending: PendingStart?) {
        prefs.edit {
            if (pending == null) remove(START_KEY_PREFIX + accountId) else putString(START_KEY_PREFIX + accountId, encodePendingStart(pending))
        }
    }

    private companion object {
        const val START_KEY_PREFIX = "subtube.startFrom."
        const val DEVICE_KEY = "subtube.device"
        const val ACCOUNT_GOOGLE_ID_KEY = "account.googleId"
        const val ACCOUNT_NAME_KEY = "account.name"
        const val ACCOUNT_PHOTO_KEY = "account.photo"
        const val ACCOUNT_EMAIL_KEY = "account.email"

        // an earlier version's account: its YouTube channel
        const val OLD_ACCOUNT_ID_KEY = "account.id"
        const val OLD_ACCOUNT_TITLE_KEY = "account.title"
        const val OLD_ACCOUNT_THUMBNAIL_KEY = "account.thumbnail"
        const val OLD_ACCOUNT_HANDLE_KEY = "account.handle"
        const val SET_UP_KEY_PREFIX = "setUpDone."
        const val OLD_SET_UP_KEY = "setUpDone"
        const val THEME_KEY = "theme"
    }
}
