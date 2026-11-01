package cc.hafa.subtube.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A page the app shows in place of the website: the privacy policy or the terms (`shared/pages`). */
@Serializable
data class InfoPage(
    /** The page's title. */
    val title: String,
    /** A one-line summary of the page. */
    val description: String,
    /** Where the website publishes the page. */
    val web: String,
    /** The day the page last changed, as `yyyy-mm-dd`. */
    val updated: String,
    /** The paragraphs before the first section. */
    val intro: List<String>,
    /** The headed lists after the intro. */
    val sections: List<InfoSection>,
)

/** A heading and the bulleted items under it. */
@Serializable
data class InfoSection(
    /** The section's heading. */
    val heading: String,
    /** The section's bullets. */
    val items: List<String>,
)

/** A run of a page's text: plain, or a link. */
sealed interface InfoText {
    /** Text shown as it is. */
    data class Plain(val text: String) : InfoText

    /** [label] linking to [url], an https: or mailto: address. */
    data class Link(val label: String, val url: String) : InfoText
}

private val pageJson = Json { ignoreUnknownKeys = true }

// the schema's one markup: [label](url)
private val LINK = Regex("""\[([^\[\]]+)]\(((?:https|mailto):[^()\s]+)\)""")

/** Read a page from its JSON. */
fun readInfoPage(json: String): InfoPage = pageJson.decodeFromString(json)

/** Split a page's [text] into plain runs and its `[label](url)` links. */
fun infoText(text: String): List<InfoText> {
    val runs = mutableListOf<InfoText>()
    var written = 0
    for (match in LINK.findAll(text)) {
        if (match.range.first > written) {
            runs.add(InfoText.Plain(text.substring(written, match.range.first)))
        }
        val (label, url) = match.destructured
        runs.add(InfoText.Link(label, url))
        written = match.range.last + 1
    }
    if (written < text.length) {
        runs.add(InfoText.Plain(text.substring(written)))
    }
    return runs
}
