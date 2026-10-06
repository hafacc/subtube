package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** The largest whole number a device file may hold: JavaScript's largest safe integer. */
internal const val MAX_SAFE_INTEGER: Long = 9007199254740991L

/** A JSON string's text; null for anything else. */
internal fun JsonElement?.stringOrNull(): String? = (this as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content

/** A JSON `true` or `false`; null for anything else, the strings "true" and "false" too. */
internal fun JsonElement?.booleanValue(): Boolean? = (this as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.booleanOrNull

/** The strings of an array holding nothing else; null for anything other than that. */
internal fun JsonElement?.stringsOrNull(): List<String>? =
    (this as? JsonArray)?.map { element -> element.stringOrNull() }?.takeIf { all -> null !in all }?.filterNotNull()
