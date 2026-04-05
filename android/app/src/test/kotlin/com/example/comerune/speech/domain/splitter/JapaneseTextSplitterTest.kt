package com.example.comerune.speech.domain.splitter

import org.junit.Assert.assertEquals
import org.junit.Test

class JapaneseTextSplitterTest {

    private val splitter = JapaneseTextSplitter()

    // --- Short text should not be split ---

    @Test
    fun `short text is not split`() {
        val text = "こんにちは" // 5 chars, well below 15
        assertEquals(listOf(text), splitter.split(text))
    }

    @Test
    fun `text at minTextLength boundary is not split`() {
        // Exactly 15 code points
        val text = "あいうえおかきくけこさしすせそ"
        assertEquals(15, text.codePointCount(0, text.length))
        assertEquals(listOf(text), splitter.split(text))
    }

    @Test
    fun `text just above minTextLength boundary is split when particle present`() {
        // 16 code points with a "から" particle
        val text = "あいうえおかきくからけこさしすせそ"
        assertEquals(16, text.codePointCount(0, text.length))
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals(text, result.joinToString(""))
    }

    // --- Conjunctive particle splitting ---

    @Test
    fun `splits at kara particle`() {
        // "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ" (28 chars)
        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("でも岩国は今豪雨らしいから", result[0])
        assertEquals("これぐらいの雨でまだよかったよ", result[1])
    }

    @Test
    fun `splits at kedo particle`() {
        val text = "今日は天気よかったけどちょっと寒かったね"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("今日は天気よかったけど", result[0])
        assertEquals("ちょっと寒かったね", result[1])
    }

    @Test
    fun `splits at node particle`() {
        val text = "明日は雨が降りそうなので傘を持って行った方がいいよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("明日は雨が降りそうなので", result[0])
        assertEquals("傘を持って行った方がいいよ", result[1])
    }

    @Test
    fun `splits at noni particle`() {
        val text = "せっかく来たのにもう帰っちゃうのかよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("せっかく来たのに", result[0])
        assertEquals("もう帰っちゃうのかよ", result[1])
    }

    @Test
    fun `splits at temo particle`() {
        val text = "雨が降っても試合はやるらしいよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("雨が降っても", result[0])
        assertEquals("試合はやるらしいよ", result[1])
    }

    @Test
    fun `splits at tte particle`() {
        val text = "あの人すごいいい人だってみんな言ってるよね"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("あの人すごいいい人だって", result[0])
        assertEquals("みんな言ってるよね", result[1])
    }

    @Test
    fun `splits at shi particle`() {
        val text = "天気もいいし景色もきれいだし最高だね"
        val result = splitter.split(text)
        // "天気もいいし" (6) + "景色もきれいだし" (8) + "最高だね" (4)
        // Last chunk < 5 chars, merged with previous
        assertEquals(2, result.size)
        assertEquals("天気もいいし", result[0])
        assertEquals("景色もきれいだし最高だね", result[1])
    }

    @Test
    fun `splits at dakara particle`() {
        val text = "それはちょっと違うと思うだからもう一回考えてみて"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("それはちょっと違うと思うだから", result[0])
        assertEquals("もう一回考えてみて", result[1])
    }

    @Test
    fun `splits at keredomo particle`() {
        val text = "確かにそうかもしれないけれどもやっぱり心配だよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("確かにそうかもしれないけれども", result[0])
        assertEquals("やっぱり心配だよ", result[1])
    }

    @Test
    fun `splits at tara particle`() {
        val text = "もし明日晴れたらみんなでピクニックに行こうよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("もし明日晴れたら", result[0])
        assertEquals("みんなでピクニックに行こうよ", result[1])
    }

    @Test
    fun `splits at demo particle`() {
        val text = "ちょっと難しいかもしれないでもやってみる価値はある"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("ちょっと難しいかもしれないでも", result[0])
        assertEquals("やってみる価値はある", result[1])
    }

    @Test
    fun `splits at dakedo particle`() {
        val text = "もうちょっと待ちたいんだけど時間がないんだよね"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("もうちょっと待ちたいんだけど", result[0])
        assertEquals("時間がないんだよね", result[1])
    }

    // --- Potential false-match tests ---

    @Test
    fun `tte in itteru does not cause harmful split`() {
        // "言ってる" contains "って" but it's part of a verb, not a conjunctive particle.
        // The regex will match, but minChunkLength merging prevents harmful fragmentation.
        val text = "あの人がそう言ってるのは本当のことなんだよね"
        val result = splitter.split(text)
        // Chunks must concatenate to original
        assertEquals(text, result.joinToString(""))
        // Each chunk should be at least minChunkLength (5) code points
        for (chunk in result) {
            assert(chunk.codePointCount(0, chunk.length) >= JapaneseTextSplitter.MIN_CHUNK_LENGTH_DEFAULT) {
                "Chunk '$chunk' is shorter than minChunkLength"
            }
        }
    }

    @Test
    fun `shi in i-adjective tanoshii does not split`() {
        // "楽しい" contains "し" but it's part of an い-adjective, not a conjunctive particle
        val text = "今日のイベントは本当に楽しいからまた来たいね"
        val result = splitter.split(text)
        // Should split at "から" but NOT at "し" in "楽しい"
        assertEquals(2, result.size)
        assertEquals("今日のイベントは本当に楽しいから", result[0])
        assertEquals("また来たいね", result[1])
    }

    @Test
    fun `shi in i-adjective ureshii does not split`() {
        val text = "合格できて嬉しいけどまだまだ頑張らないとね"
        val result = splitter.split(text)
        // Should split at "けど" but NOT at "し" in "嬉しい"
        assertEquals(2, result.size)
        assertEquals("合格できて嬉しいけど", result[0])
        assertEquals("まだまだ頑張らないとね", result[1])
    }

    // --- Punctuation after particle ---

    @Test
    fun `splits at particle followed by comma`() {
        val text = "今日は天気よかったけど、ちょっと寒かったね"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("今日は天気よかったけど、", result[0])
        assertEquals("ちょっと寒かったね", result[1])
    }

    @Test
    fun `splits at kara followed by comma`() {
        val text = "でも岩国は今豪雨らしいから、これぐらいの雨でまだよかったよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("でも岩国は今豪雨らしいから、", result[0])
        assertEquals("これぐらいの雨でまだよかったよ", result[1])
    }

    @Test
    fun `splits at node followed by period`() {
        val text = "明日は雨が降りそうなので。傘を持って行った方がいいよ"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("明日は雨が降りそうなので。", result[0])
        assertEquals("傘を持って行った方がいいよ", result[1])
    }

    @Test
    fun `splits at shi followed by comma`() {
        val text = "天気もいいし、景色もきれいだし最高だね"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals("天気もいいし、", result[0])
        assertEquals("景色もきれいだし最高だね", result[1])
    }

    @Test
    fun `comma without particle does not split`() {
        // 「、」alone (after a non-particle character) should not trigger a split
        val text = "今日は暑いですね、みなさん水分補給してください"
        val result = splitter.split(text)
        assertEquals(1, result.size)
    }

    @Test
    fun `punctuation after particle preserves concatenation invariant`() {
        val texts = listOf(
            "今日は天気よかったけど、ちょっと寒かったね",
            "でも岩国は今豪雨らしいから、これぐらいの雨でまだよかったよ",
            "天気もいいし、景色もきれいだし最高だね",
            "明日は雨が降りそうなので。傘を持って行った方がいいよ"
        )
        for (text in texts) {
            val chunks = splitter.split(text)
            assertEquals(
                "Chunks must concatenate to original: $text",
                text, chunks.joinToString("")
            )
        }
    }

    // --- Case/adverbial particles should NOT split ---

    @Test
    fun `does not split at de particle`() {
        val text = "東京で大きなイベントがあるらしいよ今度行ってみたい"
        // "で" is a case particle — should not split here
        val result = splitter.split(text)
        // No conjunctive particle found → single chunk
        assertEquals(1, result.size)
    }

    @Test
    fun `does not split at ni particle`() {
        val text = "明日友達の家に遊びに行くんだけど何持っていこう"
        val result = splitter.split(text)
        // Only splits at だけど, not at に
        assertEquals(2, result.size)
        assertEquals("明日友達の家に遊びに行くんだけど", result[0])
    }

    // --- Max chunks limit ---

    @Test
    fun `limits to max 3 chunks`() {
        // Text with 4 conjunctive particles
        val text = "雨が降ってるからバスで行ったけどすごい混んでてもなんとか座れたので良かった"
        val result = splitter.split(text)
        assert(result.size <= 3) { "Expected at most 3 chunks but got ${result.size}" }
        assertEquals(text, result.joinToString(""))
    }

    // --- Punctuation priority ---

    @Test
    fun `punctuation-backed splits are preferred over particle-only when exceeding maxChunks`() {
        // maxChunks=2 → only 1 split point allowed
        // 4 candidates: から (no punct), けど、(punct), ても (no punct), ので (no punct)
        // → けど、should be selected because it has punctuation
        val splitter = JapaneseTextSplitter(maxChunks = 2, minTextLength = 5)
        val text = "雨が降ってるからバスで行ったけど、すごい混んでてもなんとか座れたので良かった"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        // The split should happen at けど、(punctuation-backed) not at から (particle-only)
        assertEquals("雨が降ってるからバスで行ったけど、", result[0])
        assertEquals("すごい混んでてもなんとか座れたので良かった", result[1])
    }

    @Test
    fun `multiple punctuation-backed splits are preferred in order`() {
        // maxChunks=3 → 2 split points allowed
        // candidates: から、(punct), けど (no punct), ので、(punct), ても (no punct)
        // → から、and ので、should be selected
        val splitter = JapaneseTextSplitter(maxChunks = 3, minTextLength = 5)
        val text = "雨だから、バスに乗ったけどすごい混んでたので、なんとか帰れたけど大変だった"
        val result = splitter.split(text)
        assertEquals(3, result.size)
        assertEquals("雨だから、", result[0])
        assertEquals("バスに乗ったけどすごい混んでたので、", result[1])
        assertEquals("なんとか帰れたけど大変だった", result[2])
    }

    @Test
    fun `all candidates without punctuation still works when exceeding maxChunks`() {
        // No punctuation at all — falls back to positional selection
        val splitter = JapaneseTextSplitter(maxChunks = 2, minTextLength = 5)
        val text = "雨が降ってるからバスで行ったけどすごい混んでてもなんとか座れた"
        val result = splitter.split(text)
        assertEquals(2, result.size)
        assertEquals(text, result.joinToString(""))
    }

    // --- Short chunk merging ---

    @Test
    fun `merges short chunks with adjacent chunks`() {
        val splitter = JapaneseTextSplitter(minChunkLength = 5, minTextLength = 10)
        // "あいうから" (5) + "かき" (2 — too short) → merge
        val text = "あいうえおからかきくけこさしすせそ"
        val result = splitter.split(text)
        // All chunks should be >= 5 code points
        for (chunk in result) {
            assert(chunk.codePointCount(0, chunk.length) >= 5) {
                "Chunk '$chunk' is shorter than minChunkLength"
            }
        }
    }

    // --- Concatenation invariant ---

    @Test
    fun `split chunks concatenate to original text`() {
        val texts = listOf(
            "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ",
            "今日は天気よかったけどちょっと寒かったね",
            "確かにそうかもしれないけれどもやっぱり心配だよ",
            "短いテスト",
            "雨が降っても試合はやるらしいよ"
        )
        for (text in texts) {
            val chunks = splitter.split(text)
            assertEquals(
                "Chunks must concatenate to original: $text",
                text, chunks.joinToString("")
            )
        }
    }

    // --- No particle → no split ---

    @Test
    fun `text without particles is not split`() {
        val text = "今日もいい天気で気持ちいいですね最高です"
        val result = splitter.split(text)
        assertEquals(1, result.size)
    }

    // --- Empty and edge cases ---

    @Test
    fun `empty text returns single empty chunk`() {
        assertEquals(listOf(""), splitter.split(""))
    }

    @Test
    fun `single character text returns single chunk`() {
        assertEquals(listOf("あ"), splitter.split("あ"))
    }

    @Test
    fun `consecutive particles in text`() {
        // Multiple particles back-to-back
        val text = "今日は忙しかったからでもなんとか終わったので帰れるよ"
        val result = splitter.split(text)
        assertEquals(text, result.joinToString(""))
        // Each chunk should be at least minChunkLength
        for (chunk in result) {
            assert(chunk.codePointCount(0, chunk.length) >= JapaneseTextSplitter.MIN_CHUNK_LENGTH_DEFAULT) {
                "Chunk '$chunk' is shorter than minChunkLength"
            }
        }
    }

    @Test
    fun `shi as conjunctive dashi splits correctly`() {
        // "だし" is a valid conjunctive particle usage (reason/cause)
        val text = "値段も安いんだし味もいいんだから行こうよ"
        val result = splitter.split(text)
        assertEquals(text, result.joinToString(""))
        // Should split at だし and/or だから — verify at least 2 chunks
        assert(result.size >= 2) { "Expected at least 2 chunks but got ${result.size}" }
    }

    @Test
    fun `shi in i-adjective utsukushii does not split`() {
        val text = "この景色は本当に美しいからまた見に来たいね"
        val result = splitter.split(text)
        // Should split at "から" but NOT at "し" in "美しい"
        assertEquals(2, result.size)
        assertEquals("この景色は本当に美しいから", result[0])
        assertEquals("また見に来たいね", result[1])
    }

    @Test
    fun `tte in motteku does not cause harmful split`() {
        // "持ってく" contains "って" but it's part of a verb
        val text = "明日は弁当を持って行くから楽しみにしてるよ"
        val result = splitter.split(text)
        assertEquals(text, result.joinToString(""))
        for (chunk in result) {
            assert(chunk.codePointCount(0, chunk.length) >= JapaneseTextSplitter.MIN_CHUNK_LENGTH_DEFAULT) {
                "Chunk '$chunk' is shorter than minChunkLength"
            }
        }
    }

    @Test
    fun `particle at end of text does not produce empty trailing chunk`() {
        // "から" at end — lookahead `(?=.)` prevents matching at text end
        val text = "これは長い文章のテストだから"
        val result = splitter.split(text)
        assertEquals(1, result.size)
        for (chunk in result) {
            assert(chunk.isNotEmpty()) { "Empty chunk found" }
        }
    }

    @Test
    fun `moshi does not cause harmful split due to minChunkLength`() {
        // "もし" matches SHI_PARTICLE_PATTERN, but "もし" is only 2 chars
        // and will be merged by minChunkLength (5) guard
        val text = "もし明日天気がよかったらみんなで出かけようよ"
        val result = splitter.split(text)
        assertEquals(text, result.joinToString(""))
        for (chunk in result) {
            assert(chunk.codePointCount(0, chunk.length) >= JapaneseTextSplitter.MIN_CHUNK_LENGTH_DEFAULT) {
                "Chunk '$chunk' is shorter than minChunkLength"
            }
        }
    }

    // --- Custom configuration ---

    @Test
    fun `multiple particles exceeding maxChunks merges trailing into last chunk`() {
        // 5 potential split points — all should merge into at most 3 chunks
        val text = "雨だからバスに乗ったけど混んでてもなんとかなったので帰れたし良かった"
        val result = splitter.split(text)
        assert(result.size <= 3) { "Expected at most 3 chunks but got ${result.size}" }
        assertEquals(text, result.joinToString(""))
        // Verify trailing chunks are merged, not discarded
        assert(result.last().isNotEmpty()) { "Last chunk should not be empty" }
    }

    @Test
    fun `particle only text with no surrounding content returns single chunk`() {
        // "から" alone is 2 chars — well below minTextLength
        val text = "から"
        assertEquals(listOf(text), splitter.split(text))
    }

    @Test
    fun `custom minTextLength controls split threshold`() {
        val splitter = JapaneseTextSplitter(minTextLength = 30)
        // 20 chars — below threshold
        val text = "今日は天気よかったけどちょっと寒かったね"
        assertEquals(listOf(text), splitter.split(text))
    }

    @Test
    fun `custom maxChunks limits output`() {
        val splitter = JapaneseTextSplitter(maxChunks = 2, minTextLength = 5)
        val text = "雨が降ってるからバスで行ったけどすごい混んでたので大変だった"
        val result = splitter.split(text)
        assert(result.size <= 2) { "Expected at most 2 chunks but got ${result.size}" }
        assertEquals(text, result.joinToString(""))
    }
}
