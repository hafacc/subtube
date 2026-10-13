package cc.hafa.subtube

import android.content.Context
import androidx.core.content.edit
import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.Account
import cc.hafa.subtube.core.PendingStart
import cc.hafa.subtube.core.StartFrom
import cc.hafa.subtube.data.AccountPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** What a device keeps per account is filed under the Google account's id; an earlier version's is moved there. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AccountPrefsTest {
    private val app: SubtubeApp = ApplicationProvider.getApplicationContext()
    private val stored = app.getSharedPreferences("subtube", Context.MODE_PRIVATE)
    private val prefs = AccountPrefs(app)
    private val channelId = "UC" + "a".repeat(22)
    private val ada = Account(id = "42", name = "Ada", photo = "https://example.com/ada.jpg", email = "ada@example.com")

    @Test
    fun theAccountIsKeptWithItsNamePhotoAndAddress() {
        assertNull(prefs.account)
        prefs.account = ada
        assertEquals(ada, AccountPrefs(app).account)
        prefs.account = null
        assertNull(prefs.account)
    }

    @Test
    fun anEarlierVersionsAccountIsReadUntilTheNewOneIsSaved() {
        stored.edit { putString("account.id", channelId).putString("account.title", "Ada's channel").putString("account.thumbnail", "") }
        assertNull(prefs.account)
        assertEquals(Account(id = channelId, name = "Ada's channel"), prefs.oldAccount)
        prefs.account = ada
        assertNull(prefs.oldAccount)
        assertEquals(ada, prefs.account)
    }

    @Test
    fun entriesFiledUnderAChannelMoveToTheAccount() {
        val pending = PendingStart(StartFrom.WEEK, 1000, listOf("UC1"))
        prefs.setSetUpDone(channelId, true)
        prefs.keepPendingStart(channelId, pending)
        prefs.setSetUpDone("7", true)
        assertEquals(setOf(channelId), prefs.oldAccountIds())

        prefs.moveAccountEntries(channelId, "42")

        assertTrue(prefs.isSetUpDone("42"))
        assertEquals(pending, prefs.pendingStart("42"))
        assertFalse(prefs.isSetUpDone(channelId))
        assertNull(prefs.pendingStart(channelId))
        assertTrue(prefs.oldAccountIds().isEmpty())
    }

    @Test
    fun theOneMarkOfTheOldestVersionsMovesWithItsAccount() {
        stored.edit { putString("account.id", channelId).putBoolean("setUpDone", true) }
        assertTrue(prefs.isSetUpDone(channelId))
        prefs.moveAccountEntries(channelId, "42")
        prefs.account = ada
        assertTrue(prefs.isSetUpDone("42"))
        assertFalse(prefs.isSetUpDone(channelId))
    }

    @Test
    fun anAccountNotSetUpStaysNotSetUp() {
        prefs.moveAccountEntries(channelId, "42")
        assertFalse(prefs.isSetUpDone("42"))
    }
}
