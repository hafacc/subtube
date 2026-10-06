package cc.hafa.subtube.core

import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient

class ShortsProbeTest {
    private val server = MockWebServer().apply { start() }
    private val probe = ShortsProbe(OkHttpClient(), server.url("/shorts/"))
    private val videoId = "abcdefghijk"

    @AfterTest
    fun stop() {
        server.close()
    }

    @Test
    fun okIsAShort() = runTest {
        server.enqueue(MockResponse.Builder().code(200).build())
        assertEquals(true, probe.isShort(videoId))
        val request = server.takeRequest()
        assertEquals("/shorts/$videoId", request.url.encodedPath)
        assertEquals("SOCS=CAI; CONSENT=YES+", request.headers["Cookie"])
    }

    @Test
    fun aRedirectIsNotAShort() = runTest {
        server.enqueue(MockResponse.Builder().code(303).addHeader("Location", "/watch?v=$videoId").build())
        assertEquals(false, probe.isShort(videoId))
        assertEquals(1, server.requestCount)
    }

    @Test
    fun anythingElseIsInconclusive() = runTest {
        server.enqueue(MockResponse.Builder().code(500).build())
        assertNull(probe.isShort(videoId))
        assertNull(probe.isShort("not an id"))
    }
}
