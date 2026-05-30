/// インストール元（`PackageInfo.installerStore`）から、アプリ内のバージョン
/// 更新通知・強制更新を有効にしてよいかを判定する pure function。
///
/// ## 設計意図
/// Google Play ストア等の管理ストアは**自身の仕組みで更新を配信する**ため、
/// アプリ内で GitHub Releases へ誘導すると次の問題が起きる:
///
/// - **Google Play デベロッパーポリシー違反**: Play 外への更新導線を禁止
/// - **二重更新 UX**: ストア通知とアプリ内通知が並行して出てユーザーが混乱
///
/// 本ゲートは「インストール元が既知の管理ストア」なら更新機能を無効化する。
/// サイドロード（直接配布 APK・GitHub Releases 経由のインストール等）は
/// `installerStore` が null か未知の値になるため有効のまま。
///
/// ## ガードレール構成
/// 本ゲートはランタイム最終防衛（層 2）。層 1 は `main.dart` の
/// `bool.fromEnvironment('APP_UPDATE_ENABLED')`（ビルド時抑止）。層 1 で
/// 明示的に OFF にすれば層 2 は無関係に何も起きない。層 1 を ON のままで
/// うっかり管理ストアに公開しても、層 2 が自動で無効化する。
library;

/// 既知の「自前で更新を配信する」アプリストアのインストーラパッケージ名。
///
/// ここに無いインストール元（サイドロード・adb 等）は更新機能を**許可**する。
/// 将来別ストアに公開する際は追加で対応する。
const Set<String> kManagedInstallerPackages = <String>{
  'com.android.vending', // Google Play
  'com.google.android.feedback', // Google Play（旧）
  'com.amazon.venezia', // Amazon Appstore
  'org.fdroid.fdroid', // F-Droid
  'org.fdroid.fdroid.privileged', // F-Droid Privileged Extension
  'com.sec.android.app.samsungapps', // Samsung Galaxy Store
  'com.huawei.appmarket', // Huawei AppGallery
};

/// [installerStore] がアプリ内更新を許可してよいインストール元か判定する。
///
/// - null / 空文字 → 不明（サイドロード扱い）で許可
/// - 既知の管理ストアパッケージ → **拒否**
/// - その他 → 許可（adb / ファイラ等のサイドロード経路）
bool isAppUpdateAllowedForInstaller(String? installerStore) {
  if (installerStore == null || installerStore.isEmpty) {
    return true;
  }
  return !kManagedInstallerPackages.contains(installerStore);
}
