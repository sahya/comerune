# Issue #2: AppMessage モデルと LvParser の実装

Labels: v1.2, model

GitHub Issue: https://github.com/sahya/comerune/issues/2

Epic: #1

## Goal

アプリ全体で使われる共通コメントモデル（AppMessage）と、入力文字列から放送IDを抽出するユーティリティ（LvParser）を作成する。他の Issue の基盤となる。

## Scope

- `AppMessage` クラスの定義（id, timestamp, userId, content, type, raw）
- `AppMessageType` enum の定義（chat, operator, notification, gift, nicoad）
- `LvParser` クラスの実装（正規表現 `lv\d+` で抽出）
- 上記のユニットテスト

## Non-scope

- UI実装
- WebSocket接続
- 読み上げ処理
- エラーコード enum（Issue #3 で実装）

## Dependencies

なし（最初に着手可能）

## Acceptance Criteria

- [ ] `AppMessage` が id / timestamp / userId / content / type / raw フィールドを持つ
- [ ] `AppMessageType` が chat / operator / notification / gift / nicoad を持つ
- [ ] `LvParser.extract("lv345678901")` が `"lv345678901"` を返す
- [ ] `LvParser.extract("https://live.nicovideo.jp/watch/lv345678901")` が `"lv345678901"` を返す
- [ ] `LvParser.extract("invalid")` が null を返す
- [ ] 複数マッチ時は最初のマッチを返す

## Validation / Error Handling

- 入力が null / 空 / lv不含の場合は null を返す（例外は投げない）

## Test Expectations

- **unit**: LvParser の各パターン（lv直接、URL、不正入力、複数マッチ）、AppMessage の生成
- **widget**: なし
- **integration**: なし

## Assumptions

- `AppMessage.id` は NDGR/legacy から取得できない場合に UUID 等で生成する方針だが、生成ロジック自体はここでは実装しない（各クライアント側で行う）

## AI実装適性

**High** — 純粋なデータクラスとユーティリティ。曖昧さが少ない

## Human Approval Needed

**No**


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/2`）
3. GitHub Issue をクローズする
