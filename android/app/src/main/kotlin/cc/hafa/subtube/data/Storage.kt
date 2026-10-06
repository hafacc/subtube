package cc.hafa.subtube.data

import android.content.Context
import android.util.AtomicFile
import androidx.core.content.edit
import cc.hafa.subtube.core.ChannelSummary
import cc.hafa.subtube.core.PendingStart
import cc.hafa.subtube.core.decodePendingStart
import cc.hafa.subtube.core.encodePendingStart
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

    /** The account last signed in, or null when signed out. */
    var account: ChannelSummary?
        get() {
            val channelId = prefs.getString(ACCOUNT_ID_KEY, null) ?: return null
            return ChannelSummary(
                channelId = channelId,
                title = prefs.getString(ACCOUNT_TITLE_KEY, null).orEmpty(),
                thumbnail = prefs.getString(ACCOUNT_THUMBNAIL_KEY, null).orEmpty(),
                handle = prefs.getString(ACCOUNT_HANDLE_KEY, null),
            )
        }
        set(value) {
            prefs.edit {
                if (value == null) {
                    remove(ACCOUNT_ID_KEY).remove(ACCOUNT_TITLE_KEY).remove(ACCOUNT_THUMBNAIL_KEY).remove(ACCOUNT_HANDLE_KEY)
                } else {
                    putString(ACCOUNT_ID_KEY, value.channelId)
                        .putString(ACCOUNT_TITLE_KEY, value.title)
                        .putString(ACCOUNT_THUMBNAIL_KEY, value.thumbnail)
                        .putString(ACCOUNT_HANDLE_KEY, value.handle)
                }
            }
        }

    /** Whether first run was finished on this install for the account; each account has its own mark, and signing out leaves them. */
    fun isSetUpDone(accountId: String): Boolean =
        prefs.getBoolean(SET_UP_KEY_PREFIX + accountId, false) ||
            // the one mark an earlier version kept, which was the signed-in account's
            (prefs.getBoolean(OLD_SET_UP_KEY, false) && prefs.getString(ACCOUNT_ID_KEY, null) == accountId)

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
        const val ACCOUNT_ID_KEY = "account.id"
        const val ACCOUNT_TITLE_KEY = "account.title"
        const val ACCOUNT_THUMBNAIL_KEY = "account.thumbnail"
        const val ACCOUNT_HANDLE_KEY = "account.handle"
        const val SET_UP_KEY_PREFIX = "setUpDone."
        const val OLD_SET_UP_KEY = "setUpDone"
        const val THEME_KEY = "theme"
    }
}
