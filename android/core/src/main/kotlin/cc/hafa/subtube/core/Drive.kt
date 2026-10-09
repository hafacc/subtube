package cc.hafa.subtube.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A file in the Drive app folder. */
@Serializable
data class DriveFile(
    /** Drive's id for the file. */
    val id: String,
    /** The file's name; a device's file is `device-<id>.json`. */
    val name: String,
    /** RFC 3339; compared only for equality, to spot a changed file. */
    val modifiedTime: String,
)

/** The Google account behind a token, as Drive reports it. */
@Serializable
data class DriveUser(
    /** The account's name. */
    val displayName: String,
    /** The account's address, when Drive shares it. */
    val emailAddress: String? = null,
    /** The account's picture, when it has one. */
    val photoLink: String? = null,
)

@Serializable
private data class AboutResponse(val user: DriveUser)

@Serializable
private data class FileListResponse(val files: List<DriveFile> = emptyList(), val nextPageToken: String? = null)

private val JSON_TYPE = "application/json; charset=UTF-8".toMediaType()
private const val FILE_FIELDS = "id,name,modifiedTime"

/** The Drive app folder: files only subtube's OAuth clients can see. */
class DriveClient(
    private val http: OkHttpClient,
    private val apiBase: HttpUrl = "https://www.googleapis.com/".toHttpUrl(),
) {
    private val json = Json { ignoreUnknownKeys = true }

    private fun filesUrl(): HttpUrl.Builder = apiBase.newBuilder().addPathSegments("drive/v3/files")

    private fun uploadUrl(): HttpUrl.Builder = apiBase.newBuilder().addPathSegments("upload/drive/v3/files")

    /** The signed-in Google account's name, address and picture; the app-folder scope is enough to ask. */
    suspend fun about(token: String): DriveUser {
        val url = apiBase.newBuilder()
            .addPathSegments("drive/v3/about")
            .addQueryParameter("fields", "user(displayName,emailAddress,photoLink)")
            .build()
        val body = http.googleCall(Request.Builder().url(url).build(), token, GoogleApi.DRIVE, "Google Drive about")
        return json.decodeFromString<AboutResponse>(body).user
    }

    /** Every file in the app folder. */
    suspend fun listAppFiles(token: String): List<DriveFile> {
        val files = ArrayList<DriveFile>()
        var pageToken: String? = null
        do {
            val url = filesUrl()
                .addQueryParameter("spaces", "appDataFolder")
                .addQueryParameter("fields", "nextPageToken,files($FILE_FIELDS)")
                .addQueryParameter("pageSize", "100")
                .apply { pageToken?.let { addQueryParameter("pageToken", it) } }
                .build()
            val body = http.googleCall(Request.Builder().url(url).build(), token, GoogleApi.DRIVE, "Google Drive list")
            val data = json.decodeFromString<FileListResponse>(body)
            files.addAll(data.files)
            pageToken = data.nextPageToken
        } while (pageToken != null)
        return files
    }

    /** Whether the file with [fileId] is still there: asked of the file itself, so no listing's delay can mislead. */
    suspend fun exists(fileId: String, token: String): Boolean {
        val url = filesUrl().addPathSegment(fileId).addQueryParameter("fields", "id").build()
        return try {
            http.googleCall(Request.Builder().url(url).build(), token, GoogleApi.DRIVE, "Google Drive get")
            true
        } catch (caught: GoogleApiException) {
            if (caught.status == 404) false else throw caught
        }
    }

    /** A file's content as text. */
    suspend fun download(fileId: String, token: String): String {
        val url = filesUrl().addPathSegment(fileId).addQueryParameter("alt", "media").build()
        return http.googleCall(Request.Builder().url(url).build(), token, GoogleApi.DRIVE, "Google Drive download")
    }

    /** Delete a file for good. */
    suspend fun delete(fileId: String, token: String) {
        val url = filesUrl().addPathSegment(fileId).build()
        http.googleCall(Request.Builder().url(url).delete().build(), token, GoogleApi.DRIVE, "Google Drive delete")
    }

    /** Create a JSON file in the app folder. */
    suspend fun createJson(name: String, content: String, token: String): DriveFile {
        val metadata = buildJsonObject {
            put("name", name)
            putJsonArray("parents") { add("appDataFolder") }
        }
        val body = MultipartBody.Builder()
            .setType("multipart/related".toMediaType())
            .addPart(metadata.toString().toRequestBody(JSON_TYPE))
            .addPart(content.toRequestBody(JSON_TYPE))
            .build()
        val url = uploadUrl().addQueryParameter("uploadType", "multipart").addQueryParameter("fields", FILE_FIELDS).build()
        val response = http.googleCall(Request.Builder().url(url).post(body).build(), token, GoogleApi.DRIVE, "Google Drive create")
        return json.decodeFromString(response)
    }

    /** Replace a file's content. */
    suspend fun updateJson(fileId: String, content: String, token: String): DriveFile {
        val url = uploadUrl()
            .addPathSegment(fileId)
            .addQueryParameter("uploadType", "media")
            .addQueryParameter("fields", FILE_FIELDS)
            .build()
        val request = Request.Builder().url(url).patch(content.toRequestBody(JSON_TYPE)).build()
        return json.decodeFromString(http.googleCall(request, token, GoogleApi.DRIVE, "Google Drive update"))
    }
}
