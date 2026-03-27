# Issue 02: コメント整形 — 前処理・スキップ判定

## Goal

コメント整形の骨格を作る。テキストの空白正規化と、読み上げ不要なコメントのスキップ判定を実装する。

## Scope

### インターフェース

- `CommentNormalizer` インターフェースを `domain/normalizer/` に作成

### 前処理ルール（仕様 Section 3.5.1）

1. 改行 → 空白に変換
2. タブ → 空白に変換
3. 連続空白 → 1つに圧縮
4. 前後空白を trim
5. 制御文字を除去

### スキップ判定（仕様 Section 3.4）

以下に該当するコメントは `skipReason` を設定して返す:

- 空白のみ → `"blank"`
- 絵文字・記号のみ → `"emoji_only"` / `"symbol_only"`

### 実装クラス

- `DefaultCommentNormalizer` の骨格を作成
- この Issue では前処理とスキップ判定のみ実装
- URL処理、記号圧縮、辞書置換等は後続 Issue で追加

## Non-scope

- URL 処理（Issue 03）
- 記号圧縮（Issue 03）
- 絵文字変換の詳細ロジック（Issue 03）
- 文字数制限（Issue 04）
- 辞書置換（Issue 04）
- NGワード（Issue 04）
- 重複抑制（Issue 05）

## Dependencies

- Issue 01（データモデル: RawComment, NormalizedComment, SpeechSettings）

## Acceptance Criteria

1. `CommentNormalizer` インターフェースが存在し、`normalize(RawComment, SpeechSettings): NormalizedComment` を持つ
2. `"  こんにちは\n\nすごい\tですね  "` → `"こんにちは すごい ですね"` に正規化される
3. 空白のみ入力 → `skipReason = "blank"` が返る
4. 制御文字（`\u0000` 等）が除去される
5. 前処理後に空でなければ `normalizedText` に値が入り `skipReason = null` である

## Test Expectations

- **単体テスト（必須）**:
  - 改行・タブ・連続空白の正規化
  - 空文字/空白のみ入力のスキップ
  - 制御文字除去
  - 通常テキストが変更されないこと
  - 前後空白の trim

## AI 実装適性

- **AI 実装に向いている**: 純粋な文字列変換ロジック。テストも書きやすい
- **人間承認ポイント**: 特になし。仕様が明確

## Implementation Notes

- `DefaultCommentNormalizer` は後続 Issue で段階的にルールを追加していく設計
- 絵文字/記号のみ判定の正規表現は、この Issue では基本的なものだけ入れる（詳細は Issue 03）
- `priority` の計算は `isOwner` フラグのみ（仕様どおり: owner=10, 通常=0）
