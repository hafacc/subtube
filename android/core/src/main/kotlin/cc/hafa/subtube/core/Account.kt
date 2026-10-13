package cc.hafa.subtube.core

/** The signed-in Google account, as Drive reports it. */
data class Account(
    /** The account's id in Drive, which keys what a device keeps for it. */
    val id: String,
    /** The account's name. */
    val name: String,
    /** The account's picture, when it has one. */
    val photo: String? = null,
    /** The account's address, when Drive shares it. */
    val email: String? = null,
)

/** The account behind Drive's answer; null when it carries no id. */
fun DriveUser.toAccount(): Account? = permissionId?.let { id -> Account(id = id, name = displayName, photo = photoLink, email = emailAddress) }

private val CHANNEL_ID = Regex("UC[\\w-]{22}")

/** Whether [id] is a YouTube channel's, which earlier versions filed an account's entries under. */
fun isChannelId(id: String): Boolean = CHANNEL_ID.matches(id)

/** The key of an account's not-yet-uploaded edits in a [SyncStorage]. */
fun syncKey(accountId: String): String = SYNC_KEY_PREFIX + accountId

/** The key of an account's uploaded Drive file id in a [SyncStorage]. */
fun uploadedKey(accountId: String): String = UPLOADED_KEY_PREFIX + accountId

/** The YouTube channel ids that [keys] of a [SyncStorage] still file an earlier version's entries under. */
fun oldSyncAccountIds(keys: Iterable<String>): Set<String> =
    keys.flatMap { key -> listOf(SYNC_KEY_PREFIX, UPLOADED_KEY_PREFIX).filter(key::startsWith).map(key::removePrefix) }
        .filterTo(HashSet(), ::isChannelId)

/** File what [storage] keeps under [oldId] under [newId]; what [newId] already has stays. */
fun moveSyncEntries(storage: SyncStorage, oldId: String, newId: String) {
    for (key in listOf(::syncKey, ::uploadedKey)) {
        val value = storage.read(key(oldId))
        if (value != null) {
            if (storage.read(key(newId)) == null) {
                storage.write(key(newId), value)
            }
            storage.remove(key(oldId))
        }
    }
}

private const val SYNC_KEY_PREFIX = "subtube.sync."
private const val UPLOADED_KEY_PREFIX = "subtube.uploaded."
