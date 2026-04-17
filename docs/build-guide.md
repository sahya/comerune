# ビルド手順

## 前提条件

- Flutter SDK 3.22.0 以上（Dart SDK 3.4.0 以上）
- Android SDK

## Application ID の設定

Android の `applicationId` は `android/app_id.properties` から読み込まれます。
このファイルはリポジトリに含まれないため（フォーク保護のため `.gitignore` 対象）、ローカルで作成する必要があります。

```bash
# テンプレートをコピー
cp android/app_id.properties.example android/app_id.properties

# applicationId を編集
# applicationId=app.spectacles_software.comerune  ← 本番用
```

ファイルが存在しない場合、`com.example.comerune`（開発用プレースホルダー）が使用されます。
ビルドログに警告が表示されるため、リリースビルド前に正しく設定されていることを確認してください。

### CI/CD での設定

GitHub Actions のリリースワークフローでは、Repository Secret `ANDROID_APPLICATION_ID` から自動的にファイルが生成されます。

**設定手順:**
1. GitHub リポジトリの Settings → Secrets and variables → Actions を開く
2. Repository secret `ANDROID_APPLICATION_ID` を追加し、本番の applicationId を設定する

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
