package cc.hafa.subtube.core

import java.util.logging.Logger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.coroutines.executeAsync

/** The access token expired or was revoked; a fresh one may work. */
class TokenExpiredException : Exception("Google access token expired or missing")

/**
 * The token is valid but lacks a scope subtube asked for: the user unticked
 * YouTube or Drive access on Google's consent screen. Signing in again fixes it.
 */
class InsufficientScopeException : Exception("Google access was granted without a permission subtube needs")

/** The playlist doesn't exist; a channel with no Shorts has no Shorts list. */
class PlaylistNotFoundException(playlistId: String) : Exception("Playlist $playlistId not found")

/** YouTube refused a request because the app's daily quota is used up; asking again today can't work. */
class DailyLimitException : Exception("YouTube's daily limit is used up")

/** Where everything below the interface logs what it keeps out of it. */
internal val logger: Logger = Logger.getLogger("subtube")

/** The Google API a request goes to; each words its refusals its own way. */
internal enum class GoogleApi(
    /** The texts in a 403's body that mean a permission subtube asked for wasn't granted. */
    val scopeMarkers: List<String>,
    /** Whether a 403 can mean the app's daily quota is used up. */
    val hasDailyLimit: Boolean,
) {
    /** The YouTube Data API. */
    YOUTUBE(listOf("ACCESS_TOKEN_SCOPE_INSUFFICIENT", "insufficientPermissions"), hasDailyLimit = true),

    /** The Drive API. */
    DRIVE(listOf("insufficient"), hasDailyLimit = false),
}

private val DAILY_LIMIT_REASONS = setOf("quotaExceeded", "dailyLimitExceeded")

/**
 * Whether an answer says the daily quota is used up: [status] 403 with a JSON
 * [body] whose `error.errors` holds a `reason` of `quotaExceeded` or
 * `dailyLimitExceeded`. The per-minute `rateLimitExceeded` is not it.
 */
fun isDailyLimit(status: Int, body: String): Boolean =
    if (status != 403) {
        false
    } else {
        val root = try {
            Json.parseToJsonElement(body)
        } catch (_: SerializationException) {
            null
        }
        val errors = ((root as? JsonObject)?.get("error") as? JsonObject)?.get("errors") as? JsonArray
        errors.orEmpty().any { entry -> (entry as? JsonObject)?.get("reason").stringOrNull() in DAILY_LIMIT_REASONS }
    }

/** Any other failed Google API request. */
class GoogleApiException(
    /** The HTTP status Google answered with. */
    val status: Int,
    message: String,
) : Exception(message)

/** A finished response: its status and body text. */
internal data class HttpResult(val status: Int, val body: String)

/** Run [request] to [api] with the bearer [token] and return its body, mapping Google's error statuses to exceptions. */
internal suspend fun OkHttpClient.googleCall(request: Request, token: String, api: GoogleApi, label: String): String {
    val authorized = request.newBuilder().header("Authorization", "Bearer $token").build()
    val result = newCall(authorized).executeAsync().use { response ->
        HttpResult(response.code, withContext(Dispatchers.IO) { response.body.string() })
    }
    if (result.status == 401) {
        throw TokenExpiredException()
    }
    if (result.status !in 200..299) {
        val body = result.body
        if (result.status == 403 && api.scopeMarkers.any { marker -> marker in body }) {
            throw InsufficientScopeException()
        }
        if (api.hasDailyLimit && isDailyLimit(result.status, body)) {
            throw DailyLimitException()
        }
        if (result.status == 404 && "playlistNotFound" in body) {
            throw PlaylistNotFoundException(request.url.queryParameter("playlistId").orEmpty())
        }
        throw GoogleApiException(result.status, "$label failed: ${result.status} $body")
    }
    return result.body
}
