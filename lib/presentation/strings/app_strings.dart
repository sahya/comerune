/// UI 文字列を集約する定数クラス（i18n 対応準備）。
///
/// 本クラスは将来の多言語対応を見据え、UI にハードコードされていた
/// 日本語文字列を段階的に集約するための入口となる。
///
/// ## 方針
/// - 形式: 素朴な定数 class（getter / メソッド）
///   （`flutter_localizations` + ARB 案は将来移行時に検討する）
/// - 既定ロケールの表示は**バイト完全一致**で現状維持とする
/// - 引数を含む動的文字列（例: `"フォントサイズ: Npx"`）は関数として提供し、
///   単純な `const` 展開による文法崩れを避ける
/// - API 応答由来の動的メッセージや例外テキストは UI 定数ではないため
///   ここでは扱わない
///
/// ## 使い方
/// ```dart
/// Text(AppStrings.settings.title)
/// Text(AppStrings.settings.commentFontSizeSubtitle(14))
/// ```
///
/// ## 追加手順（開発者向け）
/// 1. 対象画面で使われているハードコード文字列を洗い出す
/// 2. 命名規則: 画面名 → ネストクラス、項目名 → `camelCase` 定数
/// 3. 引数を含む文字列は戻り値 `String` のメソッドとして追加する
/// 4. 既存テストで文字列 match しているものが壊れないか確認する
/// 5. 既定ロケールの見た目が変わらないことを widget テストで担保する
///
/// ## スコープ
/// 現時点（Issue #476 Phase 1）では **`SettingsScreen`（設定画面ルート）**
/// の文字列のみを集約している。他画面の文字列は継続課題として段階的に
/// 追加予定（下位画面: コメント表示設定・読み上げ設定・ユーザー管理設定、
/// ならびに SnackBar・ダイアログ等）。
abstract final class AppStrings {
  const AppStrings._();

  static const SettingsStrings settings = SettingsStrings._();
  static const TimeshiftStrings timeshift = TimeshiftStrings._();
  static const ConnectionStrings connection = ConnectionStrings._();
}

/// `SettingsScreen` で使用する文字列の集約。
final class SettingsStrings {
  const SettingsStrings._();

  // AppBar
  String get title => '設定';

  // セクション: アカウント
  String get accountSectionTitle => 'ニコニコアカウント';
  String get accountLoggedInLabel => 'ログイン済み';
  String get accountLoginRequired => 'コメント取得にはログインが必要です';
  String get accountLoginButton => 'ニコニコにログイン';
  String get accountLogoutButton => 'ログアウト';
  String get logoutDialogTitle => 'ログアウト';
  String get logoutDialogMessage => 'ログアウトしますか？再度ログインが必要になります。';
  String get logoutDialogCancel => 'キャンセル';
  String get logoutDialogConfirm => 'ログアウト';
  String get logoutSnackBar => 'ログアウトしました';

  // セクション: テーマ
  String get themeSectionTitle => 'テーマ';
  String get themeDropdownLabel => '配色テーマ';
  // 改行は UI の見た目をバイト完全一致で維持するため原文通り保持する。
  String get themeDescription =>
      'ダークモードは夜間の視認性を向上します。\n'
      '色覚テーマは色の区別が難しい方に配慮した配色です。';

  // タイル: コメント表示設定
  String get commentDisplayTileTitle => 'コメント表示設定';

  /// コメント表示タイルのサブタイトル: 現在のフォントサイズを表示する。
  /// 引数を含む動的文字列のため関数として提供する。
  String commentFontSizeSubtitle(int fontSizePx) => 'フォントサイズ: ${fontSizePx}px';

  // タイル: 読み上げ設定
  String get ttsTileTitle => '読み上げ設定';
  String ttsAutoReadSubtitle({required bool enabled}) =>
      enabled ? '自動読み上げ: ON' : '自動読み上げ: OFF';

  // タイル: ユーザー管理
  String get userManagementTileTitle => 'ユーザー管理';
  String get userManagementTileSubtitle => 'お気に入り・コテハン';

  // セクション: データ管理
  String get dataManagementSectionTitle => 'データ管理';
  String get exportSettingsButton => '設定をエクスポート';
  String get importSettingsButton => '設定をインポート';
  String get dataManagementDescription => 'JSON形式で設定のバックアップ・復元ができます。';

  String get exportFailedSnackBar => '設定のエクスポートに失敗しました';
  String get importDialogTitle => '設定のインポート';
  String get importDialogMessage => '現在の設定がインポートしたデータで上書きされます。よろしいですか？';
  String get importDialogCancel => 'キャンセル';
  String get importDialogConfirm => 'インポート';
  String get importSuccessSnackBar => '設定をインポートしました';
  String get importInvalidFileSnackBar => '無効な設定ファイルです';
  String get importFailedSnackBar => '設定のインポートに失敗しました';

  // タイル: ライセンス
  String get licenseTileTitle => 'ライセンス';
  String get licenseTileSubtitle => '第三者ライブラリのライセンス情報';

  /// `showLicensePage` に渡すアプリ名。ブランド名のため**多言語対応時も翻訳しない**。
  /// 将来的には `package_info_plus` の `PackageInfo.appName` から動的に取得する
  /// リファクタリングを検討する（本 PR のスコープ外 — 挙動は既存踏襲）。
  String get licenseApplicationName => 'comerune';

  // セクション: デバッグ
  String get debugSectionTitle => 'デバッグ';
  String get debugModeSwitchTitle => 'デバッグモード';
}

/// 接続エラーのスナックバー等で使用する文字列の集約。
///
/// 再試行可能/不可の案内文は、
/// [ConnectionErrorCodeExtension.isRetryable] の分類と対応する。
final class ConnectionStrings {
  const ConnectionStrings._();

  /// 再接続ボタンで回復し得るエラー時の誘導文（末尾に連結して使用する）。
  String get retryGuidance => '再接続ボタンで再試行できます。';

  /// 再接続では回復しないエラー時の案内文（末尾に連結して使用する）。
  String get nonRetryableNotice => '再接続しても解消しません。';
}

/// タイムシフトコメント取得 UI の文字列。
final class TimeshiftStrings {
  const TimeshiftStrings._();

  String get fetch500 => '500件取得';
  String get fetch1000 => '1000件取得';
  String get fetchAll => '全件取得';
  String get cancel => 'キャンセル';
  String fetchedCount(int count) => '取得済み: $count件';
  String get fetching => '取得中...';
  String get fetchComplete => '取得完了';
  String get fetchError => '取得に失敗しました';
  String get retry => '再試行';
}
