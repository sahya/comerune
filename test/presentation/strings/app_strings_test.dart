import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/strings/app_strings.dart';

void main() {
  group('AppStrings.settings (byte-for-byte 既定ロケール維持の回帰防止)', () {
    // 本テストは「i18n 準備として抽出した文字列が、
    // 既定ロケール（日本語）で従来と寸分違わず表示される」ことを
    // 文字列単位で固定する。将来の翻訳追加で日本語側が書き換えられた際、
    // 意図しない変更をレビューで検出できる。
    test('AppBar / セクションタイトルが既存の文言と一致する', () {
      expect(AppStrings.settings.title, '設定');
      expect(AppStrings.settings.accountSectionTitle, 'ニコニコアカウント');
      expect(AppStrings.settings.themeSectionTitle, 'テーマ');
      expect(AppStrings.settings.dataManagementSectionTitle, 'データ管理');
      expect(AppStrings.settings.debugSectionTitle, 'デバッグ');
    });

    test('アカウントセクションのラベル・ボタンが既存の文言と一致する', () {
      expect(AppStrings.settings.accountLoggedInLabel, 'ログイン済み');
      expect(AppStrings.settings.accountLoginRequired, 'コメント取得にはログインが必要です');
      expect(AppStrings.settings.accountLoginButton, 'ニコニコにログイン');
      expect(AppStrings.settings.accountLogoutButton, 'ログアウト');
    });

    test('ログアウトダイアログ / SnackBar が既存の文言と一致する', () {
      expect(AppStrings.settings.logoutDialogTitle, 'ログアウト');
      expect(
        AppStrings.settings.logoutDialogMessage,
        'ログアウトしますか？再度ログインが必要になります。',
      );
      expect(AppStrings.settings.logoutDialogCancel, 'キャンセル');
      expect(AppStrings.settings.logoutDialogConfirm, 'ログアウト');
      expect(AppStrings.settings.logoutSnackBar, 'ログアウトしました');
    });

    test('テーマセクションの文言が既存と一致する（改行含む）', () {
      expect(AppStrings.settings.themeDropdownLabel, '配色テーマ');
      // 改行を含む説明文はバイト一致で固定する。
      expect(
        AppStrings.settings.themeDescription,
        'ダークモードは夜間の視認性を向上します。\n'
        '色覚テーマは色の区別が難しい方に配慮した配色です。',
      );
    });

    test('タイル（コメント表示 / TTS / ユーザー管理）の文言が既存と一致する', () {
      expect(AppStrings.settings.commentDisplayTileTitle, 'コメント表示設定');
      expect(AppStrings.settings.ttsTileTitle, '読み上げ設定');
      expect(AppStrings.settings.userManagementTileTitle, 'ユーザー管理');
      expect(AppStrings.settings.userManagementTileSubtitle, 'お気に入りユーザー');
    });

    test('NG設定タイル文言が AppStrings に集約されている (Issue #727)', () {
      expect(AppStrings.settings.ngFilterTileTitle, 'NG設定');
      expect(AppStrings.settings.ngFilterTileSubtitleDisabled, '未対応');
    });

    test('commentFontSizeSubtitle は引数を埋め込んだ形で既存のフォーマットと一致する', () {
      // 既存の '$int px' 形式（'px' 単位つき）を壊さないこと。
      expect(AppStrings.settings.commentFontSizeSubtitle(14), 'フォントサイズ: 14px');
      expect(AppStrings.settings.commentFontSizeSubtitle(10), 'フォントサイズ: 10px');
      expect(AppStrings.settings.commentFontSizeSubtitle(32), 'フォントサイズ: 32px');
    });

    test('ttsAutoReadSubtitle が ON/OFF 分岐ごとに既存と一致する', () {
      expect(
        AppStrings.settings.ttsAutoReadSubtitle(enabled: true),
        '自動読み上げ: ON',
      );
      expect(
        AppStrings.settings.ttsAutoReadSubtitle(enabled: false),
        '自動読み上げ: OFF',
      );
    });

    test('データ管理セクションの文言が既存と一致する', () {
      expect(AppStrings.settings.exportSettingsButton, '設定をエクスポート');
      expect(AppStrings.settings.importSettingsButton, '設定をインポート');
      expect(
        AppStrings.settings.dataManagementDescription,
        'JSON形式で設定のバックアップ・復元ができます。',
      );
      expect(AppStrings.settings.exportFailedSnackBar, '設定のエクスポートに失敗しました');
    });

    test('インポートダイアログ / SnackBar の文言が既存と一致する', () {
      expect(AppStrings.settings.importDialogTitle, '設定のインポート');
      expect(
        AppStrings.settings.importDialogMessage,
        '現在の設定がインポートしたデータで上書きされます。よろしいですか？',
      );
      expect(AppStrings.settings.importDialogCancel, 'キャンセル');
      expect(AppStrings.settings.importDialogConfirm, 'インポート');
      expect(AppStrings.settings.importSuccessSnackBar, '設定をインポートしました');
      expect(AppStrings.settings.importInvalidFileSnackBar, '無効な設定ファイルです');
      expect(AppStrings.settings.importFailedSnackBar, '設定のインポートに失敗しました');
    });

    test('ライセンス / デバッグセクションの文言が既存と一致する', () {
      expect(AppStrings.settings.licenseTileTitle, 'ライセンス');
      expect(AppStrings.settings.licenseTileSubtitle, '第三者ライブラリのライセンス情報');
      // ライセンスページのアプリ名は pubspec.yaml の `name` と一致していること。
      expect(AppStrings.settings.licenseApplicationName, 'comerune');
      expect(AppStrings.settings.debugModeSwitchTitle, 'デバッグモード');
    });
  });

  group('AppStrings.connection', () {
    test('再試行誘導文と非再試行案内文が既定ロケールで固定される', () {
      // Issue #639 cause 3: UI が isRetryable に応じて切り替える案内文。
      // バイト完全一致を維持し、既存 Snackbar のリグレッションを防ぐ。
      expect(AppStrings.connection.retryGuidance, '再接続ボタンで再試行できます。');
      expect(AppStrings.connection.nonRetryableNotice, '再接続しても解消しません。');
    });
  });

  group('AppStrings.timeshift unsupported dialog', () {
    test('未対応ダイアログの文言が既定ロケールで固定される（Issue #639 / #654 暫定）', () {
      // 暫定実装の文言が振動しないようバイト完全一致を維持する。
      // viewUri 取得経路（Issue #654）が確立して `kTimeshiftFetchEnabled` を
      // true へ戻す PR では、本テストごと削除して問題ない。
      expect(AppStrings.timeshift.unsupportedDialogTitle, 'タイムシフトは現在未対応です');
      expect(
        AppStrings.timeshift.unsupportedDialogBody,
        'タイムシフト（過去放送）のコメント取得は現在対応していません。\n'
        '今後のアップデートで対応予定です。',
      );
      expect(AppStrings.timeshift.unsupportedDialogConfirm, 'OK');
    });
  });

  group('AppStrings.commentDisplaySettings', () {
    test('pastCommentFetchCountDescription は取得数と表示保持数の区別を説明し、'
        'buffer サイズは引数で注入される（Issue #668）', () {
      // domain 層の定数を渡した場合の既定ロケール表示をバイト完全一致で固定する。
      expect(
        AppStrings.commentDisplaySettings.pastCommentFetchCountDescription(
          liveCommentBufferSize: timelineLiveCommentBufferSize,
        ),
        '初回接続時にまとめて取得する過去コメント数の上限です。\n'
        '取得後の新着コメントも追加で表示されます'
        '（表示保持数 = 取得数 + 約 5000 件）。',
      );
    });

    test('pastCommentFetchCountDescription は buffer サイズ変更に追従する'
        '（ハードコードしない回帰防止）', () {
      // 将来 `timelineLiveCommentBufferSize` を変更した際に、
      // description だけ古い値のまま取り残されるドリフトを防ぐための回帰テスト。
      final String desc = AppStrings.commentDisplaySettings
          .pastCommentFetchCountDescription(liveCommentBufferSize: 3000);
      expect(desc, contains('約 3000 件'));
      expect(desc, isNot(contains('約 5000 件')));
    });
  });

  group('AppStrings.userDetailSheet (Issue #778 Phase 2 byte-for-byte 維持)', () {
    // Phase 2 では `UserDetailSheet` の固定 UI 文言（タイトル / NG ボタン /
    // 空状態 / コメント履歴件数 / コメント色セクション / カスタムカラー /
    // コテハンセクション）を AppStrings に集約する。表示はバイト完全一致で
    // 変えないため、各 getter / メソッドが既存ハードコード文言と同一である
    // ことを固定する。
    test('ヘッダー（タイトル / ID / コテハン / 名前）が既存と一致する', () {
      expect(AppStrings.userDetailSheet.title, 'ユーザー詳細');
      expect(AppStrings.userDetailSheet.userIdLine('user-1'), 'ID: user-1');
      expect(
        AppStrings.userDetailSheet.userNicknameLine('テスト太郎'),
        'コテハン: テスト太郎',
      );
      expect(AppStrings.userDetailSheet.userNameLine('表示名'), '名前: 表示名');
    });

    test('NG ユーザートグルのボタン文言が既存と一致する', () {
      expect(AppStrings.userDetailSheet.ngButtonRegister, 'NG登録');
      expect(AppStrings.userDetailSheet.ngButtonUnregister, 'NG解除');
    });

    test('コメント履歴の空状態と件数見出しが既存と一致する', () {
      expect(
        AppStrings.userDetailSheet.noCommentsInBroadcast,
        'この放送でのコメントはありません',
      );
      expect(AppStrings.userDetailSheet.commentHistoryCount(0), 'コメント履歴（0件）');
      expect(
        AppStrings.userDetailSheet.commentHistoryCount(123),
        'コメント履歴（123件）',
      );
    });

    test('コメント色セクション（リセット含む）の文言が既存と一致する', () {
      expect(AppStrings.userDetailSheet.commentColorSectionTitle, 'コメント色');
      expect(AppStrings.userDetailSheet.commentColorReset, 'リセット');
      expect(
        AppStrings.userDetailSheet.commentColorResetSemanticsLabel,
        'コメント色をリセット',
      );
    });

    test('カスタムカラー（PR #775 由来）の文言が既存と一致する', () {
      expect(
        AppStrings.userDetailSheet.customColorSelectedSemanticsLabel,
        'カスタムカラー 選択中',
      );
      expect(
        AppStrings.userDetailSheet.customColorSelectSemanticsLabel,
        'カスタムカラーを選択',
      );
      expect(AppStrings.userDetailSheet.customColorDialogTitle, 'カスタムカラー');
      expect(AppStrings.userDetailSheet.customColorDialogCancel, 'キャンセル');
      expect(AppStrings.userDetailSheet.customColorDialogApply, '適用');
    });

    test('コテハン（ニックネーム）セクションの文言が既存と一致する', () {
      expect(AppStrings.userDetailSheet.nicknameSectionTitle, 'コテハン');
      expect(AppStrings.userDetailSheet.nicknameUnregistered, '未登録');
      expect(AppStrings.userDetailSheet.nicknameEditSemanticsLabel, 'コテハンを変更');
      expect(AppStrings.userDetailSheet.nicknameAddSemanticsLabel, 'コテハンを登録');
      expect(AppStrings.userDetailSheet.nicknameEditButton, '変更');
      expect(AppStrings.userDetailSheet.nicknameAddButton, '登録');
      expect(
        AppStrings.userDetailSheet.nicknameRemoveSemanticsLabel,
        'コテハンを削除',
      );
      expect(AppStrings.userDetailSheet.nicknameRemoveButton, '削除');
      expect(AppStrings.userDetailSheet.nicknameDialogTitle, 'コテハン登録');
      expect(AppStrings.userDetailSheet.nicknameDialogFieldLabel, 'コテハン');
      expect(AppStrings.userDetailSheet.nicknameDialogFieldHint, 'ニックネームを入力');
      expect(AppStrings.userDetailSheet.nicknameDialogCancel, 'キャンセル');
      expect(AppStrings.userDetailSheet.nicknameDialogSave, '保存');
    });
  });

  group('AppStrings.commentScreen (Issue #778 Phase 2 byte-for-byte 維持)', () {
    test('ソート切替トグルの tooltip が既存と一致する（PR #776 由来）', () {
      // 「現在の並び順 → 切替先」を案内する tooltip。
      // 昇順表示中は「新しい順に切替」、降順表示中は「古い順に切替」を出す。
      expect(AppStrings.commentScreen.sortToggleToDescending, '新しい順に切替');
      expect(AppStrings.commentScreen.sortToggleToAscending, '古い順に切替');
    });
  });

  group('AppStrings.broadcasterNgEdit (NG 設定編集画面の byte-for-byte 維持)', () {
    test('NG設定編集画面のタブラベルが既存と一致する', () {
      expect(AppStrings.broadcasterNgEdit.usersTabLabel, 'NGユーザー');
      expect(AppStrings.broadcasterNgEdit.wordsTabLabel, 'NGワード');
    });

    test('テンプレート編集時のバナー文言が既存と一致する', () {
      // 動的引数なしの固定文。バナーが見える位置・色は別 widget テストの
      // 担当で、ここでは文字列バイト一致のみ担保する。
      expect(
        AppStrings.broadcasterNgEdit.templateBanner,
        'テンプレート: 新規放送者の初期値として使われます',
      );
    });
  });

  group('AppStrings.ngUserList (NG ユーザー一覧画面の byte-for-byte 維持)', () {
    test('NG解除ダイアログの文言が既存と一致する', () {
      expect(AppStrings.ngUserList.unregisterDialogTitle, 'NG解除');
      expect(
        AppStrings.ngUserList.unregisterDialogContent('user-1'),
        'ユーザーID「user-1」のNG登録を解除しますか？',
      );
      expect(AppStrings.ngUserList.unregisterDialogConfirm, '解除');
    });

    test('NG解除完了 SnackBar が既存と一致する（引数を含む）', () {
      // 引数を `{userId} のNGを解除しました` の形で接続するため、
      // 末尾の半角スペース 1 つを含むかを byte-for-byte で固定する。
      expect(
        AppStrings.ngUserList.unregisteredSnackBar('user-1'),
        'user-1 のNGを解除しました',
      );
    });

    test('動的引数を含む文言の境界値が byte-for-byte で固定される', () {
      // ARB 化で `{userId}` プレースホルダに置き換えた際にも
      // 同じ前後余白・記号の埋め込みになるよう、空文字 / 半角スペース /
      // 鉤括弧ネスト / 制御記号を含む文字列で固定する。
      // unregisterDialogContent: 鉤括弧で値を挟む形
      expect(
        AppStrings.ngUserList.unregisterDialogContent(''),
        'ユーザーID「」のNG登録を解除しますか？',
      );
      expect(
        AppStrings.ngUserList.unregisterDialogContent('「abc」'),
        'ユーザーID「「abc」」のNG登録を解除しますか？',
      );
      // unregisteredSnackBar: 引数の直後に半角スペース 1 個を入れる形
      expect(AppStrings.ngUserList.unregisteredSnackBar(''), ' のNGを解除しました');
      expect(AppStrings.ngUserList.unregisteredSnackBar(' '), '  のNGを解除しました');
    });

    test('読み込み失敗 / 空状態 / tooltip の文言が既存と一致する', () {
      expect(AppStrings.ngUserList.loadFailedMessage, 'NG リストの読込みに失敗しました');
      expect(AppStrings.ngUserList.retryButton, '再試行');
      expect(AppStrings.ngUserList.emptyMessage, 'NGユーザーIDは登録されていません');
      expect(AppStrings.ngUserList.removeTooltip, 'NG解除');
    });
  });

  group('AppStrings.ngWordList (NG ワード一覧画面の byte-for-byte 維持)', () {
    test('NGワード削除ダイアログの文言が既存と一致する', () {
      expect(AppStrings.ngWordList.deleteDialogTitle, 'NGワード削除');
      expect(AppStrings.ngWordList.deleteDialogContent('スパム'), '「スパム」を削除しますか？');
      expect(AppStrings.ngWordList.deleteDialogCancel, 'キャンセル');
      expect(AppStrings.ngWordList.deleteDialogConfirm, '削除');
    });

    test('削除完了 SnackBar の文言が既存と一致する（引数を含む）', () {
      expect(AppStrings.ngWordList.deletedSnackBar('スパム'), '「スパム」を削除しました');
    });

    test('動的引数を含む文言の境界値が byte-for-byte で固定される', () {
      // ARB 化で `{pattern}` プレースホルダに置き換えた際にも
      // 同じ鉤括弧で挟む形に保つこと。空文字 / regex メタ文字 /
      // 鉤括弧ネスト / `$` を含むパターンで固定する。
      // deleteDialogContent: 鉤括弧で値を挟む形
      expect(AppStrings.ngWordList.deleteDialogContent(''), '「」を削除しますか？');
      expect(
        AppStrings.ngWordList.deleteDialogContent(r'$abc'),
        r'「$abc」を削除しますか？',
      );
      expect(
        AppStrings.ngWordList.deleteDialogContent('「nested」'),
        '「「nested」」を削除しますか？',
      );
      // deletedSnackBar
      expect(AppStrings.ngWordList.deletedSnackBar(''), '「」を削除しました');
      expect(AppStrings.ngWordList.deletedSnackBar(r'.*'), '「.*」を削除しました');
    });

    test('追加 UI（ボタン / ダイアログ）の文言が既存と一致する', () {
      expect(AppStrings.ngWordList.addButton, 'NGワード追加');
      expect(AppStrings.ngWordList.addDialogTitle, 'NGワード追加');
      expect(AppStrings.ngWordList.addDialogFieldLabel, 'パターン（部分一致）');
      expect(AppStrings.ngWordList.addDialogFieldHint, '例: スパム');
      expect(AppStrings.ngWordList.addDialogConfirm, '追加');
    });

    test('入力バリデーション SnackBar の文言が既存と一致する', () {
      expect(AppStrings.ngWordList.invalidPatternSnackBar, '無効なパターンです');
      expect(
        AppStrings.ngWordList.duplicatePatternSnackBar,
        '同じパターンが既に登録されています',
      );
    });

    test('読み込み失敗 / 空状態 / tooltip の文言が既存と一致する', () {
      expect(AppStrings.ngWordList.loadFailedMessage, 'NG リストの読込みに失敗しました');
      expect(AppStrings.ngWordList.retryButton, '再試行');
      expect(AppStrings.ngWordList.emptyMessage, 'NGワードは登録されていません');
      expect(AppStrings.ngWordList.deleteTooltip, '削除');
    });
  });
}
