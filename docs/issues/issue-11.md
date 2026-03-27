# Issue #11: 読み上げ基盤（SpeechEngine / キュー制御 / フィルタ）の実装

Labels: v1.2, speech

GitHub Issue: https://github.com/sahya/comerune/issues/11

Epic: #1

## Goal

コメント読み上げの共通基盤（キュー、フィルタ、エンジン抽象）を作る。

## Scope

- `SpeechEngine` 抽象クラス（インターフェース）
- 読み上げキュー制御:
  - キュー上限（既定20件）
  - 最大遅延（既定10秒）超えたら古いものから破棄
- 整形フィルタ:
  - URL省略（「URL」に置換）
  - 連投抑制（同一userId 1秒以内の連続）
  - NGワード正規表現マッチでスキップ
- 自動読み上げ ON/OFF の制御
- legacy 未対応フォーマットは読み上げ対象外

## Non-scope

- 棒読みちゃんの TCP 送信（Issue #13）
- VOICEVOX の HTTP API 呼び出し（Issue #14）
- UI（設定画面は Issue #12）

## Dependencies

- Issue #2（AppMessage モデル）

## Acceptance Criteria

- [ ] キュー上限を超えた場合、古いコメントが破棄される
- [ ] 最大遅延を超えたコメントが破棄される
- [ ] URL が「URL」に置換される
- [ ] 同一 userId の1秒以内の連続コメントの2件目以降がスキップされる
- [ ] NGワード正規表現にマッチするコメントがスキップされる
- [ ] 不正な正規表現パターンは無視される
- [ ] 自動読み上げ OFF 時はキューに追加されない
- [ ] legacy 未対応フォーマットのコメントは読み上げされない

## Validation / Error Handling

- 不正な NGワード正規表現はスキップ（ログ出力）

## Test Expectations

- **unit**: キュー制御（上限、遅延破棄）、フィルタ（URL省略、連投抑制、NGワード）、不正正規表現の処理
- **widget**: なし
- **integration**: なし

## Assumptions

なし

## AI実装適性

**High** — キュー制御とフィルタは定型的なロジック

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
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/11`）
3. GitHub Issue をクローズする
