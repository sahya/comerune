# Issue 05: 重複抑制 (DuplicateDetector)

## Goal

同一コメントや短時間の連投を検出して読み上げをスキップする。
配信中にスパム的なコメント連投があっても、同じ音声が繰り返し再生されることを防ぐ。

## Scope

### 重複抑制ルール（仕様 Section 3.5.8）

- **完全一致**: 同一の整形済みテキストがすでに直近に存在 → スキップ
- **時間ウィンドウ**: `duplicateWindowMs`（デフォルト 5000ms）以内に同一整形結果 → スキップ
- **同一ユーザー連投**: 同一 userId の短時間連投 → 2件目以降を抑制

### 実装クラス

- `DuplicateDetector` インターフェース
- `InMemoryDuplicateDetector` 実装
  - 直近 N 件のコメント履歴を保持
  - 時間経過で自動的に古いエントリを無視

### CommentNormalizer への統合

- `DefaultCommentNormalizer` に `DuplicateDetector` を注入
- 整形処理の最後に重複チェックを実行
- 重複時は `skipReason = "duplicate"` を設定

## Non-scope

- 重複判定の類似度計算（編集距離等）— 完全一致のみ
- 重複履歴の永続化
- 重複抑制パラメータの UI

## Dependencies

- Issue 01（データモデル: NormalizedComment, SpeechSettings）
- Issue 02（CommentNormalizer に統合するため）

## Acceptance Criteria

1. 同一テキストのコメントが連続投入された場合、2件目は `skipReason = "duplicate"` でスキップされる
2. 5秒以内の同一テキストがスキップされる
3. 5秒超過後の同一テキストは通過する
4. 同一 userId から短時間（5秒以内）に異なるテキストの連投があった場合、2件目以降が抑制される
5. `duplicateWindowMs` の設定変更が反映される
6. 異なるテキスト・異なるユーザーのコメントは正常に通過する

## Test Expectations

- **単体テスト（必須）**:
  - 同一テキスト連続投入でのスキップ
  - 時間ウィンドウ経過後の通過
  - 同一ユーザー連投の抑制
  - 異なるユーザー・異なるテキストの正常通過
  - 履歴が無限に増えないことの確認（古いエントリの破棄）

## AI 実装適性

- **AI 実装に向いている**: ロジックが明確で、時間ベースの判定はテストしやすい
- **人間承認ポイント**: 同一ユーザー連投の「短時間」をどう定義するか（仕様では `duplicateWindowMs` と同じ5秒を想定しているが、別パラメータにすべきか判断が必要）

## Implementation Notes

- 時間判定にはテスト可能な時計（`Clock` や注入可能な `currentTimeMillis`）を使うとテストが安定する
- 履歴の最大保持件数は固定値（例: 50件）で十分。キューの最大件数（20）より多ければよい
- `DuplicateDetector` は `CommentNormalizer` の依存として注入し、Normalizer 内で呼ぶ設計
