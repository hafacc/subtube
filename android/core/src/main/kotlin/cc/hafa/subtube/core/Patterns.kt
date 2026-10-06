package cc.hafa.subtube.core

/*
 * The filter pattern language of shared/patterns/README.md: one meta regex that
 * accepts exactly the valid patterns, and the rewrite that turns a valid
 * pattern into an engine pattern that java.util.regex, JavaScript and ICU all
 * match the same way. A port of shared/tools/pattern.ts.
 */

private const val DIGITS = "0123456789"
private const val LOWER = "abcdefghijklmnopqrstuvwxyz"
private const val UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

/** `x-[x-last]` for every character of one run, so a range must run forwards. */
private fun orderedRanges(run: String): List<String> = run.map { first -> "$first-[$first-${run.last()}]" }

private fun buildMetaRegex(): String {
    val literal = """[^\\\^\$\.\|\?\*\+\(\)\[\]\{\}]"""
    val escaped = """\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/tnrdDwWsS]"""
    val anchor = """\^|\$|\\[bB]"""
    val classItem = (
        orderedRanges(DIGITS) + orderedRanges(LOWER) + orderedRanges(UPPER) + listOf(
            """[^\\\]\[\^\-&]""",
            "&(?!&)",
            """\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/\-tnrdws]""",
        )
        ).joinToString("|")
    val characterClass = """\[\^?(?!:)(?:$classItem)+\]"""
    val bounds = DIGITS.map { digit -> "$digit,[$digit-9]" }.joinToString("|")
    val quantifier = """(?:[\*\+\?]|\{[0-9]\}|\{[0-9],\}|\{(?:$bounds)\})\??"""
    val atom = """(?:$literal|$escaped|\.|$characterClass)"""
    val piece = "(?:$anchor|$atom(?:$quantifier)?)"
    val group = """\((?:\?:)?(?:$piece|\|)*\)"""
    return "^(?:$piece|$group(?:$quantifier)?|\\|)*$"
}

/** The meta regex, identical to shared/patterns/meta-regex.txt. */
val PATTERN_META_REGEX: String = buildMetaRegex()

private val META = Regex(PATTERN_META_REGEX)

/** Whether [pattern] is in the shared pattern language. */
fun isValidPattern(pattern: String): Boolean = META.containsMatchIn(pattern)

private const val WORD = "A-Za-z0-9_"
private const val SPACE =
    "\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"
private const val ANY = """[\s\S]"""

private val SHORTHAND_OUTSIDE = mapOf(
    "d" to "[0-9]",
    "D" to "[^0-9]",
    "w" to "[$WORD]",
    "W" to "[^$WORD]",
    "s" to "[$SPACE]",
    "S" to "[^$SPACE]",
    "b" to "(?:(?<=[$WORD])(?![$WORD])|(?<![$WORD])(?=[$WORD]))",
    "B" to "(?:(?<=[$WORD])(?=[$WORD])|(?<![$WORD])(?![$WORD]))",
)

private val SHORTHAND_INSIDE = mapOf("d" to "0-9", "w" to WORD, "s" to SPACE)

private fun isAsciiLetter(char: String): Boolean = char.length == 1 && char[0] in 'a'..'z' || char.length == 1 && char[0] in 'A'..'Z'

private fun swapCase(char: String): String = if (char == char.lowercase()) char.uppercase() else char.lowercase()

/** The engine pattern for a valid [pattern]: what every client compiles with no flags and searches with. */
fun toEnginePattern(pattern: String, caseSensitive: Boolean): String {
    val chars = pattern.codePoints().toArray().map { codePoint -> String(Character.toChars(codePoint)) }
    val out = StringBuilder()
    var index = 0
    while (index < chars.size) {
        val char = chars[index]
        when {
            char == "\\" -> {
                val next = chars[index + 1]
                out.append(SHORTHAND_OUTSIDE[next] ?: "\\$next")
                index += 2
            }
            char == "." -> {
                out.append(ANY)
                index += 1
            }
            char == "$" -> {
                out.append("(?!$ANY)")
                index += 1
            }
            char == "(" -> {
                out.append("(?:")
                index += if (chars.getOrNull(index + 1) == "?") 3 else 1
            }
            char == "[" -> {
                index += 1
                val body = StringBuilder("[")
                if (chars[index] == "^") {
                    body.append("^")
                    index += 1
                }
                val extra = StringBuilder()
                while (chars[index] != "]") {
                    val item = chars[index]
                    if (item == "\\") {
                        val next = chars[index + 1]
                        body.append(SHORTHAND_INSIDE[next] ?: "\\$next")
                        index += 2
                    } else if (chars.getOrNull(index + 1) == "-") {
                        val last = chars[index + 2]
                        body.append("$item-$last")
                        if (!caseSensitive && isAsciiLetter(item)) {
                            extra.append("${swapCase(item)}-${swapCase(last)}")
                        }
                        index += 3
                    } else {
                        body.append(item)
                        if (!caseSensitive && isAsciiLetter(item)) {
                            extra.append(swapCase(item))
                        }
                        index += 1
                    }
                }
                out.append(body).append(extra).append("]")
                index += 1
            }
            !caseSensitive && isAsciiLetter(char) -> {
                out.append("[").append(char).append(swapCase(char)).append("]")
                index += 1
            }
            else -> {
                out.append(char)
                index += 1
            }
        }
    }
    return if (out.isEmpty()) "(?:)" else out.toString()
}

/** Compile a valid pattern for searching; null when it isn't in the language. */
fun compilePattern(pattern: String, caseSensitive: Boolean): Regex? =
    if (isValidPattern(pattern)) Regex(toEnginePattern(pattern, caseSensitive)) else null
