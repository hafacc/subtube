package cc.hafa.subtube.core

// the pattern language's `\s` set (shared/patterns/README.md), not the engine's
private val WHITESPACE: Set<Int> =
    ((0x0009..0x000D) + 0x0020 + 0x0085 + 0x00A0 + 0x1680 + (0x2000..0x200A) + 0x2028 + 0x2029 + 0x202F + 0x205F + 0x3000).toSet()
private const val SPECIAL = "\\^$.|?*+()[]{}"
private const val WHITESPACE_RUN = "\\s+"
private const val BOUNDARY = "\\b"

private fun isWordCharacter(codePoint: Int): Boolean =
    codePoint in 'A'.code..'Z'.code || codePoint in 'a'.code..'z'.code || codePoint in '0'.code..'9'.code || codePoint == '_'.code

private fun isSpecial(codePoint: Int): Boolean = codePoint < 0x80 && codePoint.toChar() in SPECIAL

/** One phrase's part of a pattern; empty for a phrase that is only whitespace. */
private fun phrasePattern(phrase: String): String {
    val trimmed = phrase.codePoints().toArray().toList()
        .dropWhile(WHITESPACE::contains)
        .dropLastWhile(WHITESPACE::contains)
    return if (trimmed.isEmpty()) {
        ""
    } else {
        val body = StringBuilder()
        trimmed.forEachIndexed { index, codePoint ->
            if (codePoint in WHITESPACE) {
                if (index == 0 || trimmed[index - 1] !in WHITESPACE) {
                    body.append(WHITESPACE_RUN)
                }
            } else {
                if (isSpecial(codePoint)) {
                    body.append('\\')
                }
                body.appendCodePoint(codePoint)
            }
        }
        val before = if (isWordCharacter(trimmed.first())) BOUNDARY else ""
        val after = if (isWordCharacter(trimmed.last())) BOUNDARY else ""
        "$before$body$after"
    }
}

/**
 * The filter pattern that finds any of [phrases], each as whole words
 * (shared/fixtures/phrases.json).
 *
 * Empty phrases and repeats are dropped; no phrases give the empty pattern.
 */
fun phrasesToPattern(phrases: Collection<String>): String =
    phrases.mapTo(LinkedHashSet(), ::phrasePattern).filter(String::isNotEmpty).joinToString("|")

/** The phrase one alternative of a pattern may stand for; null when it uses anything a phrase can't produce. */
private fun readPhrase(alternative: List<Int>): String? {
    val phrase = StringBuilder()
    var index = 0
    while (index < alternative.size) {
        val codePoint = alternative[index]
        val next = alternative.getOrNull(index + 1)
        if (codePoint != '\\'.code) {
            phrase.appendCodePoint(codePoint)
            index += 1
        } else if (next == 'b'.code && (index == 0 || index == alternative.size - 2)) {
            index += 2
        } else if (next == 's'.code && alternative.getOrNull(index + 2) == '+'.code) {
            phrase.append(' ')
            index += 3
        } else if (next != null && isSpecial(next)) {
            phrase.appendCodePoint(next)
            index += 2
        } else {
            return null
        }
    }
    return phrase.toString()
}

/**
 * The phrases [pattern] was built from, or null when [phrasesToPattern] could
 * not have produced it.
 */
fun patternToPhrases(pattern: String): List<String>? {
    val alternatives = arrayListOf(ArrayList<Int>())
    val codePoints = pattern.codePoints().toArray()
    var index = 0
    while (index < codePoints.size) {
        val codePoint = codePoints[index]
        if (codePoint == '|'.code) {
            alternatives.add(ArrayList())
        } else {
            alternatives.last().add(codePoint)
            if (codePoint == '\\'.code && index + 1 < codePoints.size) {
                index += 1
                alternatives.last().add(codePoints[index])
            }
        }
        index += 1
    }
    val phrases = if (pattern.isEmpty()) emptyList() else alternatives.map(::readPhrase)
    val read = phrases.filterNotNull()
    return if (read.size == phrases.size && phrasesToPattern(read) == pattern) read else null
}

/** A saved pattern as the app uses it: unchanged when it is phrases, otherwise no pattern. */
fun phrasePatternOnly(pattern: String): String = if (patternToPhrases(pattern) != null) pattern else ""
