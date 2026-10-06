package cc.hafa.subtube.auth

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.coroutines.executeAsync

/** What subtube reads: YouTube, and its own folder in Drive. */
private val SCOPES = listOf(
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/drive.appdata",
)

/** A cached token is handed out only while it has at least this long left. */
private const val TOKEN_MIN_REMAINING_MS = 5 * 60 * 1000L

/** How long to trust a token whose lifetime tokeninfo couldn't report. */
private const val UNKNOWN_LIFETIME_MS = 10 * 60 * 1000L

private const val TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
private const val REVOKE_URL = "https://oauth2.googleapis.com/revoke"

@Serializable
private data class TokenInfo(@SerialName("expires_in") val expiresIn: Long? = null)

private data class CachedToken(val accessToken: String, val expiresAt: Long)

/** The outcome of asking Play services for access without showing anything. */
sealed interface AuthorizeOutcome {
    /** Access granted; here is the token. */
    data class Granted(val accessToken: String) : AuthorizeOutcome

    /** Google needs the user (account choice or consent); launch this to ask. */
    data class NeedsConsent(val pendingIntent: PendingIntent) : AuthorizeOutcome
}

/**
 * Google access through Play services' AuthorizationClient. The Android OAuth
 * client is matched by package name and signing certificate, so there is no
 * client id here and no refresh token to keep: Play services re-issues access
 * tokens silently. It doesn't say when one expires, and may hand back one it
 * cached, so the lifetime is read from tokeninfo. Signing out only forgets the
 * token on this device ([signOut]); Google's grant stands until [revoke],
 * which deleting the profile calls.
 */
class GoogleAuth(context: Context, private val http: OkHttpClient) {
    private val client = Identity.getAuthorizationClient(context)
    private val request = AuthorizationRequest.builder()
        .setRequestedScopes(SCOPES.map(::Scope))
        .build()

    // signing out leaves Google's grant standing, so only asking for the chooser lets the user pick another account
    private val requestWithChooser = AuthorizationRequest.builder()
        .setRequestedScopes(SCOPES.map(::Scope))
        .setPrompt(AuthorizationRequest.Prompt.SELECT_ACCOUNT)
        .build()
    private val json = Json { ignoreUnknownKeys = true }
    private val mutex = Mutex()
    private var cached: CachedToken? = null

    /**
     * Ask for access; never shows UI itself. With [chooseAccount] Google is
     * asked to let the user pick the account, as a sign-in from signed out does.
     */
    suspend fun authorize(chooseAccount: Boolean = false): AuthorizeOutcome {
        val result = client.authorize(if (chooseAccount) requestWithChooser else request).await()
        val pendingIntent = result.pendingIntent
        return if (result.hasResolution() && pendingIntent != null) {
            AuthorizeOutcome.NeedsConsent(pendingIntent)
        } else {
            AuthorizeOutcome.Granted(remember(result))
        }
    }

    /** Finish the consent flow [AuthorizeOutcome.NeedsConsent] started; returns the token. */
    suspend fun completeConsent(data: Intent?): String =
        remember(client.getAuthorizationResultFromIntent(data))

    private suspend fun remember(result: AuthorizationResult): String {
        val token = result.accessToken ?: throw IllegalStateException("Google returned no access token")
        mutex.withLock { cached = CachedToken(token, System.currentTimeMillis() + lifetimeMs(token)) }
        return token
    }

    private suspend fun lifetimeMs(token: String): Long = try {
        // in the body, not the address: a token must not end up wherever addresses are logged
        val ask = Request.Builder().url(TOKENINFO_URL).post(FormBody.Builder().add("access_token", token).build()).build()
        val body = http.newCall(ask).executeAsync().use { response ->
            if (response.isSuccessful) withContext(Dispatchers.IO) { response.body.string() } else null
        }
        body?.let { json.decodeFromString<TokenInfo>(it).expiresIn }?.times(1000) ?: UNKNOWN_LIFETIME_MS
    } catch (caught: CancellationException) {
        throw caught
    } catch (_: Exception) {
        UNKNOWN_LIFETIME_MS
    }

    /**
     * A token with time left, minted silently when needed; null when only the
     * user can grant one (signed out of Google, or consent withdrawn).
     */
    suspend fun silentToken(): String? {
        val current = mutex.withLock { cached }
        return if (current != null && current.expiresAt - System.currentTimeMillis() > TOKEN_MIN_REMAINING_MS) {
            current.accessToken
        } else {
            // Play services would hand the same nearly-expired token back
            current?.let { stale -> clear(stale.accessToken) }
            when (val outcome = authorize()) {
                is AuthorizeOutcome.Granted -> outcome.accessToken
                is AuthorizeOutcome.NeedsConsent -> null
            }
        }
    }

    /** Drop a token Google rejected and mint another silently; null when only the user can. */
    suspend fun replaceRejected(rejected: String): String? {
        clear(rejected)
        return silentToken()
    }

    private suspend fun forget(token: String) {
        mutex.withLock {
            if (cached?.accessToken == token) {
                cached = null
            }
        }
        client.clearToken(ClearTokenRequest.builder().setToken(token).build()).await()
    }

    private suspend fun clear(token: String) {
        try {
            forget(token)
        } catch (caught: CancellationException) {
            throw caught
        } catch (_: Exception) {
            // Play services keeps it until it expires; the copy here is already gone
        }
    }

    /**
     * Forget the token on this device. Google's grant stands, so other
     * devices stay signed in and the next sign-in here asks for no consent.
     * A failure to clear it in Play services is thrown.
     */
    suspend fun signOut() {
        mutex.withLock { cached?.accessToken }?.let { token -> forget(token) }
    }

    /** Withdraw Google's grant and forget the token, so the next sign-in asks for consent again; an unreachable Google leaves the grant standing. */
    suspend fun revoke() {
        val token = mutex.withLock { cached?.accessToken } ?: try {
            silentToken()
        } catch (caught: CancellationException) {
            throw caught
        } catch (_: Exception) {
            null
        }
        if (token != null) {
            try {
                val revoke = Request.Builder().url(REVOKE_URL).post(FormBody.Builder().add("token", token).build()).build()
                http.newCall(revoke).executeAsync().close()
            } catch (_: IOException) {
                // an unrevoked token still expires within the hour
            }
            clear(token)
        }
    }
}
