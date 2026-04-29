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

## リリース署名の設定

リリースビルドの署名には本番用キーストアが必要です。
`key.properties` が存在しない場合はデバッグ鍵で署名されます（ローカル開発用）。

### キーストアの生成

```bash
# android/keystore/ ディレクトリを作成
mkdir -p android/keystore

# リリース用キーストアを生成
keytool -genkeypair \
  -alias release \
  -keyalg EC \
  -groupname secp256r1 \
  -validity 10000 \
  -storetype PKCS12 \
  -dname "CN=comerune" \
  -keystore android/keystore/release.jks
```

- **鍵アルゴリズム**: ECDSA（secp256r1 / P-256）。RSA 3072bit 相当のセキュリティを小さな鍵サイズで実現する
- **有効期限**: 10000日（約27年）。Google Play は 2033-10-22 以降に期限切れとなる鍵を拒否するため、十分な期間を設定する
- **keystore / jks ファイルは `.gitignore` 対象** — リポジトリにコミットされない

### key.properties の設定

```bash
# テンプレートをコピー
cp android/key.properties.example android/key.properties
chmod 600 android/key.properties

# 各値を実際のパスワード・パスに書き換える
```

| プロパティ | 説明 |
|---|---|
| `storePassword` | キーストアのパスワード |
| `keyPassword` | 鍵エントリのパスワード（PKCS12 では `storePassword` と同じ値を設定する） |
| `keyAlias` | 鍵のエイリアス名（上記コマンドでは `release`） |
| `storeFile` | キーストアファイルへの相対パス（`build.gradle.kts` の `file()` で解決される） |

> ⚠️ **`key.properties.example` の値（`your_store_password` など）をそのまま残さないでください。**
> プレースホルダーのままだと release 署名が完了せず、Gradle が **debug 鍵で sign された "release" APK** を生成します。
> 実害例: 別 keystore で署名された APK を後でアップデートインストールしようとすると `App not installed as package conflicts with an existing package` で失敗する／Play Console にアップロード後にアップロード鍵が固定されて差し替え不可になる。
> `make build-release` は実行前に `scripts/verify-release-keystore.sh` で keystore が **実際に開けるか** を検証し、失敗時は abort します。

### キーストアのバックアップと復旧

キーストアを紛失すると、同じ署名の APK を二度と生成できなくなります。
既存ユーザーはアプリを再インストールする必要が生じます。

**推奨バックアップ方法:**
- クラウドストレージ（AWS KMS / GCP KMS 等）に暗号化して保存
- USB ドライブ等のオフラインメディアにバックアップし、物理的に安全な場所に保管
- 複数の場所に冗長に保管する

**復旧手順:**
1. バックアップから `release.jks` を `android/keystore/` にリストア
2. `android/key.properties` のパスワードが正しいことを確認
3. `flutter build apk --release` で署名されたビルドが生成されることを確認

### CI/CD での署名設定

GitHub Actions のリリースワークフローでは、以下の Repository Secrets からキーストアを復元して署名します。

| Secret 名 | 内容 |
|---|---|
| `ANDROID_SIGNING_KEYSTORE_BASE64` | キーストアファイル（.jks）の Base64 エンコード |
| `ANDROID_SIGNING_KEY_PASSWORD` | 鍵エントリのパスワード（PKCS12 では `ANDROID_SIGNING_STORE_PASSWORD` と同じ値） |
| `ANDROID_SIGNING_STORE_PASSWORD` | キーストアのパスワード |

鍵エイリアスは `release` 固定でワークフローに直接記述されているため、Secret の設定は不要です。

**Secrets の設定手順:**
1. キーストアを Base64 エンコード
   - GNU/Linux: `base64 -w 0 android/keystore/release.jks`
   - macOS: `base64 android/keystore/release.jks | tr -d '\n'`
2. GitHub リポジトリの Settings → Secrets and variables → Actions を開く
3. 上記 3 つの Repository Secrets を追加する

### ADI Verification 用 APK

Android Developer Console の所有権確認用 APK は、通常のリリースワークフローに混ぜず、専用の GitHub Actions workflow
`.github/workflows/android-developer-verification.yml` で生成します。

- workflow 名: `ADI Verification`
- 想定用途: `adi-registration.properties` を含む確認専用 APK の生成
- 推奨設定: GitHub の `environment` `android-developer-verification` を作成し、以下の secrets を **environment secrets** として設定する
  - `ANDROID_APPLICATION_ID`
  - `ANDROID_SIGNING_KEYSTORE_BASE64`
  - `ANDROID_SIGNING_KEY_PASSWORD`
  - `ANDROID_SIGNING_STORE_PASSWORD`
  - `ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT`

`ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT` は、所有権確認用 APK の `assets/adi-registration.properties`
に埋め込まれる前提の値です。互換目的で旧名 `ANDROID_ADI_REGISTRATION_SNIPPET` も読めますが、新規設定では
`ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT` を使用してください。

この workflow で生成した APK は所有権確認専用です。通常配布用の APK 生成には使わず、検証完了後は通常の `Release` workflow を利用してください。
GitHub Actions で生成した場合は、artifact `android-developer-verification-apk` をダウンロードして利用します。

ローカルで手動生成する場合は、次の前提を満たしたうえで `make` ターゲットを利用できます。

- `android/app_id.properties` がある（`Application ID の設定` を参照）
- `android/key.properties` がある（`リリース署名の設定` を参照）
- `android/key.properties` の `storeFile` が指す keystore ファイルが存在する
- `android/app/src/main/assets/adi-registration.properties` が **存在しない**（このターゲットがビルド時に一時生成するため）
- 確認文字列を保存したローカルファイルがある

```bash
ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE=/path/to/adi-registration.properties \
make build-adi-verification
```

前提が揃っていない場合、スクリプトは **不足分をすべてまとめて表示し** 、それぞれに修正コマンド例と該当ドキュメント節を案内します。
表示された項目を解消してから再実行してください。

生成物:
- `build/app/outputs/flutter-apk/comerune-android-developer-verification-arm64.apk`

このターゲットは `scripts/build-android-developer-verification-apk.sh` を呼び出し、ビルド時だけ
`android/app/src/main/assets/adi-registration.properties` を一時生成して完了時に削除します。
ビルド失敗時には未検証の `app-release.apk` も削除されるため、verification 用 APK と通常リリース APK が混在することはありません。
通常の `make build-release` は `scripts/guard-no-adi-registration-asset.sh` を通すため、verification 用 asset が残っている場合は失敗します。

### Google Play App Signing

Google Play App Signing の利用を推奨します。

- Google がアプリ署名鍵を管理し、開発者はアップロード鍵のみ保持する
- アップロード鍵を紛失しても Google に再設定を依頼できる
- 鍵のローテーションが可能（通常の署名では不可）

**導入手順:**
1. Google Play Console でアプリを作成後、App Signing を有効化
2. Google が提供する署名鍵証明書に基づいてアップロード鍵をエクスポート
3. 以降、本リポジトリの署名設定はアップロード鍵用として使用する

詳細は [Google Play App Signing ドキュメント](https://developer.android.com/studio/publish/app-signing#app-signing-google-play) を参照してください。

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
make build-adi-verification  # Android Developer Verification 用APK
make test            # テスト実行
make format          # 安全フォーマット（既存の作業差分以外は自動で戻す）
make format-all      # 全体フォーマット（専用PR向け）
make check           # 静的解析 + フォーマット + テスト（まとめて）
```

## フォーマット運用の推奨

- 通常のIssue対応では `make format` を使い、スコープ外の大量差分混入を防ぐ
- リポジトリ全体の整形を行う場合は `make format-all` を使い、**機能変更と分離した別PR** で実施する
