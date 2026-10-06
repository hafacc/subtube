package cc.hafa.subtube.core

import java.util.Locale

/** Text with every code point lowercased on its own, locale-independently, so every client folds alike. */
fun foldCase(text: String): String {
    val folded = StringBuilder(text.length)
    var index = 0
    while (index < text.length) {
        val codePoint = text.codePointAt(index)
        // one code point at a time: a whole-string lowercase would turn a final Σ into ς
        folded.append(String(Character.toChars(codePoint)).lowercase(Locale.ROOT))
        index += Character.charCount(codePoint)
    }
    return folded.toString()
}

/** Order two strings by Unicode code point, not UTF-16 unit; a prefix goes first. */
fun compareCodePoints(left: String, right: String): Int {
    var leftIndex = 0
    var rightIndex = 0
    while (leftIndex < left.length && rightIndex < right.length) {
        val leftPoint = left.codePointAt(leftIndex)
        val rightPoint = right.codePointAt(rightIndex)
        if (leftPoint != rightPoint) {
            return leftPoint.compareTo(rightPoint)
        }
        leftIndex += Character.charCount(leftPoint)
        rightIndex += Character.charCount(rightPoint)
    }
    return (left.length - leftIndex).compareTo(right.length - rightIndex)
}

/** Whether a search for [query] finds [name]: anywhere in it, ignoring case and the white space around what was typed; an empty search finds everything. */
fun matchesSearch(name: String, query: String): Boolean = foldCase(name).contains(foldCase(query.trim()))

/** Order two strings ignoring case: [foldCase] both, then by code point. */
fun compareIgnoringCase(left: String, right: String): Int = compareCodePoints(foldCase(left), foldCase(right))

/** [compareIgnoringCase] as a comparator: the one case-insensitive order every list uses. */
val ignoringCase: Comparator<String> = Comparator(::compareIgnoringCase)
