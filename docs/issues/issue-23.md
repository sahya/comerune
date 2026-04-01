# Issue #23: ユーザー名読み上げ仕様の再定義（「コメント→名前さん」）と設定依存の解消

Labels: bug, ux, speech, settings, comment-screen

GitHub Issue:

Parent: #22（項目5の派生）

Epic: #1

## Goal

ユーザーコメント読み上げの体験を次の仕様で統一する。

1. 読み上げ時に名前へ「さん」を付与する  
2. 読み上げ順を「コメント → 名前」にする  
3. UI上の「ユーザーID名前解決」を「ユーザー名表示」と独立して切り替え可能にする  
4. ユーザーID非表示設定でも、条件を満たせばユーザー名を読み上げできるようにする

## Scope

- `CommentScreen` の読み上げ文生成ロジックを新仕様へ変更
- ユーザー名解決トグルのUI依存（`showUserName` 依存）を解消
- ユーザーID非表示時でも読み上げ側で名前解決が有効になる条件を明確化し実装
- 既存テストの期待値更新 + 必要な回帰テスト追加

## Non-scope

- 読み上げエンジン（VOICEVOX/Bouyomi）自体の刷新
- コメント表示フォーマット全体の再設計（表示列/UIデザイン変更）
- 新規アーキテクチャ導入、大規模リファクタ

## Current Findings（現仕様の確認）

### 1) 読み上げ順が「名前 → コメント」になっている

- 現在は `speechText = '$displayName、$speechText'` で前置している
  - `lib/presentation/screens/comment_screen.dart`（`_submitNewCommentsForSpeech`）

### 2) 読み上げ名解決で数値ID制約がある

- `_resolveSpeechDisplayName` 内で非数値IDを早期 return している
  - `lib/presentation/screens/comment_screen.dart`（`_resolveSpeechDisplayName` / `_isNumericUserId`）
- そのため、非数値ID + `message.userName` ありでも読み上げ名が付かない
  - `test/presentation/screens/comment_screen_speech_test.dart` の現期待値にも反映済み

### 3) UI上の名前解決トグルが「ユーザー名表示」に依存している

- `showUserName == false` のとき `resolveUserName` の `onChanged` が null
  - `lib/presentation/screens/comment_display_settings_screen.dart`
- 同挙動は widget test でも固定化されている
  - `test/presentation/screens/comment_display_settings_screen_test.dart`

### 4) 読み上げON/OFFは独立だが、名前解決ON/OFFとの運用導線が分かりづらい

- `readUserName` は `TtsSettingsScreen` で単独トグル可能
  - `lib/presentation/screens/tts_settings_screen.dart`
- 一方、名前解決は表示設定側で `showUserName` と結びついており、読み上げ用途での調整が直感的でない

## Acceptance Criteria

- [ ] `readUserName=true` かつ表示名が解決できる場合、読み上げ文が「`{comment}、{name}さん`」になる
- [ ] `readUserName=true` でも名前が解決できない場合は従来どおりコメント本文のみを読む
- [ ] 同一ユーザーに既に敬称付き名が保存されている場合、敬称を重複付与しない（例: `テストさんさん` を避ける）
- [ ] 読み上げ用の名前解決優先順位が `コテハン → message.userName → resolveUserName` で統一される
- [ ] `message.userName` が存在する場合は userId が非数値でも読み上げ名として利用される
- [ ] `CommentDisplaySettingsScreen` で `showUserName=false` でも `resolveUserName` を独立してON/OFFできる
- [ ] `showUserName=false` かつ `readUserName=true` かつ `resolveUserName=true` のとき、読み上げ名解決が有効に動作する
- [ ] `showUserName=false` でも `resolveUserName=true` の間は、読み上げ用途の名前解決リクエスト（`requestUserNameResolve`）が継続される
- [ ] 上記条件で既存のコメント表示（ユーザーID非表示挙動）は維持される

### 設定組み合わせ（最低保証）

| showUserName | resolveUserName | readUserName | 期待動作 |
|---|---|---|---|
| OFF | OFF | ON | 本文のみ読み上げ（名前解決しない） |
| OFF | ON | OFF | 画面表示はID非表示のまま、読み上げは本文のみ |
| OFF | ON | ON | 画面表示はID非表示のまま、「本文→名前さん」で読み上げ |
| ON | ON | ON | 既存表示要件を維持しつつ、「本文→名前さん」で読み上げ |

## Test Expectations

- **widget**
  - `CommentDisplaySettingsScreen`: `showUserName` OFF時でも `resolveUserName` が操作可能であること
  - `TtsSettingsScreen`: `readUserName` 設定の永続化が維持されること
- **speech/widget**
  - 読み上げ文フォーマットが「コメント→名前さん」へ変わること
  - ユーザーID非表示 + 名前解決ON + 名前読み上げON の組み合わせ回帰
  - `コテハン → message.userName → resolveUserName` 優先順位回帰
  - 非数値ID + `message.userName` ありケースで名前読み上げされる回帰

## Assumptions

- 区切り記号は既存実装に合わせて `、` を使用する
- 敬称付与は「読み上げ時の最終表示名」に対して適用し、既に `さん` 終端なら追加しない
- 既存の表示用解決優先順位（コテハン → `message.userName` → `resolveUserName`）は読み上げ側でも踏襲する

## Risks / Follow-ups

- 既存テストは「非数値IDは読み上げ名を付けない」前提が含まれるため、期待値更新漏れに注意
- 表示設定と読み上げ設定の責務境界が曖昧なため、将来的に設定項目の配置（表示設定/読み上げ設定）再整理を検討

## AI実装適性

**Medium** — 変更箇所は局所的だが、設定依存と読み上げ文フォーマットの回帰テスト整理が必要

## Human Approval Needed

**Yes** — 敬称付与ルール（重複回避含む）と設定UIの最終文言はオーナー確認が必要
