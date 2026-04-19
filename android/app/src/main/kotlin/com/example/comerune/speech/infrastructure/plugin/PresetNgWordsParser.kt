package com.example.comerune.speech.infrastructure.plugin

import org.json.JSONArray
import org.json.JSONObject

/**
 * Pure static parser for `preset_ng_words.json`.
 *
 * The parser is intentionally permissive to keep startup bullet-proof:
 * - Any structural problem yields an empty list rather than an exception.
 * - Unknown `policy` / `displaySubcategory` values fall back to safe defaults.
 * - Malformed individual categories are skipped; the rest still load.
 *
 * The Kotlin side only needs the flat `List<String>` of NG words (matching the
 * v1/v2 behavior), so [parseFlatWords] is the primary API. The richer
 * structured view lives on the Dart side ([NgPresetCategory]).
 */
object PresetNgWordsParser {

    const val DEFAULT_POLICY: String = "blockSpeechOnly"

    /**
     * Parses the preset JSON and returns the deduplicated, order-preserved
     * list of NG words. Any parsing error is swallowed and an empty list is
     * returned.
     */
    fun parseFlatWords(json: String): List<String> {
        if (json.isBlank()) {
            return emptyList()
        }
        val root = try {
            JSONObject(json)
        } catch (e: Exception) {
            return emptyList()
        }
        val categories = root.optJSONObject("categories") ?: return emptyList()
        val seen = LinkedHashSet<String>()
        val keys = categories.keys()
        while (keys.hasNext()) {
            val key = keys.next() ?: continue
            val category = categories.optJSONObject(key) ?: continue
            val wordArray: JSONArray = category.optJSONArray("words") ?: continue
            for (i in 0 until wordArray.length()) {
                val raw = wordArray.opt(i) as? String ?: continue
                val trimmed = raw.trim()
                if (trimmed.isNotEmpty()) {
                    seen.add(trimmed)
                }
            }
        }
        return seen.toList()
    }

    /**
     * Parses the preset JSON and returns the per-category structured view.
     *
     * This is a richer form than [parseFlatWords] and is kept internal for now
     * because only future issues (#613/#614) need it on the Kotlin side. It is
     * exposed publicly so that JUnit tests can verify policy / subcategory
     * parsing behavior.
     */
    fun parseCategories(json: String): List<ParsedCategory> {
        if (json.isBlank()) {
            return emptyList()
        }
        val root = try {
            JSONObject(json)
        } catch (e: Exception) {
            return emptyList()
        }
        val categories = root.optJSONObject("categories") ?: return emptyList()
        val result = mutableListOf<ParsedCategory>()
        val keys = categories.keys()
        while (keys.hasNext()) {
            val key = keys.next() ?: continue
            if (key.isEmpty()) {
                continue
            }
            val category = categories.optJSONObject(key) ?: continue
            val wordArray = category.optJSONArray("words") ?: continue
            val words = LinkedHashSet<String>()
            for (i in 0 until wordArray.length()) {
                val raw = wordArray.opt(i) as? String ?: continue
                val trimmed = raw.trim()
                if (trimmed.isNotEmpty()) {
                    words.add(trimmed)
                }
            }
            val policyRaw = category.optString("policy", "")
            val policy = if (policyRaw == "blockAll" || policyRaw == "blockSpeechOnly") {
                policyRaw
            } else {
                DEFAULT_POLICY
            }
            val subcategoryRaw = category.optString("displaySubcategory", "")
            val subcategory = when (subcategoryRaw) {
                "violence", "sexual", "discrimination", "minors" -> subcategoryRaw
                else -> null
            }
            result.add(
                ParsedCategory(
                    id = key,
                    description = category.optString("description", ""),
                    policy = policy,
                    displaySubcategory = subcategory,
                    words = words.toList()
                )
            )
        }
        return result
    }

    data class ParsedCategory(
        val id: String,
        val description: String,
        val policy: String,
        val displaySubcategory: String?,
        val words: List<String>,
    )
}
