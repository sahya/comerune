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
      expect(AppStrings.settings.userManagementTileSubtitle, 'お気に入り・コテハン');
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
      expect(
        AppStrings.timeshift.unsupportedDialogTitle,
        'タイムシフトは現在未対応です',
      );
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
}
