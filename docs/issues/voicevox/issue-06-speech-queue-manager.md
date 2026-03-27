# Issue 06: 読み上げキュー管理 (SpeechQueueManager)

## Goal

整形済みコメントの再生待ちキューを管理する。
FIFO 順で1件ずつ処理し、キューあふれやスパム対策として最大件数制御と重複排除を行う。

## Scope

### インターフェース

- `SpeechQueueManager` インターフェース（`domain/queue/`）

### 実装クラス: `InMemorySpeechQueueManager`

- **FIFO 管理**: 投入順に取り出し
- **最大件数制御**: `maxSize`（デフォルト 20）を超えたら拒否
- **重複投入抑止**: 同一テキストがキュー内に存在する場合は拒否
- **操作**: offer / poll / peek / clear / size / isEmpty

### API（仕様 Section 4.8）

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

## Non-scope

- 優先度付きの eviction（キュー満杯時に低優先度を押し出す方式）— 初期版は単純拒否
  - **Assumption**: 初期版はキュー満杯時に新規コメントを拒否する。eviction は将来対応（N2 参照）
- キューの永続化
- キューサイズの動的変更

## Dependencies

- Issue 01（データモデル: SpeechQueueItem, QueueOfferResult）

## Acceptance Criteria

1. 投入順に `poll()` で取り出せる（FIFO）
2. `maxSize` を超える投入が `QueueOfferResult(false, "queue_full")` で拒否される
3. 同一テキストの重複投入が `QueueOfferResult(false, "duplicate")` で拒否される
4. `clear()` 後は `isEmpty() == true` かつ `size() == 0`
5. `poll()` が空キューで `null` を返す
6. スレッドセーフである（`@Synchronized` またはそれに準ずる排他制御）

## Test Expectations

- **単体テスト（必須）**:
  - FIFO 順序の検証
  - 最大件数での拒否
  - 重複テキスト拒否
  - clear 後の状態
  - 空キューでの poll / peek
  - 複数スレッドからの同時アクセス（可能であれば）

## AI 実装適性

- **AI 実装に向いている**: シンプルなデータ構造操作。テストが書きやすい
- **人間承認ポイント**: 初期版で eviction なしの単純拒否でよいかの確認（N2 参照）

## Implementation Notes

- `ArrayDeque` を内部データ構造として使用
- `@Synchronized` で排他制御（Kotlin の同期プリミティブ）
- 将来の eviction 対応を見据え、`offer()` の戻り値で理由を返す設計にしておく
