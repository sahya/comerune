# 読み上げ整形 → VOICEVOX Core で端末内合成 → Android 音声再生 詳細仕様

## 1. 対象範囲

本仕様は、ニコニココメント取得後の以下処理を対象とする。

1. 読み上げ整形
2. [VOICEVOX Core](https://github.com/VOICEVOX/voicevox_core) による端末内音声合成
3. Android での音声再生

コメント取得処理、認証処理、画面 UI、配信連携処理は対象外とする。

### 参考リンク

* 実装例: [VOICEVOX Mobile](https://github.com/VOICEVOX/voicevox_mobile)
* SDK: [VOICEVOX Core](https://github.com/VOICEVOX/voicevox_core)

---

## 2. 全体処理フロー

```text
[取得済みコメント]
   ↓
[読み上げ対象判定]
   ↓
[読み上げ整形]
   ↓
[読み上げキューへ投入]
   ↓
[VOICEVOX Core で WAV 合成]
   ↓
[Android 音声再生]
   ↓
[再生完了後に次コメント処理]
```

### 2.1 基本方針

* コメントは逐次処理する
* 同時に複数コメントを再生しない
* 合成と再生はキュー制御する
* 長文やノイズは整形時点で抑制する
* 遅延悪化を防ぐため、必要に応じてコメントを間引く

---

## 3. 読み上げ整形

## 3.1 目的

コメント本文を、そのまま読ませると聞きづらい形式から、**短く・自然で・事故りにくい形式**へ変換する。

## 3.2 入力

```kotlin
data class RawComment(
    val id: String,
    val text: String,
    val userId: String?,
    val postedAtEpochMs: Long,
    val score: Int?,
    val isOwner: Boolean = false
)
```

## 3.3 出力

```kotlin
data class NormalizedComment(
    val id: String,
    val originalText: String,
    val normalizedText: String,
    val priority: Int = 0,
    val skipReason: String? = null
)
```

---

## 3.4 読み上げ対象判定

### 読み上げする条件

* 空文字ではない
* NGワードに一致しない
* 記号だけではない
* URL だけではない
* 長すぎない
* 直前コメントと重複しすぎない

### 読み上げしない条件

* 空白のみ
* 絵文字・記号のみ
* `w` や `8888` だけなど短いノイズのみ
* URL のみ
* 同一内容の連投
* システム都合で省略対象になったコメント

---

## 3.5 整形ルール

## 3.5.1 前処理

以下を順に適用する。

1. 改行を空白に変換
2. タブを空白に変換
3. 連続空白を1つに圧縮
4. 前後空白を trim
5. 制御文字を除去

例:

```text
"  こんにちは\n\nすごい\tですね  "
→ "こんにちは すごい ですね"
→ "こんにちは すごい ですね"
```

---

## 3.5.2 URL の扱い

URL は全文を読ませない。

変換規則:

* URL を含む場合 → `"URL省略"` に置換
* URL のみの場合 → スキップ可

例:

```text
"https://example.com/test"
→ "URL省略"

"これ見て https://example.com/test"
→ "これ見て URL省略"
```

正規表現例:

```regex
https?://[\\w/:%#\\$&\\?\\(\\)~\\.=\\+\\-]+
```

---

## 3.5.3 長い記号の圧縮

連続記号はそのまま読ませない。

対象例:

* `wwwww`
* `!!!!!!`
* `?????`
* `ーーーー`
* `～～～～`

変換例:

```text
"wwwww" → "わら"
"草草草" → "くさ"
"888888" → "はちはちはち" ではなく "はくしゅ"
"!!!!!!" → "びっくり"
```

推奨変換表:

| パターン       | 変換後  |
| ---------- | ---- |
| `w{2,}`    | わら   |
| `草{2,}`    | くさ   |
| `8{3,}`    | はくしゅ |
| `!{2,}`    | びっくり |
| `\\?{2,}`  | はてな  |
| `[ー～]{3,}` | のばし  |

---

## 3.5.4 絵文字・顔文字の扱い

絵文字や複雑な顔文字は読みづらいため抑制する。

方針:

* 単独絵文字のみ → スキップ
* 文中の絵文字 → 削除または `"えもじ"` に置換
* 複雑な顔文字 → 削除

例:

```text
"😊😊😊" → スキップ
"ありがとう😊" → "ありがとう"
"( ;∀;)" → 削除
```

---

## 3.5.5 文字数制限

長文コメントは全文を読ませない。

推奨制限:

* 整形後 40〜60 文字以内
* 60 文字超過時は切り詰め

例:

```text
"今日は本当に長い文章でたくさん書きたいことがあって..."
→ "今日は本当に長い文章でたくさん書きたいことが、以下省略"
```

推奨仕様:

* 最大読み上げ文字数: `50`
* 超過時の末尾付与: `"、以下省略"`

---

## 3.5.6 辞書置換

ニコニコ文化や固有用語を読みやすく置換する。

例:

| 入力     | 読み   |
| ------ | ---- |
| `初見`   | しょけん |
| `うぽつ`  | うぽつ  |
| `乙`    | おつ   |
| `kwsk` | くわしく |
| `www`  | わら   |
| `8888` | はくしゅ |

辞書はアプリ設定で拡張可能にする。

```kotlin
data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
```

---

## 3.5.7 NGワード・禁止語

一致した場合は以下のいずれかを行う。

* コメント自体をスキップ
* 該当単語のみ `"ピー"` に置換

推奨:

* 初期実装はスキップ
* 将来 `"ピー"` 音差し込み拡張を想定

---

## 3.5.8 重複抑制

直近コメントと同一または高類似ならスキップする。

推奨条件:

* 完全一致: スキップ
* 5秒以内かつ同一整形結果: スキップ
* 同一ユーザーの短時間連投: 2件目以降を抑制

---

## 3.6 整形関数仕様

```kotlin
interface CommentNormalizer {
    fun normalize(raw: RawComment): NormalizedComment
}
```

戻り値ルール:

* `skipReason != null` の場合は読み上げ対象外
* `normalizedText.isBlank()` の場合も対象外

---

## 4. VOICEVOX Core で端末内合成

## 4.1 目的

整形済みテキストを、Android 端末内で WAV 音声へ変換する。

## 4.2 基本方針

* Flutter から直接 VOICEVOX Core を触らない
* Android ネイティブ層に TTS モジュールを実装する
* Flutter とは Platform Channel で連携する
* 合成は1件ずつ順次実行する

---

## 4.3 構成

```text
Flutter
  ↓ MethodChannel / EventChannel
Android Native (Kotlin)
  ↓
VOICEVOX Core Wrapper
  ↓
VVM / OpenJTalk辞書 / Coreライブラリ
  ↓
WAV byte array
```

---

## 4.4 初期化仕様

### 初期化タイミング

* アプリ起動時または初回読み上げ開始時
* 一度初期化したらアプリ実行中は再利用

### 初期化処理

1. Core ライブラリロード
2. OpenJTalk 辞書ロード
3. 話者モデル VVM ロード
4. Synthesizer インスタンス生成

### 状態

```kotlin
enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    SYNTHESIZING,
    ERROR
}
```

---

## 4.5 合成パラメータ

```kotlin
data class SpeechRequest(
    val text: String,
    val speakerId: Int,
    val speedScale: Float = 1.0f,
    val pitchScale: Float = 0.0f,
    val intonationScale: Float = 1.0f,
    val volumeScale: Float = 1.0f,
    val prePhonemeLength: Float = 0.1f,
    val postPhonemeLength: Float = 0.1f
)
```

### 初期値方針

コメント読み上げ用途では、まず以下を推奨:

* speedScale: `1.15`
* pitchScale: `0.0`
* intonationScale: `1.0`
* volumeScale: `1.0`

理由:

* 通常速度だとコメント処理が詰まりやすい
* 速すぎると聞き取りづらい
* 初期段階では感情表現より可読性優先

---

## 4.6 合成API仕様

```kotlin
interface VoicevoxSynthesizer {
    suspend fun initialize(): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<ByteArray>
    fun release()
}
```

### `synthesize()` の仕様

入力:

* 整形済みテキスト
* 話者ID
* 調整パラメータ

出力:

* WAV バイト列

エラー:

* 未初期化
* モデル未ロード
* 空文字入力
* 内部例外
* メモリ不足

---

## 4.7 合成処理シーケンス

```text
[NormalizedComment]
   ↓
SpeechRequest 作成
   ↓
VOICEVOX Core synthesize
   ↓
WAV ByteArray 生成
   ↓
再生キューへ受け渡し
```

### 合成失敗時

* 当該コメントのみ破棄
* エラーログ出力
* 次コメント処理へ進む
* エラー継続時のみエンジン再初期化を試行

---

## 4.8 キュー制御

### キュー仕様

```kotlin
data class SpeechQueueItem(
    val commentId: String,
    val text: String,
    val priority: Int,
    val createdAt: Long
)
```

### 制御ルール

* FIFO が基本
* 最大キュー件数を持つ
* あふれた場合は古い低優先度コメントを破棄
* 再生中にキューが増えても1件ずつ処理

推奨:

* 最大キュー長: `20`
* キュー過多時: `priority` の低いものから削除
* 同一文面重複は投入しない

---

## 4.9 パフォーマンス要件

* 短文コメント 1件あたりの合成開始待ちを最小化する
* コメント到着集中時もアプリクラッシュしない
* メモリ使用量急増を防ぐ

### 最初の実装で守るべき制約

* 同時合成しない
* 生成WAVを長時間保持しない
* 再生後すぐ破棄する
* 長文は整形で切る

---

## 5. Android 音声再生

## 5.1 目的

VOICEVOX Core が生成した WAV を Android 端末上で確実に再生する。

## 5.2 再生方式

初期実装は以下のどちらか。

### 方式A: 一時ファイル保存 + MediaPlayer

利点:

* 実装が簡単
* デバッグしやすい

欠点:

* ファイルI/Oが入る
* 大量コメント時にやや非効率

### 方式B: PCM / WAV をメモリ上で展開して AudioTrack

利点:

* 低遅延
* ファイルI/O不要

欠点:

* 実装が少し複雑

### 推奨

* PoC / 初期版: `MediaPlayer`
* 本番改善版: `AudioTrack`

---

## 5.3 再生インターフェース

```kotlin
interface SpeechPlayer {
    suspend fun playWavBytes(wavBytes: ByteArray): Result<Unit>
    fun stop()
    fun release()
}
```

---

## 5.4 再生状態

```kotlin
enum class PlayerState {
    IDLE,
    PLAYING,
    STOPPED,
    ERROR
}
```

---

## 5.5 再生シーケンス

```text
[WAV ByteArray]
   ↓
再生開始
   ↓
再生中状態へ遷移
   ↓
再生完了コールバック受信
   ↓
次のキューを処理
```

### 再生完了後

* 再生済みデータをメモリから解放
* 次のコメント合成または再生へ遷移

---

## 5.6 音声再生制御仕様

### stop

* 現在再生中の音声を停止
* キューを維持するか破棄するかは呼び出し元オプションで決める

### skip

* 現在再生中のコメントを打ち切り
* 次コメントへ進む

### clearQueue

* 未再生キューを全削除

---

## 5.7 Audio Focus

他アプリとの競合を考慮し、Audio Focus を取得する。

方針:

* 読み上げ開始時に `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` を検討
* フォーカス喪失時は停止または音量抑制
* 初期版ではまず単純停止でも可

---

## 5.8 音量

* 再生音量はアプリ内設定値を持つ
* Android システム音量に従う
* 合成側 `volumeScale` とプレイヤー音量は分けて管理する

---

## 6. 統合制御仕様

## 6.1 Orchestrator

整形・合成・再生をまとめる制御コンポーネントを置く。

```kotlin
interface CommentSpeechOrchestrator {
    suspend fun submit(rawComment: RawComment)
    fun stopCurrent()
    fun clearQueue()
}
```

### 処理内容

`submit()` 時:

1. normalize
2. skip 判定
3. queue 追加
4. アイドルなら処理開始
5. 合成
6. 再生
7. 完了後に次を処理

---

## 6.2 疑似コード

```kotlin
suspend fun submit(raw: RawComment) {
    val normalized = normalizer.normalize(raw)

    if (normalized.skipReason != null) return
    if (normalized.normalizedText.isBlank()) return

    queue.offer(
        SpeechQueueItem(
            commentId = normalized.id,
            text = normalized.normalizedText,
            priority = normalized.priority,
            createdAt = System.currentTimeMillis()
        )
    )

    if (!isProcessing) {
        processQueue()
    }
}

private suspend fun processQueue() {
    isProcessing = true
    try {
        while (queue.isNotEmpty()) {
            val item = queue.poll()

            val synthResult = synthesizer.synthesize(
                SpeechRequest(
                    text = item.text,
                    speakerId = currentSpeakerId,
                    speedScale = currentSpeed
                )
            )

            if (synthResult.isFailure) continue

            val wavBytes = synthResult.getOrThrow()
            player.playWavBytes(wavBytes)
        }
    } finally {
        isProcessing = false
    }
}
```

---

## 7. Flutter との責務分離

## Flutter 側

* コメント取得
* 設定UI
* NGワード設定
* 辞書設定
* 話者選択
* ON/OFF 切替
* 読み上げ対象の有効化制御

## Android ネイティブ側

* コメント整形本体
* VOICEVOX Core 初期化
* 音声合成
* キュー制御
* 音声再生
* 音声リソース解放

### 理由

この3処理はリアルタイム性と Android ネイティブ資源制御が重要であり、Flutter Dart 側へ寄せすぎると遅延と複雑性が増えるため。

---

## 8. 初期パラメータ推奨値

| 項目                |  推奨値 |
| ----------------- | ---: |
| 最大読み上げ文字数         |   50 |
| 最大キュー件数           |   20 |
| 同一文面重複抑止時間        |   5秒 |
| 読み上げ速度            | 1.15 |
| prePhonemeLength  |  0.1 |
| postPhonemeLength |  0.1 |

---

## 9. 最初に実装しないもの

初期版では以下は対象外としてよい。

* 感情パラメータの高度制御
* コメント優先度の複雑な重み付け
* 複数話者自動切替
* 単語単位のイントネーション調整
* ピー音差し込み
* バックグラウンドサービス最適化の完成版
* 再生中の動的音量ミキシング

---

## 10. 受け入れ条件

### 読み上げ整形

* URL を全文読みしない
* 記号連打を自然な短語へ変換できる
* 長文を制限できる
* 同一コメント連投を抑止できる

### 音声合成

* 整形済み短文を VOICEVOX Core で合成できる
* 端末オフラインでも動作する
* 話者ID指定で音声変更できる

### 音声再生

* 1コメントずつ順番に再生される
* 再生完了後に次コメントへ進む
* 停止・キュー削除ができる
* クラッシュせず継続動作する

---

では、実装に直結する形で書きます。
対象は次の2つです。

1. **Kotlin 側クラス設計**
2. **Flutter `MethodChannel` / `EventChannel` API 定義**

---

# 1. 全体アーキテクチャ

```text
Flutter UI / Comment Source
    ↓
MethodChannel: submitComment, start, stop, updateSettings...
    ↓
Android Plugin (Kotlin)
    ├─ CommentSpeechPlugin
    ├─ SpeechController
    ├─ CommentNormalizer
    ├─ SpeechQueueManager
    ├─ VoicevoxEngine
    ├─ WavPlayer
    └─ SettingsRepository
    ↓
VOICEVOX Core
    ↓
AudioTrack / MediaPlayer
```

---

# 2. Kotlin 側クラス設計

## 2.1 `CommentSpeechPlugin`

Flutter からの入口です。
`MethodCallHandler` と `EventChannel.StreamHandler` を持ちます。

### 責務

* Flutter 呼び出しの受付
* 引数バリデーション
* `SpeechController` 呼び出し
* 状態イベントの Flutter 返却

### 主要メソッド

```kotlin
class CommentSpeechPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    override fun onMethodCall(call: MethodCall, result: Result)
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?)
    override fun onCancel(arguments: Any?)
}
```

---

## 2.2 `SpeechController`

全体のオーケストレーターです。
このクラスが中心です。

### 責務

* コメント受信
* 整形
* キュー投入
* 合成
* 再生
* エラー時リカバリ
* 状態通知

### 依存

```kotlin
class SpeechController(
    private val normalizer: CommentNormalizer,
    private val queueManager: SpeechQueueManager,
    private val engine: VoicevoxEngine,
    private val player: WavPlayer,
    private val settingsRepository: SettingsRepository,
    private val eventEmitter: SpeechEventEmitter
)
```

### 公開API

```kotlin
interface SpeechController {
    suspend fun initialize(): Result<Unit>
    suspend fun submitComment(rawComment: RawComment): Result<SubmitResult>
    suspend fun start(): Result<Unit>
    suspend fun stop(clearQueue: Boolean = false): Result<Unit>
    suspend fun skip(): Result<Unit>
    suspend fun clearQueue(): Result<Unit>
    suspend fun updateSettings(settings: SpeechSettings): Result<Unit>
    suspend fun getStatus(): SpeechRuntimeStatus
    fun release()
}
```

---

## 2.3 `CommentNormalizer`

コメント整形専用です。

### 責務

* スキップ判定
* URL 除去
* 記号圧縮
* 辞書置換
* 長文制限
* 重複抑制前の基本整形

### API

```kotlin
interface CommentNormalizer {
    fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment
}
```

### 実装候補

```kotlin
class DefaultCommentNormalizer(
    private val textSanitizer: TextSanitizer,
    private val dictionaryReplacer: DictionaryReplacer,
    private val duplicateDetector: DuplicateDetector
) : CommentNormalizer
```

---

## 2.4 `SpeechQueueManager`

再生待ちキュー管理専用です。

### 責務

* FIFO 管理
* 最大件数制御
* 優先度付き破棄
* 重複投入抑止
* 現在件数取得

### API

```kotlin
interface SpeechQueueManager {
    fun offer(item: SpeechQueueItem): QueueOfferResult
    fun poll(): SpeechQueueItem?
    fun peek(): SpeechQueueItem?
    fun clear()
    fun size(): Int
    fun isEmpty(): Boolean
}
```

### 実装候補

```kotlin
class InMemorySpeechQueueManager(
    private val maxSize: Int
) : SpeechQueueManager
```

---

## 2.5 `VoicevoxEngine`

VOICEVOX Core ラッパーです。

### 責務

* Core 初期化
* OpenJTalk 辞書ロード
* VVM モデルロード
* テキスト合成
* エンジン解放

### API

```kotlin
interface VoicevoxEngine {
    suspend fun initialize(config: VoicevoxConfig): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult>
    fun isReady(): Boolean
    fun release()
}
```

### 補助データ

```kotlin
data class VoicevoxConfig(
    val openJtalkDictDir: String,
    val modelDir: String,
    val defaultSpeakerId: Int
)

data class WavSynthesisResult(
    val wavBytes: ByteArray,
    val text: String,
    val durationEstimateMs: Long?
)
```

### 実装候補

```kotlin
class VoicevoxEngineImpl : VoicevoxEngine
```

---

## 2.6 `WavPlayer`

WAV 再生担当です。

### 責務

* WAV 再生
* 停止
* 再生完了通知
* Audio Focus 制御
* リソース解放

### API

```kotlin
interface WavPlayer {
    suspend fun play(wavBytes: ByteArray): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isPlaying(): Boolean
    fun release()
}
```

### 実装候補

* 初期版: `MediaPlayerWavPlayer`
* 改善版: `AudioTrackWavPlayer`

---

## 2.7 `SettingsRepository`

設定の保持です。

### 責務

* 現在設定の保存
* 読み出し
* デフォルト設定の提供

### API

```kotlin
interface SettingsRepository {
    suspend fun get(): SpeechSettings
    suspend fun save(settings: SpeechSettings)
}
```

### 実装候補

```kotlin
class DataStoreSettingsRepository(
    private val dataStore: DataStore<Preferences>
) : SettingsRepository
```

---

## 2.8 `SpeechEventEmitter`

Flutter 向けイベント送信です。

### 責務

* 状態変化通知
* エラー通知
* キュー件数通知
* 再生開始・完了通知

### API

```kotlin
interface SpeechEventEmitter {
    fun emit(event: SpeechEvent)
}
```

---

# 3. Kotlin データモデル

## 3.1 コメント系

```kotlin
data class RawComment(
    val id: String,
    val text: String,
    val userId: String?,
    val postedAtEpochMs: Long,
    val score: Int? = null,
    val isOwner: Boolean = false
)

data class NormalizedComment(
    val id: String,
    val originalText: String,
    val normalizedText: String,
    val priority: Int = 0,
    val skipReason: String? = null
)

data class SpeechQueueItem(
    val commentId: String,
    val text: String,
    val priority: Int,
    val createdAt: Long
)
```

## 3.2 設定系

```kotlin
data class SpeechSettings(
    val enabled: Boolean = true,
    val speakerId: Int = 0,
    val speedScale: Float = 1.15f,
    val pitchScale: Float = 0.0f,
    val intonationScale: Float = 1.0f,
    val volumeScale: Float = 1.0f,
    val prePhonemeLength: Float = 0.1f,
    val postPhonemeLength: Float = 0.1f,
    val maxTextLength: Int = 50,
    val maxQueueSize: Int = 20,
    val duplicateWindowMs: Long = 5000L,
    val skipEmojiOnly: Boolean = true,
    val skipUrlOnly: Boolean = true,
    val replaceUrlWith: String = "URL省略",
    val trimLongTextSuffix: String = "、以下省略",
    val dictionaryRules: List<ReplaceRule> = emptyList(),
    val ngWords: List<String> = emptyList()
)

data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
```

## 3.3 リクエスト・レスポンス系

```kotlin
data class SpeechRequest(
    val text: String,
    val speakerId: Int,
    val speedScale: Float,
    val pitchScale: Float,
    val intonationScale: Float,
    val volumeScale: Float,
    val prePhonemeLength: Float,
    val postPhonemeLength: Float
)

data class SubmitResult(
    val accepted: Boolean,
    val skipped: Boolean,
    val normalizedText: String?,
    val skipReason: String?,
    val queueSize: Int
)
```

## 3.4 状態系

```kotlin
enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    SYNTHESIZING,
    ERROR
}

enum class PlayerState {
    IDLE,
    PLAYING,
    STOPPED,
    ERROR
}

data class SpeechRuntimeStatus(
    val enabled: Boolean,
    val engineState: TtsEngineState,
    val playerState: PlayerState,
    val queueSize: Int,
    val currentCommentId: String?,
    val currentText: String?,
    val currentSpeakerId: Int
)
```

---

# 4. Flutter Channel 設計

## 4.1 Channel 名

```text
MethodChannel: jp.example.comment_speech/methods
EventChannel : jp.example.comment_speech/events
```

---

## 4.2 MethodChannel 一覧

## `initialize`

### 用途

VOICEVOX Core 初期化

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `start`

### 用途

読み上げ処理開始

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `stop`

### 用途

現在再生停止

### Flutter → Native

```json
{
  "clearQueue": false
}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `skip`

### 用途

現在の1件を飛ばす

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `clearQueue`

### 用途

未再生キュー削除

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `submitComment`

### 用途

取得済みコメントを投入

### Flutter → Native

```json
{
  "id": "comment-123",
  "text": "こんにちはwwww",
  "userId": "user-1",
  "postedAtEpochMs": 1710000000000,
  "score": 10,
  "isOwner": false
}
```

### Native → Flutter

```json
{
  "accepted": true,
  "skipped": false,
  "normalizedText": "こんにちは わら",
  "skipReason": null,
  "queueSize": 3
}
```

---

## `updateSettings`

### 用途

読み上げ設定更新

### Flutter → Native

```json
{
  "enabled": true,
  "speakerId": 0,
  "speedScale": 1.15,
  "pitchScale": 0.0,
  "intonationScale": 1.0,
  "volumeScale": 1.0,
  "prePhonemeLength": 0.1,
  "postPhonemeLength": 0.1,
  "maxTextLength": 50,
  "maxQueueSize": 20,
  "duplicateWindowMs": 5000,
  "skipEmojiOnly": true,
  "skipUrlOnly": true,
  "replaceUrlWith": "URL省略",
  "trimLongTextSuffix": "、以下省略",
  "dictionaryRules": [
    {
      "pattern": "w{2,}",
      "replacement": "わら",
      "enabled": true
    }
  ],
  "ngWords": ["NG例"]
}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

## `getStatus`

### 用途

現在状態取得

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "enabled": true,
  "engineState": "READY",
  "playerState": "IDLE",
  "queueSize": 2,
  "currentCommentId": null,
  "currentText": null,
  "currentSpeakerId": 0
}
```

---

## `release`

### 用途

リソース解放

### Flutter → Native

```json
{}
```

### Native → Flutter

```json
{
  "ok": true
}
```

---

# 5. EventChannel イベント仕様

Flutter 側は購読して状態変化を受け取ります。

## イベント共通形式

```json
{
  "type": "queue_updated",
  "payload": {}
}
```

---

## 5.1 `engine_state_changed`

```json
{
  "type": "engine_state_changed",
  "payload": {
    "state": "READY"
  }
}
```

## 5.2 `queue_updated`

```json
{
  "type": "queue_updated",
  "payload": {
    "size": 4
  }
}
```

## 5.3 `comment_skipped`

```json
{
  "type": "comment_skipped",
  "payload": {
    "commentId": "comment-123",
    "reason": "emoji_only"
  }
}
```

## 5.4 `speech_started`

```json
{
  "type": "speech_started",
  "payload": {
    "commentId": "comment-123",
    "text": "こんにちは わら"
  }
}
```

## 5.5 `speech_completed`

```json
{
  "type": "speech_completed",
  "payload": {
    "commentId": "comment-123"
  }
}
```

## 5.6 `speech_failed`

```json
{
  "type": "speech_failed",
  "payload": {
    "commentId": "comment-123",
    "message": "synthesis failed"
  }
}
```

## 5.7 `player_state_changed`

```json
{
  "type": "player_state_changed",
  "payload": {
    "state": "PLAYING"
  }
}
```

## 5.8 `error`

```json
{
  "type": "error",
  "payload": {
    "code": "ENGINE_NOT_INITIALIZED",
    "message": "VOICEVOX engine is not initialized"
  }
}
```

---

# 6. Flutter 側ラッパー設計

## 6.1 Dart API

```dart
abstract class CommentSpeechPlatform {
  Future<void> initialize();
  Future<void> start();
  Future<void> stop({bool clearQueue = false});
  Future<void> skip();
  Future<void> clearQueue();
  Future<SubmitResult> submitComment(RawComment comment);
  Future<void> updateSettings(SpeechSettings settings);
  Future<SpeechRuntimeStatus> getStatus();
  Future<void> release();
  Stream<SpeechEvent> get events;
}
```

---

## 6.2 実装例

```dart
class MethodChannelCommentSpeech implements CommentSpeechPlatform {
  static const _method = MethodChannel('jp.example.comment_speech/methods');
  static const _events = EventChannel('jp.example.comment_speech/events');

  @override
  Stream<SpeechEvent> get events =>
      _events.receiveBroadcastStream().map((e) => SpeechEvent.fromMap(Map<String, dynamic>.from(e)));
}
```

---

# 7. MethodCall ごとの Native 実装方針

## `submitComment`

内部フロー:

1. JSON を `RawComment` に変換
2. `SpeechController.submitComment()` 呼び出し
3. `SubmitResult` を `Map<String, Any?>` にして返却

## `updateSettings`

内部フロー:

1. JSON を `SpeechSettings` に変換
2. `SpeechController.updateSettings()` 呼び出し
3. キューサイズ変更があれば QueueManager へ反映

## `initialize`

内部フロー:

1. `SpeechController.initialize()`
2. `VoicevoxEngine.initialize()`
3. `READY` イベント送出

---

# 8. エラーコード設計

```text
INVALID_ARGUMENT
ENGINE_NOT_INITIALIZED
ENGINE_INITIALIZATION_FAILED
MODEL_LOAD_FAILED
SYNTHESIS_FAILED
PLAYER_FAILED
QUEUE_FULL
COMMENT_SKIPPED
INTERNAL_ERROR
```

Flutter 側には `PlatformException` で返すか、通常レスポンス + Event 通知のどちらかに統一します。
おすすめは次です。

* **操作失敗**: `PlatformException`
* **コメント個別失敗**: `speech_failed` イベント
* **スキップ**: 正常レスポンス + `skipped=true`

---

# 9. 非同期制御方針

ここはかなり重要です。
雑に実装すると二重再生や race condition が出ます。

## 推奨

* `SpeechController` に **単一 CoroutineScope**
* キュー処理は **1本の worker**
* `Mutex` または actor 的設計で逐次化

### イメージ

```kotlin
private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
private val processMutex = Mutex()
private var isRunning = false
```

### worker 起動条件

* `submitComment()` 時に `isRunning == false` なら起動
* worker がキューを空にしたら終了
* 再度コメントが来たら再起動

---

# 10. 推奨ディレクトリ構成

## Android

```text
android/src/main/kotlin/jp/example/comment_speech/
  CommentSpeechPlugin.kt
  controller/
    SpeechController.kt
    SpeechControllerImpl.kt
  domain/
    model/
      RawComment.kt
      NormalizedComment.kt
      SpeechSettings.kt
      SpeechRequest.kt
      SpeechRuntimeStatus.kt
    normalizer/
      CommentNormalizer.kt
      DefaultCommentNormalizer.kt
      TextSanitizer.kt
      DictionaryReplacer.kt
      DuplicateDetector.kt
    queue/
      SpeechQueueManager.kt
      InMemorySpeechQueueManager.kt
    engine/
      VoicevoxEngine.kt
      VoicevoxEngineImpl.kt
    player/
      WavPlayer.kt
      MediaPlayerWavPlayer.kt
      AudioTrackWavPlayer.kt
  infra/
    SettingsRepository.kt
    DataStoreSettingsRepository.kt
    SpeechEventEmitter.kt
```

## Flutter

```text
lib/
  comment_speech.dart
  src/
    method_channel_comment_speech.dart
    models/
      raw_comment.dart
      submit_result.dart
      speech_settings.dart
      speech_runtime_status.dart
      speech_event.dart
```

---

# 11. 最初の実装順

順番はこれが安全です。

### Step 1

* `initialize`
* `submitComment`
* `normalize`
* `synthesize`
* `play`
* 1件だけ再生

### Step 2

* キュー制御
* `skip`
* `clearQueue`
* 状態イベント

### Step 3

* 設定更新
* 辞書置換
* 重複抑制
* NGワード

### Step 4

* `AudioTrack` 化
* Foreground Service 対応
* パフォーマンス改善

---

# 12. 実装上の注意

## Flutter 側に寄せすぎない

整形・合成・再生の中心を Dart 側へ置くと、後で遅延と保守コストが増えます。
**Flutter は UI とコメント受け渡し中心**が安全です。

## `submitComment` は fire-and-forget に近くする

コメント到着頻度が高いので、毎回重い同期処理を返す設計は避けた方がよいです。
返すのは最小限で十分です。

## 初期版は `MediaPlayer`

本番は `AudioTrack` に寄せたくなりますが、最初からそこへ行くと不具合点が増えます。

---

では、**そのまま Android 側に置き始められる最小スケルトン**をまとめます。
対象は Flutter プラグインの **Kotlin 側** です。

構成は次です。

* `CommentSpeechPlugin.kt`
* `SpeechController.kt`
* `SpeechControllerImpl.kt`
* `model` 一式
* `normalizer` 最小実装
* `queue` 最小実装
* `engine` interface + 仮実装
* `player` interface + 仮実装
* `event` emitter

まだ **VOICEVOX Core の実結線部分** と **WAV 実再生の詳細** はダミーにしてあります。
先に全体の依存関係を固めるためです。

---

## 1. `CommentSpeechPlugin.kt`

```kotlin
package jp.example.comment_speech

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import jp.example.comment_speech.controller.SpeechController
import jp.example.comment_speech.controller.SpeechControllerImpl
import jp.example.comment_speech.domain.engine.VoicevoxEngineImpl
import jp.example.comment_speech.domain.event.FlutterSpeechEventEmitter
import jp.example.comment_speech.domain.model.RawComment
import jp.example.comment_speech.domain.model.ReplaceRule
import jp.example.comment_speech.domain.model.SpeechSettings
import jp.example.comment_speech.domain.normalizer.DefaultCommentNormalizer
import jp.example.comment_speech.domain.player.MediaPlayerWavPlayer
import jp.example.comment_speech.domain.queue.InMemorySpeechQueueManager
import jp.example.comment_speech.infra.InMemorySettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class CommentSpeechPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var eventSink: EventChannel.EventSink? = null
    private lateinit var controller: SpeechController

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "jp.example.comment_speech/methods")
        eventChannel = EventChannel(binding.binaryMessenger, "jp.example.comment_speech/events")

        val eventEmitter = FlutterSpeechEventEmitter { event ->
            eventSink?.success(event)
        }

        val settingsRepository = InMemorySettingsRepository()
        val normalizer = DefaultCommentNormalizer()
        val queueManager = InMemorySpeechQueueManager(maxSize = 20)
        val engine = VoicevoxEngineImpl(binding.applicationContext)
        val player = MediaPlayerWavPlayer(binding.applicationContext)

        controller = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queueManager,
            engine = engine,
            player = player,
            settingsRepository = settingsRepository,
            eventEmitter = eventEmitter
        )

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        controller.release()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                pluginScope.launch {
                    controller.initialize()
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("ENGINE_INITIALIZATION_FAILED", it.message, null) }
                }
            }

            "start" -> {
                pluginScope.launch {
                    controller.start()
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("START_FAILED", it.message, null) }
                }
            }

            "stop" -> {
                val clearQueue = call.argument<Boolean>("clearQueue") ?: false
                pluginScope.launch {
                    controller.stop(clearQueue)
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("STOP_FAILED", it.message, null) }
                }
            }

            "skip" -> {
                pluginScope.launch {
                    controller.skip()
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("SKIP_FAILED", it.message, null) }
                }
            }

            "clearQueue" -> {
                pluginScope.launch {
                    controller.clearQueue()
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("CLEAR_QUEUE_FAILED", it.message, null) }
                }
            }

            "getStatus" -> {
                pluginScope.launch {
                    runCatching { controller.getStatus() }
                        .onSuccess { status ->
                            result.success(
                                mapOf(
                                    "enabled" to status.enabled,
                                    "engineState" to status.engineState.name,
                                    "playerState" to status.playerState.name,
                                    "queueSize" to status.queueSize,
                                    "currentCommentId" to status.currentCommentId,
                                    "currentText" to status.currentText,
                                    "currentSpeakerId" to status.currentSpeakerId
                                )
                            )
                        }
                        .onFailure { result.error("GET_STATUS_FAILED", it.message, null) }
                }
            }

            "release" -> {
                controller.release()
                result.success(mapOf("ok" to true))
            }

            "submitComment" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("INVALID_ARGUMENT", "arguments must be map", null)
                    return
                }

                val rawComment = RawComment(
                    id = args["id"] as? String ?: "",
                    text = args["text"] as? String ?: "",
                    userId = args["userId"] as? String,
                    postedAtEpochMs = (args["postedAtEpochMs"] as? Number)?.toLong() ?: 0L,
                    score = (args["score"] as? Number)?.toInt(),
                    isOwner = args["isOwner"] as? Boolean ?: false
                )

                pluginScope.launch {
                    controller.submitComment(rawComment)
                        .onSuccess { submitResult ->
                            result.success(
                                mapOf(
                                    "accepted" to submitResult.accepted,
                                    "skipped" to submitResult.skipped,
                                    "normalizedText" to submitResult.normalizedText,
                                    "skipReason" to submitResult.skipReason,
                                    "queueSize" to submitResult.queueSize
                                )
                            )
                        }
                        .onFailure { result.error("SUBMIT_FAILED", it.message, null) }
                }
            }

            "updateSettings" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("INVALID_ARGUMENT", "arguments must be map", null)
                    return
                }

                val dictionaryRules = (args["dictionaryRules"] as? List<Map<String, Any?>>)
                    ?.map {
                        ReplaceRule(
                            pattern = it["pattern"] as? String ?: "",
                            replacement = it["replacement"] as? String ?: "",
                            enabled = it["enabled"] as? Boolean ?: true
                        )
                    } ?: emptyList()

                val settings = SpeechSettings(
                    enabled = args["enabled"] as? Boolean ?: true,
                    speakerId = (args["speakerId"] as? Number)?.toInt() ?: 0,
                    speedScale = (args["speedScale"] as? Number)?.toFloat() ?: 1.15f,
                    pitchScale = (args["pitchScale"] as? Number)?.toFloat() ?: 0.0f,
                    intonationScale = (args["intonationScale"] as? Number)?.toFloat() ?: 1.0f,
                    volumeScale = (args["volumeScale"] as? Number)?.toFloat() ?: 1.0f,
                    prePhonemeLength = (args["prePhonemeLength"] as? Number)?.toFloat() ?: 0.1f,
                    postPhonemeLength = (args["postPhonemeLength"] as? Number)?.toFloat() ?: 0.1f,
                    maxTextLength = (args["maxTextLength"] as? Number)?.toInt() ?: 50,
                    maxQueueSize = (args["maxQueueSize"] as? Number)?.toInt() ?: 20,
                    duplicateWindowMs = (args["duplicateWindowMs"] as? Number)?.toLong() ?: 5000L,
                    skipEmojiOnly = args["skipEmojiOnly"] as? Boolean ?: true,
                    skipUrlOnly = args["skipUrlOnly"] as? Boolean ?: true,
                    replaceUrlWith = args["replaceUrlWith"] as? String ?: "URL省略",
                    trimLongTextSuffix = args["trimLongTextSuffix"] as? String ?: "、以下省略",
                    dictionaryRules = dictionaryRules,
                    ngWords = (args["ngWords"] as? List<String>) ?: emptyList()
                )

                pluginScope.launch {
                    controller.updateSettings(settings)
                        .onSuccess { result.success(mapOf("ok" to true)) }
                        .onFailure { result.error("UPDATE_SETTINGS_FAILED", it.message, null) }
                }
            }

            else -> result.notImplemented()
        }
    }
}
```

---

## 2. `SpeechController.kt`

```kotlin
package jp.example.comment_speech.controller

import jp.example.comment_speech.domain.model.RawComment
import jp.example.comment_speech.domain.model.SpeechRuntimeStatus
import jp.example.comment_speech.domain.model.SpeechSettings
import jp.example.comment_speech.domain.model.SubmitResult

interface SpeechController {
    suspend fun initialize(): Result<Unit>
    suspend fun start(): Result<Unit>
    suspend fun stop(clearQueue: Boolean = false): Result<Unit>
    suspend fun skip(): Result<Unit>
    suspend fun clearQueue(): Result<Unit>
    suspend fun submitComment(rawComment: RawComment): Result<SubmitResult>
    suspend fun updateSettings(settings: SpeechSettings): Result<Unit>
    suspend fun getStatus(): SpeechRuntimeStatus
    fun release()
}
```

---

## 3. `SpeechControllerImpl.kt`

```kotlin
package jp.example.comment_speech.controller

import jp.example.comment_speech.domain.engine.VoicevoxEngine
import jp.example.comment_speech.domain.event.SpeechEvent
import jp.example.comment_speech.domain.event.SpeechEventEmitter
import jp.example.comment_speech.domain.model.*
import jp.example.comment_speech.domain.normalizer.CommentNormalizer
import jp.example.comment_speech.domain.player.WavPlayer
import jp.example.comment_speech.domain.queue.SpeechQueueManager
import jp.example.comment_speech.infra.SettingsRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class SpeechControllerImpl(
    private val normalizer: CommentNormalizer,
    private val queueManager: SpeechQueueManager,
    private val engine: VoicevoxEngine,
    private val player: WavPlayer,
    private val settingsRepository: SettingsRepository,
    private val eventEmitter: SpeechEventEmitter
) : SpeechController {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val processMutex = Mutex()

    @Volatile
    private var started: Boolean = false

    @Volatile
    private var currentCommentId: String? = null

    @Volatile
    private var currentText: String? = null

    override suspend fun initialize(): Result<Unit> {
        val settings = settingsRepository.get()
        eventEmitter.emit(SpeechEvent.engineStateChanged(TtsEngineState.INITIALIZING))
        return engine.initialize(
            VoicevoxConfig(
                openJtalkDictDir = "",
                modelDir = "",
                defaultSpeakerId = settings.speakerId
            )
        ).onSuccess {
            eventEmitter.emit(SpeechEvent.engineStateChanged(TtsEngineState.READY))
        }.onFailure {
            eventEmitter.emit(SpeechEvent.error("ENGINE_INITIALIZATION_FAILED", it.message ?: "unknown"))
            eventEmitter.emit(SpeechEvent.engineStateChanged(TtsEngineState.ERROR))
        }
    }

    override suspend fun start(): Result<Unit> = runCatching {
        started = true
        startWorkerIfNeeded()
    }

    override suspend fun stop(clearQueue: Boolean): Result<Unit> = runCatching {
        started = false
        player.stop().getOrThrow()
        if (clearQueue) {
            queueManager.clear()
            eventEmitter.emit(SpeechEvent.queueUpdated(queueManager.size()))
        }
    }

    override suspend fun skip(): Result<Unit> = runCatching {
        player.stop().getOrThrow()
    }

    override suspend fun clearQueue(): Result<Unit> = runCatching {
        queueManager.clear()
        eventEmitter.emit(SpeechEvent.queueUpdated(queueManager.size()))
    }

    override suspend fun submitComment(rawComment: RawComment): Result<SubmitResult> = runCatching {
        val settings = settingsRepository.get()

        if (!settings.enabled) {
            return@runCatching SubmitResult(
                accepted = false,
                skipped = true,
                normalizedText = null,
                skipReason = "disabled",
                queueSize = queueManager.size()
            )
        }

        val normalized = normalizer.normalize(rawComment, settings)

        if (normalized.skipReason != null || normalized.normalizedText.isBlank()) {
            eventEmitter.emit(
                SpeechEvent.commentSkipped(
                    commentId = rawComment.id,
                    reason = normalized.skipReason ?: "blank"
                )
            )
            return@runCatching SubmitResult(
                accepted = false,
                skipped = true,
                normalizedText = normalized.normalizedText,
                skipReason = normalized.skipReason,
                queueSize = queueManager.size()
            )
        }

        val offerResult = queueManager.offer(
            SpeechQueueItem(
                commentId = normalized.id,
                text = normalized.normalizedText,
                priority = normalized.priority,
                createdAt = System.currentTimeMillis()
            )
        )

        if (!offerResult.accepted) {
            return@runCatching SubmitResult(
                accepted = false,
                skipped = true,
                normalizedText = normalized.normalizedText,
                skipReason = offerResult.reason,
                queueSize = queueManager.size()
            )
        }

        eventEmitter.emit(SpeechEvent.queueUpdated(queueManager.size()))

        if (started) {
            startWorkerIfNeeded()
        }

        SubmitResult(
            accepted = true,
            skipped = false,
            normalizedText = normalized.normalizedText,
            skipReason = null,
            queueSize = queueManager.size()
        )
    }

    override suspend fun updateSettings(settings: SpeechSettings): Result<Unit> = runCatching {
        settingsRepository.save(settings)
    }

    override suspend fun getStatus(): SpeechRuntimeStatus {
        val settings = settingsRepository.get()
        return SpeechRuntimeStatus(
            enabled = settings.enabled,
            engineState = engine.currentState(),
            playerState = player.currentState(),
            queueSize = queueManager.size(),
            currentCommentId = currentCommentId,
            currentText = currentText,
            currentSpeakerId = settings.speakerId
        )
    }

    override fun release() {
        player.release()
        engine.release()
        scope.cancel()
    }

    private fun startWorkerIfNeeded() {
        if (!started) return

        scope.launch {
            processMutex.withLock {
                while (started && !queueManager.isEmpty()) {
                    val item = queueManager.poll() ?: continue
                    eventEmitter.emit(SpeechEvent.queueUpdated(queueManager.size()))

                    currentCommentId = item.commentId
                    currentText = item.text

                    val settings = settingsRepository.get()
                    val request = SpeechRequest(
                        text = item.text,
                        speakerId = settings.speakerId,
                        speedScale = settings.speedScale,
                        pitchScale = settings.pitchScale,
                        intonationScale = settings.intonationScale,
                        volumeScale = settings.volumeScale,
                        prePhonemeLength = settings.prePhonemeLength,
                        postPhonemeLength = settings.postPhonemeLength
                    )

                    eventEmitter.emit(SpeechEvent.engineStateChanged(TtsEngineState.SYNTHESIZING))

                    val synth = engine.synthesize(request)
                    if (synth.isFailure) {
                        eventEmitter.emit(
                            SpeechEvent.speechFailed(
                                commentId = item.commentId,
                                message = synth.exceptionOrNull()?.message ?: "synthesis failed"
                            )
                        )
                        eventEmitter.emit(SpeechEvent.engineStateChanged(engine.currentState()))
                        continue
                    }

                    eventEmitter.emit(SpeechEvent.engineStateChanged(TtsEngineState.READY))
                    eventEmitter.emit(SpeechEvent.speechStarted(item.commentId, item.text))

                    val playResult = player.play(synth.getOrThrow().wavBytes)
                    if (playResult.isFailure) {
                        eventEmitter.emit(
                            SpeechEvent.speechFailed(
                                commentId = item.commentId,
                                message = playResult.exceptionOrNull()?.message ?: "play failed"
                            )
                        )
                        continue
                    }

                    eventEmitter.emit(SpeechEvent.speechCompleted(item.commentId))
                    currentCommentId = null
                    currentText = null
                }
            }
        }
    }
}
```

---

## 4. model 一式

### `RawComment.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class RawComment(
    val id: String,
    val text: String,
    val userId: String?,
    val postedAtEpochMs: Long,
    val score: Int? = null,
    val isOwner: Boolean = false
)
```

### `NormalizedComment.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class NormalizedComment(
    val id: String,
    val originalText: String,
    val normalizedText: String,
    val priority: Int = 0,
    val skipReason: String? = null
)
```

### `SpeechQueueItem.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class SpeechQueueItem(
    val commentId: String,
    val text: String,
    val priority: Int,
    val createdAt: Long
)
```

### `ReplaceRule.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
```

### `SpeechSettings.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class SpeechSettings(
    val enabled: Boolean = true,
    val speakerId: Int = 0,
    val speedScale: Float = 1.15f,
    val pitchScale: Float = 0.0f,
    val intonationScale: Float = 1.0f,
    val volumeScale: Float = 1.0f,
    val prePhonemeLength: Float = 0.1f,
    val postPhonemeLength: Float = 0.1f,
    val maxTextLength: Int = 50,
    val maxQueueSize: Int = 20,
    val duplicateWindowMs: Long = 5000L,
    val skipEmojiOnly: Boolean = true,
    val skipUrlOnly: Boolean = true,
    val replaceUrlWith: String = "URL省略",
    val trimLongTextSuffix: String = "、以下省略",
    val dictionaryRules: List<ReplaceRule> = emptyList(),
    val ngWords: List<String> = emptyList()
)
```

### `SpeechRequest.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class SpeechRequest(
    val text: String,
    val speakerId: Int,
    val speedScale: Float,
    val pitchScale: Float,
    val intonationScale: Float,
    val volumeScale: Float,
    val prePhonemeLength: Float,
    val postPhonemeLength: Float
)
```

### `SubmitResult.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class SubmitResult(
    val accepted: Boolean,
    val skipped: Boolean,
    val normalizedText: String?,
    val skipReason: String?,
    val queueSize: Int
)
```

### `SpeechRuntimeStatus.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class SpeechRuntimeStatus(
    val enabled: Boolean,
    val engineState: TtsEngineState,
    val playerState: PlayerState,
    val queueSize: Int,
    val currentCommentId: String?,
    val currentText: String?,
    val currentSpeakerId: Int
)
```

### `TtsEngineState.kt`

```kotlin
package jp.example.comment_speech.domain.model

enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    SYNTHESIZING,
    ERROR
}
```

### `PlayerState.kt`

```kotlin
package jp.example.comment_speech.domain.model

enum class PlayerState {
    IDLE,
    PLAYING,
    STOPPED,
    ERROR
}
```

### `VoicevoxConfig.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class VoicevoxConfig(
    val openJtalkDictDir: String,
    val modelDir: String,
    val defaultSpeakerId: Int
)
```

### `WavSynthesisResult.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class WavSynthesisResult(
    val wavBytes: ByteArray,
    val text: String,
    val durationEstimateMs: Long? = null
)
```

### `QueueOfferResult.kt`

```kotlin
package jp.example.comment_speech.domain.model

data class QueueOfferResult(
    val accepted: Boolean,
    val reason: String? = null
)
```

---

## 5. `CommentNormalizer.kt`

```kotlin
package jp.example.comment_speech.domain.normalizer

import jp.example.comment_speech.domain.model.NormalizedComment
import jp.example.comment_speech.domain.model.RawComment
import jp.example.comment_speech.domain.model.SpeechSettings

interface CommentNormalizer {
    fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment
}
```

---

## 6. `DefaultCommentNormalizer.kt`

```kotlin
package jp.example.comment_speech.domain.normalizer

import jp.example.comment_speech.domain.model.NormalizedComment
import jp.example.comment_speech.domain.model.RawComment
import jp.example.comment_speech.domain.model.SpeechSettings

class DefaultCommentNormalizer : CommentNormalizer {

    private val urlRegex = Regex("""https?://[\w/:%#$&?\(\)~.=+\-]+""")
    private val whitespaceRegex = Regex("""\s+""")
    private val emojiOnlyRegex = Regex("""^[\p{So}\p{Cn}\p{Cs}\s]+$""")
    private val symbolOnlyRegex = Regex("""^[!！?？wW８8草\sー～〜]+$""")

    override fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment {
        var text = raw.text
            .replace("\n", " ")
            .replace("\t", " ")
            .trim()

        text = whitespaceRegex.replace(text, " ")

        if (text.isBlank()) {
            return skipped(raw, "blank")
        }

        if (settings.ngWords.any { ng -> ng.isNotBlank() && text.contains(ng, ignoreCase = true) }) {
            return skipped(raw, "ng_word")
        }

        if (settings.skipUrlOnly && urlRegex.matches(text)) {
            return skipped(raw, "url_only")
        }

        text = urlRegex.replace(text, settings.replaceUrlWith)

        text = text.replace(Regex("""w{2,}""", RegexOption.IGNORE_CASE), "わら")
        text = text.replace(Regex("""草{2,}"""), "くさ")
        text = text.replace(Regex("""8{3,}|８{3,}"""), "はくしゅ")
        text = text.replace(Regex("""!{2,}|！{2,}"""), "びっくり")
        text = text.replace(Regex("""\?{2,}|？{2,}"""), "はてな")
        text = text.replace(Regex("""[ー～〜]{3,}"""), " のばし ")

        settings.dictionaryRules
            .filter { it.enabled }
            .forEach { rule ->
                runCatching {
                    text = text.replace(Regex(rule.pattern), rule.replacement)
                }
            }

        text = whitespaceRegex.replace(text, " ").trim()

        if (text.isBlank()) {
            return skipped(raw, "blank_after_normalize")
        }

        if (settings.skipEmojiOnly && emojiOnlyRegex.matches(text)) {
            return skipped(raw, "emoji_only")
        }

        if (symbolOnlyRegex.matches(text) && text.length <= 6) {
            return skipped(raw, "symbol_only")
        }

        if (text.length > settings.maxTextLength) {
            val trimAt = settings.maxTextLength.coerceAtLeast(1)
            text = text.take(trimAt) + settings.trimLongTextSuffix
        }

        return NormalizedComment(
            id = raw.id,
            originalText = raw.text,
            normalizedText = text,
            priority = if (raw.isOwner) 10 else 0,
            skipReason = null
        )
    }

    private fun skipped(raw: RawComment, reason: String): NormalizedComment {
        return NormalizedComment(
            id = raw.id,
            originalText = raw.text,
            normalizedText = "",
            skipReason = reason
        )
    }
}
```

---

## 7. `SpeechQueueManager.kt`

```kotlin
package jp.example.comment_speech.domain.queue

import jp.example.comment_speech.domain.model.QueueOfferResult
import jp.example.comment_speech.domain.model.SpeechQueueItem

interface SpeechQueueManager {
    fun offer(item: SpeechQueueItem): QueueOfferResult
    fun poll(): SpeechQueueItem?
    fun peek(): SpeechQueueItem?
    fun clear()
    fun size(): Int
    fun isEmpty(): Boolean
}
```

---

## 8. `InMemorySpeechQueueManager.kt`

```kotlin
package jp.example.comment_speech.domain.queue

import jp.example.comment_speech.domain.model.QueueOfferResult
import jp.example.comment_speech.domain.model.SpeechQueueItem
import java.util.ArrayDeque

class InMemorySpeechQueueManager(
    private val maxSize: Int
) : SpeechQueueManager {

    private val queue = ArrayDeque<SpeechQueueItem>()

    @Synchronized
    override fun offer(item: SpeechQueueItem): QueueOfferResult {
        if (queue.any { it.text == item.text }) {
            return QueueOfferResult(false, "duplicate")
        }

        if (queue.size >= maxSize) {
            return QueueOfferResult(false, "queue_full")
        }

        queue.addLast(item)
        return QueueOfferResult(true, null)
    }

    @Synchronized
    override fun poll(): SpeechQueueItem? = queue.removeFirstOrNull()

    @Synchronized
    override fun peek(): SpeechQueueItem? = queue.firstOrNull()

    @Synchronized
    override fun clear() {
        queue.clear()
    }

    @Synchronized
    override fun size(): Int = queue.size

    @Synchronized
    override fun isEmpty(): Boolean = queue.isEmpty()
}
```

---

## 9. `VoicevoxEngine.kt`

```kotlin
package jp.example.comment_speech.domain.engine

import jp.example.comment_speech.domain.model.*

interface VoicevoxEngine {
    suspend fun initialize(config: VoicevoxConfig): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult>
    fun isReady(): Boolean
    fun currentState(): TtsEngineState
    fun release()
}
```

---

## 10. `VoicevoxEngineImpl.kt` ダミー実装

```kotlin
package jp.example.comment_speech.domain.engine

import android.content.Context
import jp.example.comment_speech.domain.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class VoicevoxEngineImpl(
    private val context: Context
) : VoicevoxEngine {

    @Volatile
    private var state: TtsEngineState = TtsEngineState.UNINITIALIZED

    override suspend fun initialize(config: VoicevoxConfig): Result<Unit> = withContext(Dispatchers.Default) {
        runCatching {
            state = TtsEngineState.INITIALIZING

            // TODO:
            // 1. OpenJTalk 辞書ロード
            // 2. VOICEVOX Core 初期化
            // 3. VVM モデルロード

            state = TtsEngineState.READY
        }.onFailure {
            state = TtsEngineState.ERROR
        }
    }

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> =
        withContext(Dispatchers.Default) {
            runCatching {
                check(state == TtsEngineState.READY) { "VOICEVOX engine is not ready" }
                check(request.text.isNotBlank()) { "text is blank" }

                state = TtsEngineState.SYNTHESIZING

                // TODO:
                // 実際には VOICEVOX Core で request.text を wavBytes に変換する
                val dummyWav = ByteArray(0)

                state = TtsEngineState.READY

                WavSynthesisResult(
                    wavBytes = dummyWav,
                    text = request.text,
                    durationEstimateMs = null
                )
            }.onFailure {
                state = TtsEngineState.ERROR
            }
        }

    override fun isReady(): Boolean = state == TtsEngineState.READY

    override fun currentState(): TtsEngineState = state

    override fun release() {
        state = TtsEngineState.UNINITIALIZED
    }
}
```

---

## 11. `WavPlayer.kt`

```kotlin
package jp.example.comment_speech.domain.player

import jp.example.comment_speech.domain.model.PlayerState

interface WavPlayer {
    suspend fun play(wavBytes: ByteArray): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isPlaying(): Boolean
    fun currentState(): PlayerState
    fun release()
}
```

---

## 12. `MediaPlayerWavPlayer.kt` ダミー実装

```kotlin
package jp.example.comment_speech.domain.player

import android.content.Context
import jp.example.comment_speech.domain.model.PlayerState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MediaPlayerWavPlayer(
    private val context: Context
) : WavPlayer {

    @Volatile
    private var state: PlayerState = PlayerState.IDLE

    override suspend fun play(wavBytes: ByteArray): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            state = PlayerState.PLAYING

            // TODO:
            // 1. wavBytes を temp file に書く
            // 2. MediaPlayer で再生
            // 3. await completion

            delay(300) // ダミー

            state = PlayerState.IDLE
        }.onFailure {
            state = PlayerState.ERROR
        }
    }

    override suspend fun stop(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            // TODO: 実再生停止
            state = PlayerState.STOPPED
        }
    }

    override fun isPlaying(): Boolean = state == PlayerState.PLAYING

    override fun currentState(): PlayerState = state

    override fun release() {
        state = PlayerState.STOPPED
    }
}
```

---

## 13. event 関連

### `SpeechEventEmitter.kt`

```kotlin
package jp.example.comment_speech.domain.event

interface SpeechEventEmitter {
    fun emit(event: Map<String, Any?>)
}
```

### `FlutterSpeechEventEmitter.kt`

```kotlin
package jp.example.comment_speech.domain.event

class FlutterSpeechEventEmitter(
    private val sender: (Map<String, Any?>) -> Unit
) : SpeechEventEmitter {
    override fun emit(event: Map<String, Any?>) {
        sender(event)
    }
}
```

### `SpeechEvent.kt`

```kotlin
package jp.example.comment_speech.domain.event

import jp.example.comment_speech.domain.model.TtsEngineState

object SpeechEvent {

    fun engineStateChanged(state: TtsEngineState): Map<String, Any?> =
        mapOf(
            "type" to "engine_state_changed",
            "payload" to mapOf("state" to state.name)
        )

    fun queueUpdated(size: Int): Map<String, Any?> =
        mapOf(
            "type" to "queue_updated",
            "payload" to mapOf("size" to size)
        )

    fun commentSkipped(commentId: String, reason: String): Map<String, Any?> =
        mapOf(
            "type" to "comment_skipped",
            "payload" to mapOf(
                "commentId" to commentId,
                "reason" to reason
            )
        )

    fun speechStarted(commentId: String, text: String): Map<String, Any?> =
        mapOf(
            "type" to "speech_started",
            "payload" to mapOf(
                "commentId" to commentId,
                "text" to text
            )
        )

    fun speechCompleted(commentId: String): Map<String, Any?> =
        mapOf(
            "type" to "speech_completed",
            "payload" to mapOf("commentId" to commentId)
        )

    fun speechFailed(commentId: String, message: String): Map<String, Any?> =
        mapOf(
            "type" to "speech_failed",
            "payload" to mapOf(
                "commentId" to commentId,
                "message" to message
            )
        )

    fun error(code: String, message: String): Map<String, Any?> =
        mapOf(
            "type" to "error",
            "payload" to mapOf(
                "code" to code,
                "message" to message
            )
        )
}
```

---

## 14. settings repository

### `SettingsRepository.kt`

```kotlin
package jp.example.comment_speech.infra

import jp.example.comment_speech.domain.model.SpeechSettings

interface SettingsRepository {
    suspend fun get(): SpeechSettings
    suspend fun save(settings: SpeechSettings)
}
```

### `InMemorySettingsRepository.kt`

```kotlin
package jp.example.comment_speech.infra

import jp.example.comment_speech.domain.model.SpeechSettings
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class InMemorySettingsRepository : SettingsRepository {
    private val mutex = Mutex()

    private var settings: SpeechSettings = SpeechSettings()

    override suspend fun get(): SpeechSettings = mutex.withLock { settings }

    override suspend fun save(settings: SpeechSettings) {
        mutex.withLock {
            this.settings = settings
        }
    }
}
```

---

## 15. この次にやる実装

ここから先は順番が重要です。

### 先にやるべきもの

1. `VoicevoxEngineImpl` に **VOICEVOX Core 実結線**
2. `MediaPlayerWavPlayer` に **temp wav file 再生**
3. `InMemorySettingsRepository` を **DataStore** に置換

### 後でよいもの

1. `AudioTrack` 化
2. Foreground Service
3. より強い重複抑制
4. ユーザー辞書の永続化UI

---

## 16. 次に私がおすすめするもの

次に一番価値が高いのは、**ダミー部分を本物に差し替える実装**です。
具体的には次のどちらかです。

* **A. `VoicevoxEngineImpl` の VOICEVOX Core 実装**
* **B. Flutter 側の Dart ラッパー一式**

順番としては **A を先**にした方がいいです。
理由は、Android 単体完結の成否を決めるのがそこだからです。



では、**ダミーだった `VoicevoxEngineImpl` を本実装へ置き換える方針**を、Flutter プラグインで使いやすい形に切ります。

先に結論です。
**Flutter + Android 単体完結**なら、`voicevox_core` の **Android 向けビルド成果物**を使い、**Android ネイティブ層で JNI ブリッジを作る**のがいちばん堅いです。GitHub Releases には `voicevox_core-android-arm64-0.16.2.zip` と `voicevox_core-android-x86_64-0.16.2.zip` があり、Android 向け成果物が配布されています。さらに 0.16 系は新 API へ移行中で、2026-03-28 時点では `0.16.2` が公開済みです。 ([GitHub][1])

加えて、`voicevox_core` 本体のソースコードとビルド成果物は MIT ですが、**VVM 音声モデルには別途利用規約がある**ので、アプリ組み込み時はそこを分けて扱う必要があります。 ([GitHub][2])

## 方針

今回は **Kotlin から直接 Java API を呼ぶ案ではなく、JNI 経由で C API をラップする案**で書きます。

理由は3つです。

* Releases で Android 向けに明示されているのは **C API アセット**です。 ([GitHub][1])
* 0.16 系は新 API へ移行中で、周辺 API がまだ動いている途中です。プレビューと本番の差分もあるため、Flutter プラグインとしては **自前の JNI 境界を固定**した方が壊れにくいです。 ([GitHub][1])
* Java API 追加の記述は CHANGELOG にありますが、現時点の Android 配布物として見える一次情報は C API 側の方が明確です。 ([GitHub][3])

## 実装構成

```text
Flutter
  ↓ MethodChannel
Kotlin VoicevoxEngineImpl
  ↓ JNI
C++ bridge
  ↓ voicevox_core C API
libvoicevox_core.so
  + OpenJTalk 辞書
  + VVM
```

---

# 1. Android 側のファイル配置

例です。

```text
android/
  src/main/
    cpp/
      CMakeLists.txt
      voicevox_jni.cpp
    jniLibs/
      arm64-v8a/
        libvoicevox_core.so
      x86_64/
        libvoicevox_core.so
    kotlin/jp/example/comment_speech/domain/engine/
      VoicevoxEngine.kt
      VoicevoxEngineImpl.kt
      NativeVoicevoxBridge.kt
    assets/
      open_jtalk_dic_utf_8-1.11/
        ...
      voice/
        speaker_XXXX.vvm
```

`voicevox_core` の Android 用 zip に入っている `.so` を ABI ごとに `jniLibs` へ置く形です。Android 向け成果物自体は公式 Releases にあります。 ([GitHub][1])

---

# 2. まず変えるべき設計

前の `VoicevoxEngineImpl` は Kotlin だけで完結する前提でしたが、ここからは次の3層に分けます。

* `VoicevoxEngineImpl.kt`

  * Kotlin の公開 API
  * assets から辞書と VVM を内部ストレージへ展開
  * JNI 呼び出し
* `NativeVoicevoxBridge.kt`

  * `external fun` 定義
* `voicevox_jni.cpp`

  * 実際に `voicevox_core` を呼ぶ

この分離にしておくと、後で `AudioQuery` ベースにする場合も、`tts()` 直叩きのまま行く場合も Kotlin 側をほぼ変えずに済みます。

---

# 3. Kotlin 側: `NativeVoicevoxBridge.kt`

```kotlin
package jp.example.comment_speech.domain.engine

object NativeVoicevoxBridge {

    init {
        System.loadLibrary("voicevox_jni")
    }

    external fun nativeInitialize(
        openJtalkDictDir: String
    ): Boolean

    external fun nativeLoadModel(
        vvmPath: String
    ): Boolean

    external fun nativeIsModelLoaded(
        speakerId: Int
    ): Boolean

    external fun nativeTts(
        text: String,
        speakerId: Int,
        speedScale: Float,
        pitchScale: Float,
        intonationScale: Float,
        volumeScale: Float,
        prePhonemeLength: Float,
        postPhonemeLength: Float
    ): ByteArray?

    external fun nativeRelease()
}
```

ここでのポイントは、**JNI の API 面を自分で固定する**ことです。
`voicevox_core` の内部 API 変更を Kotlin 側へ漏らさないためです。

---

# 4. Kotlin 側: `VoicevoxEngineImpl.kt` 本実装雛形

これはそのまま差し替えやすい形です。

```kotlin
package jp.example.comment_speech.domain.engine

import android.content.Context
import jp.example.comment_speech.domain.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class VoicevoxEngineImpl(
    private val context: Context
) : VoicevoxEngine {

    @Volatile
    private var state: TtsEngineState = TtsEngineState.UNINITIALIZED

    @Volatile
    private var initialized: Boolean = false

    override suspend fun initialize(config: VoicevoxConfig): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                state = TtsEngineState.INITIALIZING

                val dictDir = ensureOpenJtalkDict()
                val vvmFile = ensureDefaultVvm()

                val initOk = NativeVoicevoxBridge.nativeInitialize(dictDir.absolutePath)
                check(initOk) { "nativeInitialize failed" }

                val loadOk = NativeVoicevoxBridge.nativeLoadModel(vvmFile.absolutePath)
                check(loadOk) { "nativeLoadModel failed" }

                initialized = true
                state = TtsEngineState.READY
            }.onFailure {
                initialized = false
                state = TtsEngineState.ERROR
            }
        }

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> =
        withContext(Dispatchers.Default) {
            runCatching {
                check(initialized) { "VOICEVOX engine is not initialized" }
                check(state == TtsEngineState.READY) { "VOICEVOX engine is not ready" }
                check(request.text.isNotBlank()) { "text is blank" }

                state = TtsEngineState.SYNTHESIZING

                val wavBytes = NativeVoicevoxBridge.nativeTts(
                    request.text,
                    request.speakerId,
                    request.speedScale,
                    request.pitchScale,
                    request.intonationScale,
                    request.volumeScale,
                    request.prePhonemeLength,
                    request.postPhonemeLength
                ) ?: error("nativeTts returned null")

                state = TtsEngineState.READY

                WavSynthesisResult(
                    wavBytes = wavBytes,
                    text = request.text,
                    durationEstimateMs = null
                )
            }.onFailure {
                state = TtsEngineState.ERROR
            }
        }

    override fun isReady(): Boolean = initialized && state == TtsEngineState.READY

    override fun currentState(): TtsEngineState = state

    override fun release() {
        NativeVoicevoxBridge.nativeRelease()
        initialized = false
        state = TtsEngineState.UNINITIALIZED
    }

    private fun ensureOpenJtalkDict(): File {
        val outDir = File(context.filesDir, "open_jtalk_dic_utf_8-1.11")
        if (outDir.exists()) return outDir

        copyAssetDirectory("open_jtalk_dic_utf_8-1.11", outDir)
        return outDir
    }

    private fun ensureDefaultVvm(): File {
        val outFile = File(context.filesDir, "voice/default.vvm")
        if (outFile.exists()) return outFile

        outFile.parentFile?.mkdirs()
        context.assets.open("voice/default.vvm").use { input ->
            outFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return outFile
    }

    private fun copyAssetDirectory(assetPath: String, outDir: File) {
        outDir.mkdirs()
        val children = context.assets.list(assetPath) ?: emptyArray()

        if (children.isEmpty()) {
            context.assets.open(assetPath).use { input ->
                File(outDir.parentFile, File(assetPath).name).outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            return
        }

        children.forEach { child ->
            val childAssetPath = "$assetPath/$child"
            val nested = context.assets.list(childAssetPath) ?: emptyArray()
            if (nested.isEmpty()) {
                val outFile = File(outDir, child)
                context.assets.open(childAssetPath).use { input ->
                    outFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            } else {
                copyAssetDirectory(childAssetPath, File(outDir, child))
            }
        }
    }
}
```

## ここでの注意

このコードは **JNI 境界までは実コード**ですが、実際に `voicevox_core` を叩くのは次の C++ 側です。
また、**VVM は assets 同梱でもいい**ですが、アプリサイズが重くなるので、将来的には初回ダウンロード方式も検討対象です。Releases でも sample.vvm の扱いが変わっており、0.16 preview では sample.vvm のデプロイをやめた記載があります。 ([GitHub][1])

---

# 5. JNI 側: `voicevox_jni.cpp` 雛形

ここは **コンパイルが通る最小の骨格**として示します。
ただし、`voicevox_core` の 0.16 系は API 更新が進んでいるため、**関数名やオプション構造体は採用バージョンに合わせて最終調整が必要**です。0.16 系は新 API に移行中で、2026 年にも API 変更議論が継続しています。 ([GitHub][1])

```cpp
#include <jni.h>
#include <string>
#include <vector>
#include <memory>

// 実際の include パスは voicevox_core の配布物に合わせて修正
#include "voicevox_core.h"

namespace {
    bool g_initialized = false;
    // 実際には synthesizer / onnxruntime / openjtalk などのハンドルを保持
}

static std::string JStringToString(JNIEnv* env, jstring s) {
    if (!s) return "";
    const char* chars = env->GetStringUTFChars(s, nullptr);
    std::string out(chars ? chars : "");
    if (chars) env->ReleaseStringUTFChars(s, chars);
    return out;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_jp_example_comment_1speech_domain_engine_NativeVoicevoxBridge_nativeInitialize(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring open_jtalk_dict_dir
) {
    std::string dictDir = JStringToString(env, open_jtalk_dict_dir);

    // TODO:
    // 1. voicevox_core 初期化
    // 2. OpenJTalk 辞書ロード
    // 3. Synthesizer 構築
    // 0.16 採用時はそのバージョンの初期化手順に合わせる

    g_initialized = true;
    return JNI_TRUE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_jp_example_comment_1speech_domain_engine_NativeVoicevoxBridge_nativeLoadModel(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring vvm_path
) {
    if (!g_initialized) return JNI_FALSE;

    std::string vvmPath = JStringToString(env, vvm_path);

    // TODO:
    // VVM を読み込み、speaker/style に対応する voice model を load

    return JNI_TRUE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_jp_example_comment_1speech_domain_engine_NativeVoicevoxBridge_nativeIsModelLoaded(
    JNIEnv* env,
    jobject /*thiz*/,
    jint speaker_id
) {
    if (!g_initialized) return JNI_FALSE;

    // TODO:
    // speaker/style のロード確認
    return JNI_TRUE;
}

extern "C"
JNIEXPORT jbyteArray JNICALL
Java_jp_example_comment_1speech_domain_engine_NativeVoicevoxBridge_nativeTts(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring text,
    jint speaker_id,
    jfloat speed_scale,
    jfloat pitch_scale,
    jfloat intonation_scale,
    jfloat volume_scale,
    jfloat pre_phoneme_length,
    jfloat post_phoneme_length
) {
    if (!g_initialized) return nullptr;

    std::string inputText = JStringToString(env, text);
    if (inputText.empty()) return nullptr;

    // TODO:
    // 0.16 採用版の API に合わせて
    // 1. AudioQuery / TTS options 作成
    // 2. 各スケール値をセット
    // 3. wav bytes を取得

    std::vector<uint8_t> wav;  // 実際は voicevox_core の戻り値をここへ詰める

    jbyteArray result = env->NewByteArray(static_cast<jsize>(wav.size()));
    if (!result) return nullptr;
    if (!wav.empty()) {
        env->SetByteArrayRegion(
            result,
            0,
            static_cast<jsize>(wav.size()),
            reinterpret_cast<const jbyte*>(wav.data())
        );
    }
    return result;
}

extern "C"
JNIEXPORT void JNICALL
Java_jp_example_comment_1speech_domain_engine_NativeVoicevoxBridge_nativeRelease(
    JNIEnv* env,
    jobject /*thiz*/
) {
    // TODO:
    // voicevox_core の各リソース解放
    g_initialized = false;
}
```

### 正直に言うと

ここは **関数名をいま断定しません**。
理由は、0.16 系で API が大きく変わっていて、しかも 2026 年時点で関連議論が続いているからです。一次情報として確実なのは、**Android 向け成果物があり、Java/C のブロッキング API 実装が 0.16 preview 系で進められた**ことまでです。 ([GitHub][1])

---

# 6. CMake: `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.22.1)
project(voicevox_jni)

add_library(voicevox_jni SHARED
    voicevox_jni.cpp
)

find_library(log-lib log)

# voicevox_core のヘッダ配置先に合わせて include を調整
target_include_directories(voicevox_jni PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

# jniLibs にある libvoicevox_core.so をリンク
target_link_directories(voicevox_jni PRIVATE
    ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}
)

target_link_libraries(voicevox_jni
    voicevox_core
    ${log-lib}
)
```

---

# 7. Gradle 側

`android/build.gradle.kts` か `android/app/build.gradle.kts` 側で NDK/CMake を有効にします。

```kotlin
android {
    defaultConfig {
        minSdk = 26

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += ""
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
```

---

# 8. 今の `SpeechControllerImpl` で直した方がいい点

現状スケルトンのままだと、合成失敗時に `ERROR` へ落ちたあと復帰しづらいです。
なので、ここだけ先に直した方がいいです。

### 変える点

* `synthesize()` 失敗で即 permanently `ERROR` にしない
* 一時的失敗なら `READY` へ戻す
* 初期化失敗だけ `ERROR` 扱いを強める

たとえば Kotlin 側ではこう寄せます。

```kotlin
override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> =
    withContext(Dispatchers.Default) {
        if (!initialized) {
            return@withContext Result.failure(IllegalStateException("VOICEVOX engine is not initialized"))
        }

        state = TtsEngineState.SYNTHESIZING

        val result = runCatching {
            val wavBytes = NativeVoicevoxBridge.nativeTts(
                request.text,
                request.speakerId,
                request.speedScale,
                request.pitchScale,
                request.intonationScale,
                request.volumeScale,
                request.prePhonemeLength,
                request.postPhonemeLength
            ) ?: error("nativeTts returned null")

            WavSynthesisResult(
                wavBytes = wavBytes,
                text = request.text,
                durationEstimateMs = null
            )
        }

        state = if (result.isSuccess) TtsEngineState.READY else TtsEngineState.ERROR
        result
    }
```

さらに実運用では、`speech_failed` が連続した時だけ `release() -> initialize()` を試す方が安定します。

---

# 9. あなたの要件で特に重要な点

ニコニココメント読み上げ用途だと、実際のボトルネックは **合成品質より短文処理の安定性**です。
そのため実装順はこれが安全です。

1. **1話者固定**
2. **短文のみ**
3. **`tts()` 相当の最短経路で WAV を取る**
4. **キュー長を厳しく制限**
5. **長文・URL・草・拍手を整形で先に潰す**

ここで欲張って複数話者・細かいイントネーション制御・辞書 UI を先にやると、デバッグ面積が一気に増えます。

---

# 10. ここから次にやるべき作業

次に本当に必要なのは、抽象論ではなく **採用バージョンを 0.16.2 に固定した前提で、`voicevox_jni.cpp` の TODO を埋めること**です。
ただ、その部分は **配布 zip 内のヘッダ名・関数名・初期化フローに合わせて正確に書く必要**があります。0.16 系は新 API で、古い情報を混ぜると事故ります。 ([GitHub][1])

次は、**0.16.2 の Android 配布物前提で `voicevox_jni.cpp` の中身を埋めるためのチェックリスト**を切ります。

[1]: https://github.com/VOICEVOX/voicevox_core/releases "Releases · VOICEVOX/voicevox_core · GitHub"
[2]: https://github.com/VOICEVOX/voicevox_core "GitHub - VOICEVOX/voicevox_core: 無料で使える中品質なテキスト読み上げソフトウェア、VOICEVOXのコア · GitHub"
[3]: https://github.com/VOICEVOX/voicevox_core/blob/main/CHANGELOG.md "voicevox_core/CHANGELOG.md at main · VOICEVOX/voicevox_core · GitHub"


前提として、2026-03-28 時点では `voicevox_core` の Releases に **Android 向け成果物**があり、0.16 系では **C と Java の blocking API** が実装されています。また CHANGELOG では、Java 側で `Synthesizer` / `OpenJtalk` / `VoiceModelFile` が `voicevoxcore.blocking` 配下へ移るなど、**0.16 系で API 変更が入っている**ことが明示されています。さらに C API のオプション構造体を JSON に置き換える breaking change 議論も 2026-03-21 時点で open です。つまり、**0.16.2 で固定して進める**のが重要です。 ([GitHub][1])

---

## 1. まず固定するもの

### 1-1. バージョン固定

* `voicevox_core` は **0.16.2** に固定
* `libvoicevox_core.so` と `voicevox_core.h` は **同じ release ZIP 由来**にする
* 開発中に別バージョンのヘッダと `.so` を混ぜない

理由:
0.16 系は API 変更が入っており、CHANGELOG にも breaking change が複数あります。ヘッダとバイナリがずれると JNI 層で事故ります。 ([GitHub][1])

### 1-2. 配布物の配置確認

0.16 系の CHANGELOG では、リリース内容物の配置が **`include/voicevox_core.h`** と **`lib/` 配下の動的ライブラリ** に変わる旨が書かれています。なので unzip 後の構成を前提に配置します。 ([GitHub][2])

確認項目:

* `include/voicevox_core.h`
* `lib/<abi向けのso>` または Android 用 zip 内の `.so`
* LICENSE
* VERSION

---

## 2. JNI で先に決める設計

### 2-1. Kotlin から見える JNI API を固定

今の `NativeVoicevoxBridge` のように、Kotlin 側からは次だけ見える形に固定します。

* `nativeInitialize(openJtalkDictDir)`
* `nativeLoadModel(vvmPath)`
* `nativeTts(...)`
* `nativeRelease()`

理由:
0.16 系は今後も周辺 API が動く可能性がありますが、JNI 境界を固定すれば Kotlin 側への影響を閉じ込められます。これは実装戦略上かなり重要です。根拠として、0.16 系で Java / C API の構成変更と breaking change が出ています。 ([GitHub][2])

### 2-2. speakerId の意味を内部で固定

ここは盲点です。
VOICEVOX 側は 0.16 系で `VoiceModelId` や style 周りの扱いに変更が入っています。Kotlin 側の `speakerId` を JNI 内でそのまま style id と見なすのか、別の internal mapping にするのかを先に決めてください。Releases には `style_id_to_model_inner_id` 変更や VVM に UUID を振る変更が見えます。 ([GitHub][1])

おすすめ:

* 初期版は **1 話者固定**
* Kotlin の `speakerId` は **実質 style id 固定値**
* 複数話者対応は後で足す

---

## 3. Android 資材のチェック

### 3-1. OpenJTalk 辞書

確認項目:

* assets に辞書を入れる
* 初回起動時に `filesDir` へ展開する
* JNI には **展開後ディレクトリの絶対パス**を渡す

### 3-2. VVM

確認項目:

* 使用したい VVM を assets か初回DLで配布
* `filesDir/voice/...` へ配置
* JNI には **VVM ファイルの絶対パス**を渡す

注意:
Releases には sample.vvm の扱い変更や、README 更新として「自分でビルドした場合は製品版VVMが読めないことがわかるようにした」という記述があります。つまり **VVM は軽く考えない方がいい**です。 ([GitHub][1])

### 3-3. ABI

確認項目:

* `arm64-v8a`
* `x86_64`

少なくとも Android 向け成果物があることは Releases で確認できます。実機向けはまず arm64、エミュレータ検証は x86_64 です。 ([GitHub][1])

---

## 4. `voicevox_jni.cpp` で埋める順番

## Step A: include とリンクを通す

最初にやること:

* `#include "voicevox_core.h"` が通る
* `voicevox_jni` から `libvoicevox_core.so` をリンクできる
* アプリ起動時に `UnsatisfiedLinkError` が出ない

受け入れ条件:

* `System.loadLibrary("voicevox_jni")` 成功
* `nativeInitialize()` を呼んでも即クラッシュしない

---

## Step B: `nativeInitialize()`

ここでやること:

* `open_jtalk_dict_dir` を `std::string` に変換
* `voicevox_core` の初期化
* OpenJTalk 辞書を使うオブジェクトの作成
* synthesizer 本体の生成
* 必要なら onnxruntime の初期化

注意:
0.16 系で API 変更があるため、**0.16.2 の `voicevox_core.h` に書かれている初期化シーケンスをそのまま採用**してください。ここで古いブログや古いサンプルを混ぜるのが一番危険です。0.16 系は CHANGELOG でも API 再編が明示されています。 ([GitHub][2])

実装チェック:

* 初期化成功時だけ `g_initialized = true`
* 失敗時は `false`
* 例外や null path で落ちない

---

## Step C: `nativeLoadModel()`

ここでやること:

* VVM パスを受け取る
* `VoiceModelFile` 相当を読み込む
* synthesizer に model を load する

確認ポイント:

* 1つの VVM で対象 style が本当に入っているか
* その style を後段 `nativeTts()` で指定できるか
* load 済みかどうかを内部で管理するか

リリースノートには `VoiceModel` → `VoiceModelFile` の変更や VVM / UUID 周りの変更が見えます。0.16 系ではこの周辺が従来とズレています。 ([GitHub][1])

---

## Step D: `nativeTts()`

ここが核心です。

やること:

* `text` を UTF-8 文字列として受け取る
* style id 相当を指定
* speed / pitch / intonation / volume / pre/post phoneme を反映
* WAV バイト列を返す

ただし、ここで決める必要があります。

### 方式1: TTS 一発呼び出し

* 短文コメント読み上げ向き
* 実装が単純
* 初期版に向く

### 方式2: `create_audio_query` → パラメータ編集 → synthesis

* より柔軟
* 将来の調整に強い
* 実装はやや複雑

CHANGELOG には Python API で `audio_query` が `create_audio_query` に改名されるとあり、「C API と Java API に合わせる形」と説明されています。つまり **0.16 系の設計思想は create_audio_query ベース**です。なので、将来まで見れば方式2の方が自然です。 ([GitHub][2])

ただし、あなたの用途は **ニコニココメントの短文読み上げ**です。
初期版は **一発 TTS 相当でまず通す**方が安全です。

---

## 5. `nativeTts()` の実装チェックリスト

### 入力検証

* `g_initialized == true`
* `text` が空でない
* モデルが load 済み
* `speakerId/styleId` が有効

### 合成前

* state を Kotlin 側で `SYNTHESIZING`
* JNI 側で必要なら mutex で逐次化
* 1回の呼び出しで複数スレッドから同時合成しない

### 合成

* options 生成
* speed / pitch / intonation / volume / pre/post を設定
* synthesis 実行
* 戻り WAV の長さを取得

### 戻り値

* `std::vector<uint8_t>` を `jbyteArray` にコピー
* 0 byte の WAV を返さない
* 失敗時は `nullptr`

### 後処理

* 一時バッファ解放
* エラーコードが取れるならログ出力
* 内部状態を壊さない

---

## 6. ログで必ず出すもの

JNI 層は見えにくいので、最低限これをログに出してください。

* `nativeInitialize start/end`
* 辞書パス
* VVM パス
* model load success/fail
* 入力文字列長
* style id
* 生成 wav size
* 失敗した関数名

理由:
Flutter から見たとき、失敗は全部「null が返った」に見えやすいからです。

---

## 7. 先に潰すべき失敗パターン

優先順位順です。

### 7-1. `.so` 読み込み失敗

症状:

* 起動時に `UnsatisfiedLinkError`

確認:

* ABI が合っているか
* `jniLibs` の配置
* `voicevox_jni` と `voicevox_core` の依存が正しいか

### 7-2. 辞書パス不正

症状:

* initialize 失敗
* native 側で初期化不能

確認:

* assets 展開先がディレクトリになっているか
* 相対パスではなく絶対パスか

### 7-3. VVM ロード失敗

症状:

* initialize は通るが synthesize が失敗

確認:

* VVM が存在するか
* その VVM が対象 style を含むか
* 製品版 VVM の扱いに問題がないか

### 7-4. 空 WAV

症状:

* エラーなしに見えるが音が出ない

確認:

* WAV サイズ > 44 byte
* ヘッダ付き WAV になっているか
* AudioTrack / MediaPlayer 側が WAV を期待通り処理しているか

---

## 8. Kotlin 側で追加した方がいい防御

### `initialize()` に追加

* dictDir exists check
* vvmFile exists check
* 失敗時にパスを含めてログ

### `synthesize()` に追加

* `wavBytes.isNotEmpty()`
* 小さすぎるサイズを reject
* 連続失敗回数カウント

### `release()` に追加

* 二重解放を許容
* release 後に state を確実に `UNINITIALIZED`

---

## 9. 実装順のおすすめ

一番安全なのはこの順です。

1. `nativeInitialize()` を通す
2. `nativeLoadModel()` を通す
3. `nativeTts()` で **固定テキスト** `"テストです"` を WAV 化
4. Kotlin 側で byte size を確認
5. `MediaPlayer` で再生
6. その後で `submitComment()` とつなぐ

ここでの重要点は、**ニコニココメント連携より前に、固定文字列で音が出ることを証明する**ことです。
先に上流をつなぐと、故障箇所が増えすぎます。

---

## 10. この時点での実装完了条件

最低限、次が満たせれば次へ進めます。

* Android 実機 arm64 で起動する
* `initialize()` 成功
* `nativeLoadModel()` 成功
* `"こんにちは"` を 1件だけ合成できる
* WAV byte array が返る
* Android で再生できる

これが通れば、次は **`MediaPlayerWavPlayer` の本実装**へ進めばよいです。


[1]: https://github.com/VOICEVOX/voicevox_core/releases?utm_source=chatgpt.com "Releases · VOICEVOX/voicevox_core"
[2]: https://github.com/VOICEVOX/voicevox_core/blob/main/CHANGELOG.md?utm_source=chatgpt.com "CHANGELOG.md - VOICEVOX/voicevox_core"
