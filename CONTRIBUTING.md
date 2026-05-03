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

## セキュリティに関する報告

セキュリティ上の問題は Issue ではなく [SECURITY.md](SECURITY.md) の方法でご報告ください。
