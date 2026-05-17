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

## 同梱プリセットフィルタ辞書の編集

同梱のプリセットフィルタ辞書は、難読化したバイナリ `android/app/src/main/assets/preset_ng_words.enc` としてのみコミットしています（平文 `preset_ng_words.json` は `.gitignore` 済みで、リポジトリには含めません）。

辞書を変更する場合は、次の手順で行ってください。

```sh
dart run tool/ng_dict.dart decrypt   # 平文 .json をローカルに復元
# android/app/src/main/assets/preset_ng_words.json を編集
dart run tool/ng_dict.dart encrypt   # .enc を再生成
git add android/app/src/main/assets/preset_ng_words.enc   # .enc のみコミット
```

`encrypt` は内容から決定論的に生成されるため、辞書を変更していなければ `.enc` の差分は出ません（不要な差分ノイズを防ぐためにも、辞書を変更したときだけ再生成してください）。鍵は配布物に埋め込まれており暗号学的な秘匿性はありません（カジュアルな抽出防止と解析コストの引き上げが目的です）。鍵が無い環境でも、アプリはプリセットフィルタを無効にしたまま起動します（ユーザー設定の NG ワードは影響を受けません）。

## セキュリティに関する報告

セキュリティ上の問題は Issue ではなく [SECURITY.md](SECURITY.md) の方法でご報告ください。
