# Issue #6: NdgrClient（NDGR コメント取得クライアント）の実装

Labels: v1.2, infra

GitHub Issue: https://github.com/sahya/comerune/issues/6

Epic: #1

## Goal

NDGR の view API URI を起点に HTTP streaming でコメントを取得し、Protobuf length-delimited をデコードして AppMessage に変換する。

## Scope

- view API URI から HTTP streaming でデータを受信
- Protobuf length-delimited stream のデコード
- backward/segment を辿った過去コメント取得（設定件数に応じて）
- 受信データから AppMessage への正規化（MessageNormalizer の NDGR 部分）
  - chat の表示は必須
  - timestamp はサーバ時刻優先
  - userId は取れれば取る
- ストール検出（15秒無受信）

## Non-scope

- 再接続ロジック（Issue #8）
- UI表示
- Protobuf の .proto 定義ファイルの作成（事前準備として必要だが、この Issue のスコープではライブラリ選定と合わせて行う）

## Dependencies

- Issue #2（AppMessage モデル）
- Issue #4（TimelineStore — コメントの emit 先）
- Protobuf ライブラリの選定（事前タスク）

## Acceptance Criteria

- [ ] view API URI に HTTP接続してデータを受信できる
- [ ] Protobuf length-delimited をデコードできる
- [ ] 過去コメントを設定件数分取得できる（既定100件）
- [ ] chat タイプのコメントが AppMessage に正規化される
- [ ] 15秒無受信でストールとして通知する
- [ ] UIスレッドをブロックしない（Isolate 推奨）

## Validation / Error Handling

- HTTP接続失敗時はエラー通知
- Protobuf デコード例外はログ出力し、次のメッセージの処理を継続
- 断片復元の発生回数をログに記録

## Test Expectations

- **unit**: Protobuf デコード、AppMessage 正規化、ストール検出ロジック
- **widget**: なし
- **integration**: 実際のNDGRサーバへの接続テスト（可能であれば）

## Assumptions

- .proto ファイルは参考実装（tsukumijima/NDGRClient, TORISOUP/NdgrClientSharp）から推定して作成する
- Isolate でのデコードは推奨であり、初期実装では非同期処理のみでも可（性能問題が出た場合に Isolate 化する）

## AI実装適性

**Medium** — Protobuf の .proto 推定と backward/segment アルゴリズムに参考実装の読解が必要

## Human Approval Needed

**Yes** — Protobuf ライブラリの選定と .proto の内容について承認が必要

## Human Approval Record (2026-03-28 JST)

### Approval 1: Protobuf ライブラリ不使用（手書きデコーダ採用）

- Decision: `protobuf` パッケージを追加せず、`NdgrProtobufDecoder` / `_ProtoReader` を採用
- Alternatives considered:
  - `protobuf` + `.proto` 生成コード
  - 既存実装の一部移植
- Rationale:
  - NDGR の実レスポンスを段階的に扱える最小実装を優先
  - 依存追加を避けつつ、length-delimited 復元と unknown field skip を明示実装
  - 参考実装（tsukumijima/NDGRClient, TORISOUP/NdgrClientSharp）のフィールド対応で検証
- Risks:
  - API 変更時の追従コストが高い
- Mitigation:
  - デコーダ単体テストを維持し、仕様変更時は field mapping を更新する
- Approval status: **Approved by owner (sahya)**

### Approval 2: エラー通知インターフェース（Issue #8 接続点）

- Decision:
  - `NdgrClient.connect()` の失敗は **Future の例外でのみ通知**
  - `events` ストリームは `message` / `stalled` のみ通知（error event は emit しない）
- Integration rule:
  - ConnectionSupervisor 側で `connect()` の例外を `ConnectionErrorCode.ndgrStreamFailed` に単一マッピングする
  - 二重シグナリング（stream + exception）の再処理を禁止する
- Approval status: **Approved by owner (sahya)**

### Approval 3: TimelineStore 連携責務

- Decision:
  - `NdgrClient` は TimelineStore に直接依存せず、`NdgrClientEvent.message` を emit する
  - TimelineStore への投入は ConnectionSupervisor/上位層で実施する
- Rationale:
  - `domain/connection` で接続責務に限定し、保存責務を分離する
  - Issue #8 以降の統合時に、NDGR/legacy の双方を同一経路で集約できる
- Approval status: **Approved by owner (sahya)**


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/6`）
3. GitHub Issue をクローズする
