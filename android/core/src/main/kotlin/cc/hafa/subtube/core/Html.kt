package cc.hafa.subtube.core

private val ENTITY = Regex("""&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);""")

private val NAMED_ENTITIES = mapOf(
    "amp" to "&",
    "lt" to "<",
    "gt" to ">",
    "quot" to "\"",
    "apos" to "'",
    "nbsp" to " ",
)

/**
 * Decode the HTML entities the Data API puts in snippet titles (e.g.
 * "Tom &amp; Jerry", "don&#39;t"), so they display as written and per-channel
 * regexes match the text the user sees. Unknown entities are left as they are.
 */
fun decodeHtmlEntities(text: String): String =
    ENTITY.replace(text) { match ->
        val body = match.groupValues[1]
        val codePoint = when {
            body.startsWith("#x") || body.startsWith("#X") -> body.substring(2).toIntOrNull(16)
            body.startsWith("#") -> body.substring(1).toIntOrNull()
            else -> null
        }
        when {
            codePoint != null && Character.isValidCodePoint(codePoint) -> String(Character.toChars(codePoint))
            body.startsWith("#") -> match.value
            else -> NAMED_ENTITIES[body] ?: match.value
        }
    }
