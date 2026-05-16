# コントリビューションについて

comerune は MIT ライセンスのオープンソースプロジェクトです。

## フォークのすすめ

「こんな機能がほしい」「ここを変えたい」と思ったら、**フォークして自分好みに改造する**のがおすすめです。生成 AI と一緒なら、コードに詳しくなくてもアプリを改造できる時代です。

ビルド方法は [docs/build-guide.md](docs/build-guide.md) を参照してください。

> フォークしたアプリを公開する場合は、「comerune」とは別の名前をつけてください（[README](README.md#アプリ名について) 参照）。

## 直接コントリビュートする場合

プルリクエストを送っていただく場合は、以下をお願いします。

- 事前に Issue で相談してください
- `dart format .` / `flutter analyze` / `flutter test` を通してください
- コミットメッセージは `type(scope): description`（[Conventional Commits](https://www.conventionalcommits.org/)）形式で
- `pubspec.lock` はリポジトリにコミットしています。`flutter pub get` 実行後に `pubspec.lock` の差分が出た場合は、依存パッケージの sha256 が変わったというサインなので、**意図した変更かを確認してから commit に含めてください**（サプライチェーン攻撃の検知ポイント）。

個人プロジェクトのため、すべての PR をマージできるわけではありません。ご了承ください。

### AI 支援ツールの痕跡を残さない

本リポジトリは公開されています。PR の説明文・コミットメッセージに、AI 支援ツールのセッション URL や帰属情報を**含めないでください**。

- AI ツールのセッション URL（例: `https://claude.ai/code/session_...`）を貼らない
- AI の co-author 行・「Generated with ...」等の帰属行・モデル識別子（バージョン名など）を含めない
- 理由: 公開リポジトリの履歴に内部のツール利用情報が永続的に残るのを避けるため。リリースノートで内部情報を伏せる方針（[AGENTS.md](AGENTS.md) のリリースノート作成ルール）と同じ考え方です

> Claude Code を使う場合、リポジトリの `.claude/settings.json` で `attribution`（`commit` / `pr` を空文字列）を設定済みのため、ツール経由の自動付与は抑止されます。フォーク先や他ツール・手動記載では各自ご注意ください。

## セキュリティに関する報告

セキュリティ上の問題は Issue ではなく [SECURITY.md](SECURITY.md) の方法でご報告ください。
