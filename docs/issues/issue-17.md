# Issue #17: アプリケーション観点でのセキュリティ設定

Labels: chore, security

Epic: #1

## Goal

アプリケーションのビルド再現性・依存パッケージの安全性・通信経路の保護・機密情報の漏洩防止を確認・改善し、リリース前のセキュリティベースラインを確立する。

## Background

現時点で以下のセキュリティ上の懸念がある:

1. **pubspec.lock が `.gitignore` に含まれている** — アプリケーションでは lock ファイルをコミットしないと、ビルドごとに異なるバージョンが解決される可能性があり、再現性とサプライチェーン安全性が損なわれる
2. **依存パッケージの既知脆弱性が未検査** — 6 個の直接依存 + 多数の推移的依存について、CVE / OSV の確認が行われていない
3. **android/ ディレクトリが未生成** — 将来の `flutter create` 時に適切なセキュリティ設定を適用するガイドラインが未整備
4. **ログマスキングの網羅性が未検証** — SessionWsClient にクレデンシャルマスキングがあるが、他のクライアント（NdgrClient, LegacyCommentClient, VOICEVOX/棒読みちゃん通信）での漏洩リスクが未確認

## Scope

### 1. pubspec.lock のコミットとハッシュ固定

- `.gitignore` から `pubspec.lock` の行を削除する
- `pubspec.lock` をリポジトリにコミットする（sha256 content-hash が既に含まれていることを確認）
- AGENTS.md または CLAUDE.md に「`pubspec.lock` は必ずコミットする」旨のルールを追記する

### 2. 依存パッケージの脆弱性検査

- `dart pub outdated` を実行し、現在のバージョンと最新バージョンの乖離を確認する
- 既知脆弱性の有無を確認する（`dart pub deps` の出力を OSV.dev で照合、または `osv-scanner` を実行）
- 脆弱性が見つかった場合は対応方針を Issue コメントに記録する

### 3. Android セキュリティ設定ガイドラインの策定

`android/` ディレクトリ生成時に適用すべき設定をドキュメント化する:

- `android:allowBackup="false"`（SharedPreferences に接続設定が含まれるため）
- `android:usesCleartextTraffic="false"`（VOICEVOX ローカル通信は例外設定で対応）
- `network_security_config.xml` の作成（ローカルホスト例外を明示）
- リリースビルドで `android:debuggable="false"` を確認
- `minSdkVersion` を 23 以上に設定（TLS 1.2 デフォルトサポート）

### 4. 通信セキュリティの確認

- WebSocket 接続が `wss://` を強制していることを確認する
- HTTP 通信（NDGR エンドポイント）が `https://` を強制していることを確認する
- VOICEVOX / 棒読みちゃんへのローカル通信のリスクを文書化する（LAN 内平文通信の許容範囲を明示）

### 5. ログ・デバッグ情報の機密情報漏洩防止

- 全クライアントクラスのログ出力を確認し、トークン・URL パラメータ・セッション情報がマスクされていることを検証する
- リリースビルドでデバッグログが抑制される仕組みを確認または導入する
- `.ai/flutter_rules.md` にログ出力のセキュリティルールを追記する

## Non-scope

- 証明書ピニング（certificate pinning）の実装（v1.2 では対象外）
- ProGuard / R8 の難読化設定（リリース準備フェーズで対応）
- セキュリティテストの自動化（Issue #18 の CI 統合で対応）
- OAuth / 認証フローの導入（現時点で認証不要の公開 API のみ使用）

## Dependencies

- なし（他 Issue に依存しない独立した chore）
- Issue #16（CI 導入）と並行可能。脆弱性スキャンの CI 統合は Issue #18 で対応

## Target Files / Areas

| ファイル / ディレクトリ | 変更内容 |
|------------------------|---------|
| `.gitignore` | `pubspec.lock` の行を削除 |
| `pubspec.lock` | コミット対象に追加 |
| `AGENTS.md` | lock ファイルコミットルールを追記 |
| `.ai/flutter_rules.md` | ログセキュリティルール追記 |
| `docs/security/android-guidelines.md`（新規） | Android セキュリティ設定ガイドライン |
| `docs/security/communication-audit.md`（新規） | 通信セキュリティ確認結果 |
| `lib/domain/connection/` 配下 | ログ出力の監査・修正（必要な場合） |

## Acceptance Criteria

- [ ] `.gitignore` から `pubspec.lock` が除外され、lock ファイルがリポジトリにコミットされている
- [ ] `pubspec.lock` 内の全パッケージに sha256 content-hash が含まれていることを確認済み
- [ ] `dart pub outdated` の結果が確認され、重大な乖離がない（または対応方針が記録されている）
- [ ] 既知脆弱性の有無が確認され、結果が記録されている
- [ ] Android セキュリティ設定ガイドラインがドキュメント化されている
- [ ] 全 WebSocket 接続が `wss://` を使用していることが確認済み
- [ ] 全 HTTP 通信が `https://` を使用していることが確認済み（ローカル通信の例外が文書化されている）
- [ ] 全クライアントクラスのログ出力にトークン・セッション情報の漏洩がないことが確認済み

## Validation / Error Handling

- `pubspec.lock` を `.gitignore` から外した後、`dart pub get` で lock ファイルが正常に生成されることを確認する
- 脆弱性スキャン結果はゼロであることが理想だが、リスク評価の上で許容判断を記録すれば可

## Test Expectations

- **unit**: なし（設定・ドキュメント変更のため）
- **widget**: なし
- **integration**: なし
- **手動確認**:
  - `pubspec.lock` がコミットされていることを `git status` で確認
  - `dart pub outdated` の出力を目視確認
  - ログ出力の監査結果を目視確認

## Constraints

- 新規パッケージを追加しない（脆弱性スキャンツールは CI 側で導入）
- 既存の動作を変更しない（設定・ドキュメント・ログ修正のみ）
- android/ ディレクトリの作成は行わない（ガイドラインの策定のみ）

## Implementation Notes

### pubspec.lock の .gitignore 除外

```diff
- pubspec.lock
```

Dart 公式ドキュメント（https://dart.dev/guides/libraries/private-files）でも、アプリケーションプロジェクトでは `pubspec.lock` のコミットを推奨している。ライブラリの場合のみ `.gitignore` に含める。

### 脆弱性検査コマンド例

```bash
# バージョン乖離の確認
dart pub outdated

# OSV Scanner（Go 製、GitHub が提供）
osv-scanner --lockfile pubspec.lock
```

### Android network_security_config.xml の雛形

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    <!-- VOICEVOX ローカル通信用の例外 -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```

## AI実装適性

**Medium** — ログ監査は全クライアントコードの読解が必要。設定変更自体は軽微だが、網羅的な確認が求められる

## Human Approval Needed

**Yes** — 以下の判断はオーナー確認が必要:
- 脆弱性が見つかった場合の対応方針（バージョンアップ or リスク許容）
- VOICEVOX ローカル通信の平文許容範囲
- Android セキュリティガイドラインの最終承認

---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 脆弱性検査の結果サマリ
   - 意図的に実装しなかった内容
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する
3. GitHub Issue をクローズしない（オーナーが確認後にクローズする）