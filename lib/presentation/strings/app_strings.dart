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
/// Issue #476 Phase 1 では **`SettingsScreen`（設定画面ルート）** の
/// 文字列を、Issue #836 Phase 2 では NG 設定編集画面 / NG ユーザー /
/// NG ワード画面の **固定 UI ラベル** を集約済み。
///
/// 継続課題として段階的に追加予定（Phase 3 候補）:
/// - コメント表示設定 / 読み上げ設定 / ユーザー管理設定 / お気に入りユーザー
/// - コメント画面の AppBar 周辺・SnackBar・ダイアログ
/// - ログイン / 放送一覧 / ライセンスページの固定文言
///
/// ## 集約判定基準（Phase 2 で確立）
/// 集約**する**:
/// - 画面タイトル・タブラベル・ボタンラベル・tooltip
/// - ダイアログタイトル / 本文 / 確認・キャンセルボタン
/// - 空状態メッセージ / 読み込み失敗時の本文
/// - **クライアント側ローカル検証エラー**（regex 不正 / 重複検出など、
///   API 応答に依存せず固定文で確定的に出るもの）
/// - 固定文言の SnackBar（操作完了通知など、引数のみが動的で本文は
///   テンプレート化できるもの）
///
/// 集約**しない**:
/// - API 応答に対する固定 SnackBar（例:「○○の更新に失敗しました」）。
///   これは Service 層のキー化として別 Issue に切り出す方針。一見
///   固定文だが「API 応答を契機に出る UI」は Service / Repository の
///   error mapping と一緒に扱うほうが翻訳カバレッジが揃う。
/// - domain 概念（NG カテゴリ説明、正規表現の意味論 等）。
///   `FilterCategoryStrings` のような domain 寄り namespace に分離。
/// - 既存 spec list / config と二重管理になるパターン
///   （`_ngDisplayToggleSpecs` 等の data-driven UI 構造体内の文言）。
///
/// ## 同一文言の複数 namespace 重複について
/// `'再試行'` `'キャンセル'` `'削除'` `'NG リストの読込みに失敗しました'`
/// 等は複数 sub-class に重複保持されるケースがある。これは
/// **意図的**で、i18n 段階で画面ごとに翻訳を分岐できる柔軟性を
/// 確保するため（英語ロケールでは「ダイアログ確認」と「リストアイテム
/// tooltip」で同一原文でも異なる訳語を選びたいケースが頻出）。
/// ある時点で「全画面で同じ訳でよい」と確定したラベルだけを共通
/// namespace（将来の `CommonStrings` 等）に集約する方針。本 PR では
/// その共通化判断は時期尚早と判定し、各 namespace に保持している。
///
/// ## getter / メソッドの命名規約
/// 役割サフィックスを揃えて、Phase 3 以降で同一画面内に追加するときの
/// 揺れを抑える:
/// - `xxxTitle`: 画面・ダイアログのタイトル（**名詞句**）
/// - `xxxMessage`: 述語付き文の本文（読み込み失敗・エラー説明など）
/// - `xxxContent`: ダイアログ本文（引数を含むなら `String` メソッド）
/// - `xxxConfirm` / `xxxCancel`: ダイアログ確定 / キャンセルボタン
/// - `xxxButton`: 一覧上部などの常設ボタンラベル
/// - `xxxTooltip`: アイコンボタンの `tooltip:` プロパティ
/// - `xxxSnackBar`: SnackBar に表示する文言（引数を含むなら `String` メソッド）
/// - `xxxLabel` / `xxxHint`: 入力欄のラベル / ヒント
/// - `xxxDescription`: 複数行の説明文（設定タイル下のサブテキスト等）
/// - `emptyMessage` / `loadFailedMessage` / `retryButton`: 状態系の固定 UI
///
/// ### 規約の適用範囲
/// 本セクションは Issue #836 (Phase 2) で確立。**新規追加分にのみ適用**し、
/// それ以前の Phase 1 由来 namespace の retrofit は別 Issue 扱い
/// （feature PR に retrofit を混ぜない CLAUDE.md 原則）。Phase 3 以降の
/// 追加では本規約に従う。
///
/// **規約と整合しない既存例**（retrofit 候補。本 PR では触らない）:
/// - `BroadcasterNgListStrings.emptyTitle = 'まだ放送者ごとの NG 設定は…'`
///   は完全文だが `Title` サフィックスのまま。新規追加なら `emptyMessage`
///   ／ `emptyDescription` を選ぶこと。
/// - `SettingsStrings.themeDescription` / `dataManagementDescription`
///   は本規約の `xxxDescription`（複数行説明）に該当する命名で問題なし。
///
/// ### 同一 namespace 内重複の扱い
/// 同一 namespace 内に同一文言が異なる getter として存在する（例:
/// `addButton == addDialogTitle == 'NGワード追加'`）のは i18n 化時に役割
/// ごとに別訳になり得るため。複数 namespace 重複と同じ理由で意図的に
/// 分離保持する。
///
/// ## ARB 移行を見据えた引数規約
/// 引数を含む文字列メソッドは将来 `flutter_localizations` + ARB に置き換え
/// られる前提で:
/// - **メソッド引数名は ARB プレースホルダ名と同一**になる扱い。
///   引数名のリネームは breaking change として扱う。
/// - **言語仕様上の留意**: 現状の引数は positional のため、Dart の
///   呼び出し側からは引数名が観測されず、引数名リネームは「呼び出し側
///   書き換え不要・ARB 化スクリプトが手動で結びつける必要あり」という
///   緩い契約として運用する。Phase 3 で named 引数化を検討する余地は
///   ある（ARB プレースホルダとの自動マッピング容易性とのトレードオフ）。
/// - **複数形が必要な文言**（例: 「N 件削除しました」）が出てきたら、
///   `int count` を引数として加え、`{count, plural, ...}` の ARB 形式に
///   素直に対応できるシグネチャを保つ。
/// - **引数前置の文言**（例: `'$id のNGを解除しました'`）は日本語固定
///   語順に依存しているため、ARB 化時には文全体を翻訳キー単位で再設計
///   する想定。byte-for-byte 維持テストはあくまで現行ロケールの固定で
///   あり、ARB 化で同じ文字列が出続けることは保証しない。
/// - **引数を囲む記号**（例: `「$pattern」`）は CJK 表記なので、ロケール
///   依存に翻訳キーごと差し替える想定。
abstract final class AppStrings {
  const AppStrings._();

  static const SettingsStrings settings = SettingsStrings._();
  static const BroadcasterNgListStrings broadcasterNgList =
      BroadcasterNgListStrings._();
  static const BroadcasterNgEditStrings broadcasterNgEdit =
      BroadcasterNgEditStrings._();
  static const NgUserListStrings ngUserList = NgUserListStrings._();
  static const NgWordListStrings ngWordList = NgWordListStrings._();
  static const TimeshiftStrings timeshift = TimeshiftStrings._();
  static const ConnectionStrings connection = ConnectionStrings._();
  static const CommentDisplaySettingsStrings commentDisplaySettings =
      CommentDisplaySettingsStrings._();
  static const UserDetailSheetStrings userDetailSheet =
      UserDetailSheetStrings._();
  static const CommentScreenStrings commentScreen = CommentScreenStrings._();
  static const BroadcastHistoryStrings broadcastHistory =
      BroadcastHistoryStrings._();
  static const ExtendBroadcastStrings extendBroadcast =
      ExtendBroadcastStrings._();
  static const AutoExtendBroadcastStrings autoExtendBroadcast =
      AutoExtendBroadcastStrings._();
  static const AppUpdateStrings appUpdate = AppUpdateStrings._();
}

/// GitHub リリース連動のバージョン更新通知・強制更新で使う文字列。
final class AppUpdateStrings {
  const AppUpdateStrings._();

  // --- 任意更新ダイアログ ---

  /// 新しい版がある旨のダイアログタイトル。
  String get optionalTitle => '新しいバージョンがあります';

  /// 任意更新ダイアログ本文。`version` は最新版（例 `1.2.0`）。
  String optionalMessage(String version) =>
      'バージョン $version が公開されています。最新版へ更新できます。';

  /// 更新へ進むボタン。
  String get updateButton => '更新する';

  /// 任意更新を見送るボタン。
  String get laterButton => '後で';

  // --- 強制更新ブロック画面 ---

  /// 強制更新ブロック画面のタイトル。
  String get forcedTitle => '更新が必要です';

  /// 強制更新ブロック画面の本文（最新版が判明している場合）。
  /// `version` は更新先の版。
  String forcedMessageWithVersion(String version) =>
      'このバージョンはサポートを終了しました。'
      'バージョン $version へ更新してご利用ください。';

  /// 強制更新ブロック画面の本文（最新版が判明していない場合）。
  String get forcedMessage =>
      'このバージョンはサポートを終了しました。'
      '最新版へ更新してご利用ください。';

  // --- 設定画面の手動確認タイル ---

  /// 設定画面タイルのタイトル。
  String get settingsTileTitle => 'アプリ情報・更新確認';

  /// 設定タイルのサブタイトル。`version` は現在の版。
  String settingsTileSubtitle(String version) => '現在のバージョン: $version';

  /// 手動確認中のスナックバー。
  String get checking => '更新を確認しています…';

  /// 最新版だったときのスナックバー。
  String get upToDate => 'お使いのバージョンは最新です';

  /// 確認できなかったとき（オフライン等）のスナックバー。
  String get checkUnavailable => '更新を確認できませんでした';

  /// 配布ページを開けなかったときのスナックバー。
  String get launchFailed => '更新ページを開けませんでした';
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
  // Issue #803 child-1: NG エントリは別タイルへ移行済み、コテハン管理 UI も
  // 該当画面には存在しないため、サブタイトルを実態（お気に入りユーザー）に
  // 合わせて更新する。
  String get userManagementTileSubtitle => 'お気に入りユーザー';

  // タイル: NG設定 (Issue #727 follow-up)
  // 一覧画面や編集画面の語彙に合わせ、設定一覧でも短い名称で統一する。
  String get ngFilterTileTitle => 'NG設定';
  // タイルが enabled の時は subtitle 自体を表示しない設計のため、
  // disabled 時に出す「未対応」 ラベルのみ AppStrings に保持する。
  String get ngFilterTileSubtitleDisabled => '未対応';

  /// NG設定編集画面（[BroadcasterNgEditScreen]）の AppBar タイトル。
  ///
  /// Issue #727 follow-up: `scopeLabel` には放送者名（解決できないときは
  /// 放送者ID）が入る。区切りは半角ハイフン + 半角スペース 1 つずつで、
  /// `name(id)` のような結合形ではなく純粋な放送者名を渡すことを想定する。
  /// `[ngFilterTileTitle]`（タイル名・一覧画面 AppBar）と同じ「NG設定」
  /// 表記で語彙連続を維持する。
  ///
  /// **Phase 3 移管予定**: 本 getter は Settings 画面のタイル文言と
  /// セットで Phase 1 に作られた歴史的経緯から `SettingsStrings` に
  /// 残置している。Phase 3 で「画面別 namespace 集約」を一貫させる際に
  /// `BroadcasterNgEditStrings.screenTitle` 等（命名規約セクションの
  /// `xxxTitle` 規約に従う）へ移管する候補。**本 PR (#836) で移管しない理由**:
  /// 本 PR は Phase 2 の literal 集約をスコープとし、Phase 3 で
  /// `comment_screen` 等の他画面と一括して命名・移管方針を確定させた方が
  /// 移管時の grep 範囲・widget テスト更新範囲を 1 PR で管理できる。
  /// 単独で先行移管すると Phase 3 着手時に再度 doc 整合の議論が発生する。
  ///
  /// **Phase 3 移管手順**（着手時のチェックリスト）:
  /// 1. `BroadcasterNgEditStrings` に `screenTitle(String scopeLabel)` を追加
  /// 2. `grep -rn 'AppStrings.settings.ngEditScreenTitle' lib/ test/` で参照箇所を洗い出し
  /// 3. 呼び出し側を `AppStrings.broadcasterNgEdit.screenTitle(...)` に置換
  /// 4. `app_strings_test.dart` の byte-equality テストも新 getter 側に追加
  /// 5. 既存 widget テスト (`broadcaster_ng_edit_screen_test.dart` の
  ///    `find.text('NG設定 - ...')`) は AppStrings 経由表現に統一
  /// 6. 本 getter (`SettingsStrings.ngEditScreenTitle`) は Phase 3 完了後の
  ///    cleanup PR で削除
  String ngEditScreenTitle(String scopeLabel) => 'NG設定 - $scopeLabel';

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

/// `BroadcasterNgListScreen`（放送者別 NG 設定一覧）で使用する文字列。
final class BroadcasterNgListStrings {
  const BroadcasterNgListStrings._();

  String get emptyTitle => 'まだ放送者ごとの NG 設定はありません';
  String get emptyDescription =>
      'コメント画面で NGユーザーを追加するか、現在接続中の放送者の '
      'NG設定を作成すると、その放送者の設定として記録されます';
  String get createActiveTitle => '現在接続中の放送者の NG設定を作成';
  String get activeBadge => '現在接続中';
}

/// Issue #836 Phase 2: `BroadcasterNgEditScreen`（NG設定編集画面）で
/// 使用する固定 UI ラベルの集約。
///
/// 集約対象は「画面タイトル・タブラベル・固定説明文」のみで、動的な
/// API エラーや domain 概念（NG カテゴリ等）はここでは扱わない（Issue
/// #836 のスコープ方針に従う）。AppBar タイトルは `SettingsStrings`
/// の `ngEditScreenTitle` 側に既に集約済みのため重複しない。
final class BroadcasterNgEditStrings {
  const BroadcasterNgEditStrings._();

  /// 「NGユーザー」タブのラベル。
  String get usersTabLabel => 'NGユーザー';

  /// 「NGワード」タブのラベル。
  String get wordsTabLabel => 'NGワード';

  /// テンプレートスコープ編集時に画面上部へ表示する説明バナー。
  ///
  /// 動的引数なし（"テンプレート: 〜" の固定文）なので getter で提供する。
  String get templateBanner => 'テンプレート: 新規放送者の初期値として使われます';
}

/// Issue #836 Phase 2: `NgUserListView`（放送者別 NG ユーザー一覧）で
/// 使用する固定 UI ラベルの集約。
///
/// 集約対象は「画面の固定 UI ラベル（ダイアログタイトル / ボタンラベル /
/// 空状態メッセージ / load 失敗時の本文）」のみ。動的な API エラーや
/// domain 概念（NG カテゴリ等）はスコープ外。引数を含む確認/通知
/// メッセージは戻り値 `String` のメソッドとして提供する（バイト一致を
/// 担保するため文字列リテラルの前後改行・記号は原文通り保持）。
final class NgUserListStrings {
  const NgUserListStrings._();

  // 削除確認ダイアログ
  // NOTE: cancel ラベルは `showConfirmDialog`（`presentation/widgets/
  // confirm_dialog.dart`）が widget 側のデフォルト文言を持つため、本
  // クラスでは保持しない。`NgWordListStrings.deleteDialogCancel` と
  // 非対称に見えるが、widget 実装の差（`showConfirmDialog` vs 直接
  // `AlertDialog`）に起因する意図的な差異。
  String get unregisterDialogTitle => 'NG解除';
  String unregisterDialogContent(String userId) =>
      'ユーザーID「$userId」のNG登録を解除しますか？';
  String get unregisterDialogConfirm => '解除';

  /// NG解除成功時の SnackBar 文言。動的引数 `userId` を含むため
  /// メソッドとして提供する。
  String unregisteredSnackBar(String userId) => '$userId のNGを解除しました';

  // 読み込み失敗時の本文
  // NOTE: `loadFailedMessage` / `retryButton` は `NgWordListStrings` にも
  // 同一文言で存在する。i18n 時に画面ごとに別訳を選べる柔軟性のため
  // 意図的に重複保持している（クラスドキュメント参照）。
  String get loadFailedMessage => 'NG リストの読込みに失敗しました';
  String get retryButton => '再試行';

  // 空状態
  String get emptyMessage => 'NGユーザーIDは登録されていません';

  // リストアイテムの削除ボタン tooltip
  // NOTE: `unregisterDialogTitle` と同一文言だが、tooltip は短い動詞句
  // （IconButton ラベル）として、ダイアログタイトルは「ユーザーIDを…
  // 解除しますか？」の見出しとして機能する。日本語では同一語形でも、
  // 英訳時には "Unregister"（命令形）と "Unregister NG user"（タイトル）
  // のように分岐し得るため別 getter に分離して保持する。
  String get removeTooltip => 'NG解除';
}

/// Issue #836 Phase 2: `NgWordListView`（放送者別 NG ワード一覧）で
/// 使用する固定 UI ラベルの集約。
///
/// 集約対象は「画面の固定 UI ラベル」のみ。引数を含む確認/通知
/// メッセージは戻り値 `String` のメソッドとして提供する（バイト一致を
/// 担保するため文字列リテラルの前後改行・記号は原文通り保持）。
final class NgWordListStrings {
  const NgWordListStrings._();

  // 削除確認ダイアログ
  String get deleteDialogTitle => 'NGワード削除';
  String deleteDialogContent(String pattern) => '「$pattern」を削除しますか？';
  String get deleteDialogCancel => 'キャンセル';
  // NOTE: `deleteDialogConfirm` と `deleteTooltip` は同一文言だが、
  // ダイアログ確定ボタンと IconButton tooltip は i18n 時に別訳になる
  // 言語が想定されるため別 getter として保持する。
  String get deleteDialogConfirm => '削除';

  /// 削除成功時の SnackBar 文言。動的引数 `pattern` を含むため
  /// メソッドとして提供する。
  String deletedSnackBar(String pattern) => '「$pattern」を削除しました';

  // 追加 UI（ボタン + ダイアログ）
  String get addButton => 'NGワード追加';
  String get addDialogTitle => 'NGワード追加';
  String get addDialogFieldLabel => 'パターン（部分一致）';
  String get addDialogFieldHint => '例: スパム';
  String get addDialogConfirm => '追加';

  /// 入力検証エラー（regex として無効）の SnackBar 文言。
  /// クライアント側のローカル検証結果のため AppStrings に集約する
  /// （クラスドキュメントの集約判定基準を参照）。
  ///
  /// **設計意図**: あえて `FormatException.message` の詳細を露出させない。
  /// 「パターンのどこが無効か」は内部実装（regex パーサのエラー位置等）
  /// に依存し、ユーザーが直接アクションを取れない情報なので、固定文の
  /// 「無効なパターンです」だけ表示し、詳細はユーザーに見せない。
  String get invalidPatternSnackBar => '無効なパターンです';

  /// 入力検証エラー（重複）の SnackBar 文言。同上。
  String get duplicatePatternSnackBar => '同じパターンが既に登録されています';

  // 読み込み失敗時の本文
  // NOTE: `NgUserListStrings` にも同一文言で存在する。i18n 時に画面
  // ごとに別訳を選べる柔軟性のため意図的に重複保持している。
  String get loadFailedMessage => 'NG リストの読込みに失敗しました';
  String get retryButton => '再試行';

  // 空状態
  String get emptyMessage => 'NGワードは登録されていません';

  // リストアイテムの削除ボタン tooltip
  String get deleteTooltip => '削除';
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

/// `CommentDisplaySettingsScreen`（コメント表示設定画面）で使用する文字列の集約。
///
/// 画面全体の文字列集約は継続課題だが、Issue #668 で追加された
/// 「過去コメント取得件数」の補足説明は新規追加テキストのため、
/// 先行して本クラスにまとめる。
final class CommentDisplaySettingsStrings {
  const CommentDisplaySettingsStrings._();

  /// 過去コメント取得件数ドロップダウンの下に表示する補足説明。
  ///
  /// PR #652 以降、取得件数（`historyCount`）と表示保持数
  /// （`displayCapacity = historyCount + liveBuffer`）が分離されたため、
  /// 「100 件にしたのに画面に 5100 件出る」という誤解を避けるために
  /// 設定の意味と表示保持数の関係を明示する。
  ///
  /// [liveCommentBufferSize] には domain 層の
  /// `timelineLiveCommentBufferSize` をそのまま渡すこと。ここでハードコード
  /// してしまうと、将来 buffer サイズを変更した際に description だけ
  /// 古い値を表示し続けるドリフトが発生する（Issue #668 レビュー指摘）。
  String pastCommentFetchCountDescription({
    required int liveCommentBufferSize,
  }) =>
      '初回接続時にまとめて取得する過去コメント数の上限です。\n'
      '取得後の新着コメントも追加で表示されます'
      '（表示保持数 = 取得数 + 約 $liveCommentBufferSize 件）。';
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

  /// 同じ URL の再試行で解消しない種別のエラー（権限不足など）時に、
  /// リトライボタンの代わりに表示する案内。Issue #639 cause 5。
  String get nonRetryableNotice => 'このタイムシフトは再試行しても取得できません。';

  /// タイムシフト未対応ダイアログのタイトル。
  ///
  /// Issue #639 / #654 / #173 のフォローアップ。viewUri 取得経路の確立まで
  /// 取得機能を一時無効化する暫定 UI のための文言。実装が整い次第
  /// `kTimeshiftFetchEnabled` フラグを true に戻して再有効化する。
  String get unsupportedDialogTitle => 'タイムシフトは現在未対応です';

  /// タイムシフト未対応ダイアログの本文。
  ///
  /// 「将来的に対応予定」であることをユーザに伝え、リトライ誘導や
  /// 内部エラー表示を抑止する。生ログエラーへの誤遷移を避けるための措置。
  String get unsupportedDialogBody =>
      'タイムシフト（過去放送）のコメント取得は現在対応していません。\n'
      '今後のアップデートで対応予定です。';

  /// 未対応ダイアログの確認ボタン。
  String get unsupportedDialogConfirm => 'OK';
}

/// `UserDetailSheet`（ユーザー詳細シート）で使用する文字列の集約。
///
/// Issue #778 Phase 2 の対象。PR #775（カスタムカラー追加）で増えた
/// 色選択 UI 文言と、それ以前から存在する固定ラベル（タイトル・空状態・
/// NG 操作・コテハンセクション・コメント履歴件数）をまとめて集約する。
/// 既定ロケール（日本語）の表示はバイト完全一致で現状維持とする。
final class UserDetailSheetStrings {
  const UserDetailSheetStrings._();

  // ヘッダー
  String get title => 'ユーザー詳細';

  /// 「ID: {userId}」形式のヘッダー行。
  String userIdLine(String userId) => 'ID: $userId';

  /// 「コテハン: {nickname}」形式のヘッダー行。
  /// コテハン未登録時はそもそも表示されないため、引数は非 null 前提。
  String userNicknameLine(String nickname) => 'コテハン: $nickname';

  /// 「名前: {resolvedUserName}」形式のヘッダー行。
  String userNameLine(String resolvedUserName) => '名前: $resolvedUserName';

  // NG ユーザートグル
  String get ngButtonRegister => 'NG登録';
  String get ngButtonUnregister => 'NG解除';

  // コメント履歴
  String get noCommentsInBroadcast => 'この放送でのコメントはありません';

  /// 「コメント履歴（N件）」形式の見出し。
  String commentHistoryCount(int count) => 'コメント履歴（$count件）';

  // コメント色セクション
  String get commentColorSectionTitle => 'コメント色';
  String get commentColorReset => 'リセット';
  String get commentColorResetSemanticsLabel => 'コメント色をリセット';

  // カスタムカラー（PR #775 由来）
  String get customColorSelectedSemanticsLabel => 'カスタムカラー 選択中';
  String get customColorSelectSemanticsLabel => 'カスタムカラーを選択';
  String get customColorDialogTitle => 'カスタムカラー';
  String get customColorDialogCancel => 'キャンセル';
  String get customColorDialogApply => '適用';

  // コテハン（ニックネーム）セクション
  String get nicknameSectionTitle => 'コテハン';
  String get nicknameUnregistered => '未登録';
  String get nicknameEditSemanticsLabel => 'コテハンを変更';
  String get nicknameAddSemanticsLabel => 'コテハンを登録';
  String get nicknameEditButton => '変更';
  String get nicknameAddButton => '登録';
  String get nicknameRemoveSemanticsLabel => 'コテハンを削除';
  String get nicknameRemoveButton => '削除';
  String get nicknameDialogTitle => 'コテハン登録';
  String get nicknameDialogFieldLabel => 'コテハン';
  String get nicknameDialogFieldHint => 'ニックネームを入力';
  String get nicknameDialogCancel => 'キャンセル';
  String get nicknameDialogSave => '保存';
}

/// `CommentScreen`（コメント画面）で使用する文字列の集約。
///
/// Issue #778 Phase 2 の対象。PR #776（コメントスクロール順永続化）で
/// AppBar に追加されたソート切替ボタンの tooltip を集約する。本 PR では
/// それ以外の `CommentScreen` 文言は触らない（Phase 3 以降で別 Issue 化）。
final class CommentScreenStrings {
  const CommentScreenStrings._();

  /// 現在「昇順（古い順）」表示中に、降順（新しい順）へ切り替える誘導 tooltip。
  String get sortToggleToDescending => '新しい順に切替';

  /// 現在「降順（新しい順）」表示中に、昇順（古い順）へ切り替える誘導 tooltip。
  String get sortToggleToAscending => '古い順に切替';
}

/// Issue #766: 過去放送のコメント統計を再アクセスできる履歴ビューで使用する文字列。
final class BroadcastHistoryStrings {
  const BroadcastHistoryStrings._();

  // 設定画面のタイル
  String get settingsTileTitle => '放送履歴';
  String get settingsTileSubtitle => '過去放送のコメント統計を振り返る';

  // 画面 AppBar
  String get screenTitle => '放送履歴';
  String get clearAllTooltip => '履歴を全て削除';

  // 空状態
  String get emptyTitle => 'まだ履歴はありません';
  String get emptyDescription => '自分の放送が終了したタイミングで自動的に記録されます。';

  // プライバシ説明（端末ローカル保存）
  String get privacyNote => 'この履歴は端末内のみに保存され、外部に送信されません。';

  // 削除ダイアログ（個別）
  String get removeOneDialogTitle => 'この履歴を削除';
  String get removeOneDialogMessage => 'この 1 件の放送履歴を削除します。よろしいですか？';
  String get removeOneDialogCancel => 'キャンセル';
  String get removeOneDialogConfirm => '削除';
  String get removeOneTooltip => 'この履歴を削除';

  // 削除ダイアログ（全件）
  String get clearAllDialogTitle => '履歴を全て削除';
  String get clearAllDialogMessage => '保存されている全ての放送履歴を削除します。よろしいですか？';
  String get clearAllDialogCancel => 'キャンセル';
  String get clearAllDialogConfirm => '削除';
  String get clearAllSnackBar => '放送履歴を全て削除しました';
  String get clearAllFailedSnackBar => '放送履歴の削除に失敗しました';
  String get removeOneSnackBar => '履歴を削除しました';
  String get removeOneFailedSnackBar => '履歴の削除に失敗しました';

  // 詳細シート
  String get detailLvLabel => '番組ID';
  String get detailTotalCommentsLabel => '総コメント数';
  String get detailUniqueUsersLabel => 'ユニークユーザー数';
  String get detailDurationLabel => '配信時間';
  String get detailPeakLabel => 'ピーク時間帯';
  String detailPeakValue({required String label, required int count}) =>
      '$label (${count}コメント)';
  String get detailHighlightTitle => '放送の盛り上がり';
  String detailHighlightLine({
    required int index,
    required String label,
    required int count,
  }) => 'ピーク$index: $label (${count}コメント/分)';
  String get openProgramPageButton => '公式番組ページを開く';
  String get launchFailedSnackBar => 'リンクを開けませんでした';

  /// 一覧タイルのサブタイトル: 「lv | 記録日時 | 総コメ数 / ユニーク数」。
  String tileSubtitle({
    required String lv,
    required DateTime recordedAt,
    required int totalComments,
    required int uniqueUserCount,
  }) {
    final DateTime local = recordedAt.toLocal();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final String date = '${local.year}/${pad2(local.month)}/${pad2(local.day)}';
    final String time = '${pad2(local.hour)}:${pad2(local.minute)}';
    return '$lv  $date $time  '
        'コメ:$totalComments / 人:$uniqueUserCount';
  }
}

/// Issue #872: 配信中に放送を任意分数で延長するメニュー / ダイアログで使う文字列。
final class ExtendBroadcastStrings {
  const ExtendBroadcastStrings._();

  /// AppBar オーバーフローメニューの項目ラベル。
  String get menuItem => '放送を延長';

  /// ダイアログ AppBar タイトル。
  String get dialogTitle => '放送を延長';

  /// プルダウンの上に置くフィールドラベル。
  String get fieldLabel => '延長する時間';

  /// 各選択肢の表示文字列（30 分 / 60 分 等）。
  String optionMinutes(int minutes) => '$minutes 分';

  /// ダイアログ確定ボタン。
  String get confirm => '延長する';

  /// ダイアログキャンセルボタン。
  String get cancel => 'キャンセル';

  /// 延長 API 成功時の SnackBar 文言。
  String success(int minutes) => '放送を $minutes 分延長しました';

  /// 延長 API 失敗時の SnackBar 文言（成功 / 失敗の 2 値のみ表示）。
  String get failure => '放送を延長できませんでした';
}

/// Issue #875: 自動延長機能のメニュー項目で使う文字列。
/// Issue #876: 自動延長 Timer 動作のコメ欄システムメッセージ文言を追加。
final class AutoExtendBroadcastStrings {
  const AutoExtendBroadcastStrings._();

  /// AppBar オーバーフローメニューの項目ラベル。
  String get menuItem => '自動延長';

  /// 自動延長 API 成功時にコメ欄へ流すシステムメッセージ文言。
  /// `{minutes}` は実際に伸びた分数。
  String successMessage(int minutes) => '自動延長が成功しました（+$minutes 分）';

  /// 自動延長 API がリトライ全失敗した時にコメ欄へ流すメッセージ。
  /// 個別の理由（上限到達 / ネットワーク等）は付記せず簡潔に通知する
  /// ことで、ユーザーが「自分で対処すべきこと」（手動延長／放送終了）
  /// に集中できるようにする。
  String get failureMessage => '自動延長に失敗しました';
}
