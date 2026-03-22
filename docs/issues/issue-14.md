# Issue #14: VoicevoxEngine（VOICEVOX HTTP API 連携 + 音声再生）の実装

Labels: v1.2, speech

GitHub Issue: https://github.com/sahya/comerune/issues/14

Epic: #1

## Goal

VOICEVOX の HTTP API でコメントの音声を合成し、アプリ内で再生する。

## Scope

- `SpeechEngine` を実装する `VoicevoxEngine` クラス
- `POST /audio_query` → `POST /synthesis` の2段階 API 呼び出し
- 音声バイナリの `audioplayers` による再生
- 接続先の管理（既定: エミュレータ `10.0.2.2:50021`、実機は LAN 内ホスト）
- 話者 ID、話速、音高、抑揚、音量の設定適用
- `/speakers` API からの話者一覧取得（設定画面のドロップダウン用）
- 話者一覧取得失敗時のフォールバック（既定 ID=0）
- HTTP 処理は UI スレッドを塞がない（非同期）
- 合成失敗時はスキップ

## Non-scope

- UI（設定画面は Issue #12 で実装済み）
- キュー制御・フィルタ（Issue #11 で実装済み）
- 感情パラメータ等の拡充（将来拡張）

## Dependencies

- Issue #11（SpeechEngine 基盤）
- Issue #12（設定値の取得、話者ドロップダウンへの連携）

## Acceptance Criteria

- [ ] `/audio_query` → `/synthesis` でコメントの音声が生成される
- [ ] 生成された音声がアプリ内で再生される
- [ ] 話者 ID、話速、音高、抑揚、音量が設定通りに適用される
- [ ] `/speakers` API から話者一覧を取得してドロップダウンに反映できる
- [ ] API 接続失敗時は「取得失敗」を表示し、ID=0 で動作する
- [ ] 合成失敗時は発話をスキップする
- [ ] UI スレッドがブロックされない

## Validation / Error Handling

- API 接続失敗 → ログ出力、発話スキップ
- 音声再生失敗 → ログ出力、スキップ
- 話者一覧取得失敗 → フォールバック

## Test Expectations

- **unit**: API リクエスト構築、パラメータ適用、話者一覧取得失敗時のフォールバック
- **widget**: なし
- **integration**: 実際の VOICEVOX サーバへの接続テスト（手動）

## Assumptions

- VOICEVOX の host/port 管理は、初期実装ではアプリ内定数とする（エミュレータ: `10.0.2.2:50021`）

## AI実装適性

**High** — VOICEVOX の API は公開仕様が明確

## Human Approval Needed

**Yes** — host/port の管理方法（定数 vs 隠し設定）について確認が望ましい


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/14`）
3. GitHub Issue をクローズする
