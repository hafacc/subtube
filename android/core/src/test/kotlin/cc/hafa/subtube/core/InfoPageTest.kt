package cc.hafa.subtube.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InfoPageTest {
    private val pages = File(checkNotNull(System.getProperty("subtube.shared")), "pages")

    @Test
    fun sharedPagesDecode() {
        for (name in listOf("privacy", "terms")) {
            val page = readInfoPage(File(pages, "$name.json").readText())
            assertEquals("https://subtube.hafa.cc/$name", page.web)
            assertTrue(page.title.isNotEmpty())
            val texts = page.intro + page.sections.flatMap(InfoSection::items)
            for (text in texts) {
                val runs = infoText(text)
                // every bracket belongs to a link, as the schema requires
                assertTrue(runs.filterIsInstance<InfoText.Plain>().none { run -> '[' in run.text || ']' in run.text }, text)
            }
        }
    }

    @Test
    fun splitsLinks() {
        assertEquals(
            listOf(
                InfoText.Plain("See "),
                InfoText.Link("terms", "https://example.com/t"),
                InfoText.Plain(" or "),
                InfoText.Link("mail", "mailto:a@b.c"),
                InfoText.Plain("."),
            ),
            infoText("See [terms](https://example.com/t) or [mail](mailto:a@b.c)."),
        )
        assertEquals(listOf(InfoText.Link("x", "https://x.y")), infoText("[x](https://x.y)"))
        assertEquals(emptyList(), infoText(""))
    }
}
