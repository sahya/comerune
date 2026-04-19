package com.example.comerune.speech.infrastructure.plugin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PresetNgWordsParserTest {

    // --- parseFlatWords ---

    @Test
    fun `empty string returns empty list`() {
        assertEquals(emptyList<String>(), PresetNgWordsParser.parseFlatWords(""))
    }

    @Test
    fun `blank string returns empty list`() {
        assertEquals(emptyList<String>(), PresetNgWordsParser.parseFlatWords("   \n"))
    }

    @Test
    fun `malformed JSON returns empty list`() {
        assertEquals(emptyList<String>(), PresetNgWordsParser.parseFlatWords("{not json"))
    }

    @Test
    fun `document with no categories field returns empty list`() {
        val json = """{"version":3}"""
        assertEquals(emptyList<String>(), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `v3 valid document returns all words deduplicated`() {
        val json = """
            {
              "version": 3,
              "categories": {
                "a": {
                  "policy": "blockSpeechOnly",
                  "displaySubcategory": "violence",
                  "words": ["x", "y", "x"]
                },
                "b": {
                  "policy": "blockSpeechOnly",
                  "displaySubcategory": "sexual",
                  "words": ["y", "z"]
                }
              }
            }
        """.trimIndent()
        assertEquals(listOf("x", "y", "z"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `v2 document parses the same as v3 for flat words`() {
        val json = """
            {
              "version": 2,
              "categories": {
                "a": { "words": ["a", "b"] }
              }
            }
        """.trimIndent()
        assertEquals(listOf("a", "b"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `empty and whitespace words are skipped`() {
        val json = """
            {
              "categories": {
                "a": { "words": ["ok", "", "  ", "ok2"] }
              }
            }
        """.trimIndent()
        assertEquals(listOf("ok", "ok2"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `non-string word entries are skipped`() {
        val json = """
            {
              "categories": {
                "a": { "words": ["ok", 42, null, true, "ok2"] }
              }
            }
        """.trimIndent()
        assertEquals(listOf("ok", "ok2"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `category with non-array words is skipped`() {
        val json = """
            {
              "categories": {
                "bad": { "words": "not-a-list" },
                "good": { "words": ["ok"] }
              }
            }
        """.trimIndent()
        assertEquals(listOf("ok"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `trims surrounding whitespace in words`() {
        val json = """
            {
              "categories": {
                "a": { "words": ["  hello  ", "\tworld\n"] }
              }
            }
        """.trimIndent()
        assertEquals(listOf("hello", "world"), PresetNgWordsParser.parseFlatWords(json))
    }

    @Test
    fun `preserves hiragana katakana kanji and full-width text`() {
        val json = """
            {
              "categories": {
                "a": { "words": ["ひらがな", "カタカナ", "漢字", "ＡＢＣ"] }
              }
            }
        """.trimIndent()
        assertEquals(
            listOf("ひらがな", "カタカナ", "漢字", "ＡＢＣ"),
            PresetNgWordsParser.parseFlatWords(json)
        )
    }

    // --- parseCategories ---

    @Test
    fun `parseCategories populates policy and displaySubcategory`() {
        val json = """
            {
              "version": 3,
              "categories": {
                "a": {
                  "description": "first",
                  "policy": "blockSpeechOnly",
                  "displaySubcategory": "violence",
                  "words": ["x"]
                }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json).single()
        assertEquals("a", parsed.id)
        assertEquals("first", parsed.description)
        assertEquals("blockSpeechOnly", parsed.policy)
        assertEquals("violence", parsed.displaySubcategory)
        assertEquals(listOf("x"), parsed.words)
    }

    @Test
    fun `parseCategories falls back to defaults when policy is unknown`() {
        val json = """
            {
              "categories": {
                "a": {
                  "policy": "blockNone",
                  "displaySubcategory": "violence",
                  "words": ["x"]
                }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json).single()
        assertEquals("blockSpeechOnly", parsed.policy)
    }

    @Test
    fun `parseCategories returns null subcategory on unknown or missing`() {
        val json = """
            {
              "categories": {
                "missing": { "policy": "blockSpeechOnly", "words": ["x"] },
                "unknown": {
                  "policy": "blockSpeechOnly",
                  "displaySubcategory": "violent",
                  "words": ["y"]
                }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json)
        assertEquals(2, parsed.size)
        val missing = parsed.first { it.id == "missing" }
        val unknown = parsed.first { it.id == "unknown" }
        assertNull(missing.displaySubcategory)
        assertNull(unknown.displaySubcategory)
    }

    @Test
    fun `parseCategories skips categories with non-array words`() {
        val json = """
            {
              "categories": {
                "bad": { "policy": "blockSpeechOnly", "words": "nope" },
                "good": { "policy": "blockSpeechOnly", "words": ["x"] }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json)
        assertEquals(1, parsed.size)
        assertEquals("good", parsed.single().id)
    }

    @Test
    fun `parseCategories deduplicates words within a category`() {
        val json = """
            {
              "categories": {
                "a": {
                  "policy": "blockSpeechOnly",
                  "words": ["x", "y", "x", "z", "y"]
                }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json).single()
        assertEquals(listOf("x", "y", "z"), parsed.words)
    }

    @Test
    fun `default policy constant is blockSpeechOnly`() {
        assertEquals("blockSpeechOnly", PresetNgWordsParser.DEFAULT_POLICY)
    }

    @Test
    fun `blockAll policy is recognized`() {
        val json = """
            {
              "categories": {
                "a": {
                  "policy": "blockAll",
                  "displaySubcategory": "violence",
                  "words": ["x"]
                }
              }
            }
        """.trimIndent()
        val parsed = PresetNgWordsParser.parseCategories(json).single()
        assertEquals("blockAll", parsed.policy)
    }

    @Test
    fun `empty object returns empty list`() {
        assertTrue(PresetNgWordsParser.parseCategories("{}").isEmpty())
        assertTrue(PresetNgWordsParser.parseFlatWords("{}").isEmpty())
    }
}
