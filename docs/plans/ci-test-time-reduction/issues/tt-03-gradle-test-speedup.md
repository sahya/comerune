# TT-03: Kotlin テストジョブの Gradle 高速化実験

## Goal
`:app:testDebugUnitTest` ステップ（実測 152〜308 秒。テスト実体は 27 ファイルと小さい）の
時間内訳を特定し、キャッシュ活用で warm run を 30 秒以上短縮する。
効果が出なければ「効果なし」と記録してクローズする（実験 Issue）。

## Scope
- spec.md §2.2 の手順に従った内訳計測（`--profile`）と結果の記録
- 実験: (a) Gradle build cache の有効化（CI 実行時のみ）、(b) configuration cache の試行
- 効果が確認できた施策のみを `kotlin-test` ジョブへ反映

## Non-scope
- Kotlin ソース・テストコードの変更
- テストの分割・除外・`testOptions` 変更
- ローカル開発者のビルド挙動を変える `gradle.properties` の恒久変更
  （CI 側フラグで実現できない場合は owner に判断を返す）

## Dependencies
TT-02（分割後の `kotlin-test` ジョブが対象）

## Acceptance criteria
- [ ] 時間内訳（configuration / compile / test 実行）が Issue コメントまたは PR 本文に
      記録されている
- [ ] 採用した施策について、warm cache run 同士の比較で中央値 30 秒以上の短縮が
      run URL 付きで示されている。**または**効果なし・非互換と判定し、変更を残さず
      記録のみでクローズしている
- [ ] キャッシュ導入後も clean な状態（cache miss）で green になることを 1 run 確認済み

## Test expectations
- 既存 Kotlin テストが全パスすること以外の追加テストは不要

## Implementation notes
- setup-java の `cache: gradle` は `~/.gradle/caches` を保存するため、
  `org.gradle.caching=true` で生成される build cache もそこに乗る
- configuration cache が Flutter Gradle プラグイン非対応でエラーになったら、
  回避策を作り込まず不採用と判定する（spec.md §2.2）
- `--no-daemon` は現行コメントの意図（使い捨て CI でのメモリ保持回避）を尊重して維持
