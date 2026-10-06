package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PhrasesTest {
    @Test
    fun buildsWholeWordAlternativesAndReadsThemBack() {
        val pattern = phrasesToPattern(listOf(" trailer ", "hello   world", "C++", "trailer", ""))
        assertEquals("""\btrailer\b|\bhello\s+world\b|\bC\+\+""", pattern)
        assertEquals(listOf("trailer", "hello world", "C++"), patternToPhrases(pattern))
    }

    @Test
    fun aPatternNoPhrasesCouldBuildIsNotPhrases() {
        assertNull(patternToPhrases("cat"))
        assertNull(patternToPhrases("""(ep|episode) ?\d+"""))
        assertEquals("", phrasePatternOnly("cat"))
        assertEquals("""\bcat\b""", phrasePatternOnly("""\bcat\b"""))
        assertEquals(emptyList(), patternToPhrases(""))
    }

    @Test
    fun aFilterSavedWithTopicsWritesEachOnce() {
        val filter = defaultFilter(Subscription("UCone", "One", "")).copy(topics = listOf("10", "28", "10"))
        val written = filterToJson(filter)
        assertEquals("""["10","28"]""", written["topics"].toString())
        assertEquals(listOf("10", "28"), filterFromJson("UCone", "One", "", written).topics)
    }
}
