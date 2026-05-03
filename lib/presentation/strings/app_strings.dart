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
  static const BroadcasterNgListStrings broadcasterNgList =
      BroadcasterNgListStrings._();
  static const TimeshiftStrings timeshift = TimeshiftStrings._();
  static const ConnectionStrings connection = ConnectionStrings._();
  static const CommentDisplaySettingsStrings commentDisplaySettings =
      CommentDisplaySettingsStrings._();
  static const UserDetailSheetStrings userDetailSheet =
      UserDetailSheetStrings._();
  static const CommentScreenStrings commentScreen = CommentScreenStrings._();
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
