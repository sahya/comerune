# Issue #38: 設定リポジトリ (SettingsRepository)

## Goal

読み上げ設定（速度、話者、NGワード、辞書ルール等）を保持・読み出しするリポジトリを実装する。
他のコンポーネント（Normalizer, Controller, Engine）がこの設定を参照する。

## Scope

### インターフェース

```kotlin
interface SettingsRepository {
    suspend fun get(): SpeechSettings
    suspend fun save(settings: SpeechSettings)
}
```

### 初期実装: `InMemorySettingsRepository`

- メモリ上で `SpeechSettings` を保持
- `Mutex` で排他制御
- デフォルト値は `SpeechSettings()` のデフォルトコンストラクタから取得

## Non-scope

- `DataStore` (Android Jetpack) を使った永続化 — 将来の改善対象
- 設定変更の UI（Flutter 側の Issue）
- 設定変更イベントの通知（Controller 側の責務）
- SharedPreferences 等への移行

## Dependencies

- #32（データモデル: SpeechSettings, ReplaceRule）

## Acceptance Criteria

1. `get()` がデフォルトの `SpeechSettings` を返す
2. `save()` 後に `get()` で更新された設定が取得できる
3. 複数回の `save()` で最新の設定のみ保持される
4. スレッドセーフである（`Mutex` による排他制御）

## Test Expectations

- **単体テスト（必須）**:
  - 初期状態でデフォルト設定が返ること
  - save → get で更新された設定が返ること
  - 複数回 save で最新のみ保持されること

## AI 実装適性

- **AI 実装に向いている**: 非常にシンプルな実装。スケルトンコードがそのまま使える
- **人間承認ポイント**: 特になし

## Implementation Notes

- スケルトンコード（仕様書 Section 14）がそのまま使える
- 将来 `DataStore` に切り替える場合はインターフェースはそのまま、実装クラスだけ差し替える設計
- `suspend fun` にしているのは、将来の永続化対応でI/Oが入ることを見越しているため
