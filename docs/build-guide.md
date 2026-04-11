# ビルド手順

## 前提条件

- Flutter SDK 3.22.0 以上（Dart SDK 3.4.0 以上）
- Android SDK

## 基本手順

```bash
# リポジトリをクローン
git clone https://github.com/sahya/comerune.git
cd comerune

# 依存パッケージの取得
flutter pub get

# デバッグビルド（実機/エミュレータ接続時）
flutter run

# デバッグAPKの生成
flutter build apk --debug

# リリースAPKの生成
flutter build apk --release
```

## Makefile

Makefileも用意しています。

```bash
make build           # デバッグAPK
make build-release   # リリースAPK
make test            # テスト実行
make format          # 安全フォーマット（既存の作業差分以外は自動で戻す）
make format-all      # 全体フォーマット（専用PR向け）
make check           # 静的解析 + フォーマット + テスト（まとめて）
```

## フォーマット運用の推奨

- 通常のIssue対応では `make format` を使い、スコープ外の大量差分混入を防ぐ
- リポジトリ全体の整形を行う場合は `make format-all` を使い、**機能変更と分離した別PR** で実施する
