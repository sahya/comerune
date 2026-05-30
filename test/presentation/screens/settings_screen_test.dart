import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/application/app_update/update_prompt_store.dart';
import 'package:comerune/application/app_update/version_update_checker.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/app_update/github_release_repository.dart';
import 'package:comerune/data/auth/user_session_store.dart';
import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/broadcaster_ng_list_screen.dart';
import 'package:comerune/presentation/screens/settings_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';
import '../../helpers/fake_file_picker_platform.dart';
import '../../helpers/fake_share_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/in_memory_user_session_store.dart';
import '../../helpers/settings_test_helpers.dart';
import '../../helpers/throwing_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ライセンスページが参照する PackageInfo にテスト用のモック値を注入する。
    PackageInfo.setMockInitialValues(
      appName: 'comerune',
      packageName: 'app.comerune',
      version: '1.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('SettingsScreen', () {
    testWidgets('shows login button when not logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-button')), findsOneWidget);
      expect(find.byKey(const Key('logout-button')), findsNothing);
      expect(find.text('コメント取得にはログインが必要です'), findsOneWidget);
    });

    testWidgets('shows logout button when logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('user_session_abc123');

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logout-button')), findsOneWidget);
      expect(find.byKey(const Key('login-button')), findsNothing);
      expect(find.text('ログイン済み'), findsOneWidget);
    });

    testWidgets('theme dropdown persists selected value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be light
      AppSettings loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.light);

      // Open the dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Tap the dark option in the dropdown overlay
      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.dark);
    });

    testWidgets('theme dropdown updates themeModeNotifier immediately', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<AppThemeMode> themeNotifier =
          ValueNotifier<AppThemeMode>(AppThemeMode.light);

      await tester.pumpWidget(
        _buildScreen(settingsStore, themeModeNotifier: themeNotifier),
      );
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.light);

      // Open dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.dark);

      themeNotifier.dispose();
    });

    testWidgets('debug mode toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('debug-mode-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      toggleSwitchByKeySync(tester, const Key('debug-mode-switch'));
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.debugMode, isTrue);
    });

    testWidgets('shows navigation tiles for sub-screens', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      // Scroll to each tile individually to verify it exists.
      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('comment-display-settings-tile')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('tts-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tts-settings-tile')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('user-management-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('user-management-settings-tile')),
        findsOneWidget,
      );
    });

    testWidgets('tts tile shows auto-read status', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tts-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default autoRead is OFF
      expect(find.text('自動読み上げ: OFF'), findsOneWidget);
    });

    testWidgets('settings sections are displayed in correct order', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      // Account section should appear before theme (both visible initially).
      final double accountY = tester.getTopLeft(find.text('ニコニコアカウント')).dy;
      final double themeY = tester.getTopLeft(find.text('配色テーマ')).dy;
      expect(
        accountY,
        lessThan(themeY),
        reason: 'ニコニコアカウント should appear before テーマ',
      );

      // Scroll to comment-display tile; adjacent TTS tile should also be
      // visible since they are directly next to each other.
      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Comment display should appear before TTS.
      final double commentDisplayY = tester
          .getTopLeft(find.byKey(const Key('comment-display-settings-tile')))
          .dy;
      final double ttsY = tester
          .getTopLeft(find.byKey(const Key('tts-settings-tile')))
          .dy;
      expect(
        commentDisplayY,
        lessThan(ttsY),
        reason: 'コメント表示設定 should appear before 読み上げ設定',
      );

      // Scroll to user-management tile; adjacent export button should also be
      // visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('user-management-settings-tile')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // User management should appear before data management.
      final double userMgmtY = tester
          .getTopLeft(find.byKey(const Key('user-management-settings-tile')))
          .dy;
      final double exportY = tester
          .getTopLeft(find.byKey(const Key('export-settings-button')))
          .dy;
      expect(
        userMgmtY,
        lessThan(exportY),
        reason: 'ユーザー管理 should appear before データ管理',
      );

      // Scroll to debug switch; adjacent export button should still be visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('debug-mode-switch')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Data management should appear before debug.
      final double exportY2 = tester
          .getTopLeft(find.byKey(const Key('export-settings-button')))
          .dy;
      final double debugY = tester
          .getTopLeft(find.byKey(const Key('debug-mode-switch')))
          .dy;
      expect(
        exportY2,
        lessThan(debugY),
        reason: 'データ管理 should appear before デバッグ',
      );
    });

    testWidgets('comment display tile shows font size', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default font size is 14px
      expect(find.text('フォントサイズ: 14px'), findsOneWidget);
    });

    testWidgets('license tile renders and is tappable', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.byKey(const Key('license-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Verify the license tile renders with correct text
      expect(find.byKey(const Key('license-tile')), findsOneWidget);
      expect(find.text('ライセンス'), findsOneWidget);

      // Verify the tile is tappable (opens license page)
      await tester.tap(find.byKey(const Key('license-tile')));
      await tester.pumpAndSettle();

      // showLicensePage pushes a new route with the LicensePage widget
      expect(find.text('comerune'), findsOneWidget);
    });

    testWidgets(
      'license page shows applicationVersion from PackageInfo (not hardcoded)',
      (WidgetTester tester) async {
        // 既定の setUp モック値（1.2.0）を上書きし、ハードコードでないことを保証する。
        PackageInfo.setMockInitialValues(
          appName: 'comerune',
          packageName: 'app.comerune',
          version: '9.9.9-test',
          buildNumber: '42',
          buildSignature: '',
        );

        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        final Finder scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('license-tile')),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('license-tile')));
        await tester.pumpAndSettle();

        // LicensePage は applicationVersion を本文に表示する。
        // PackageInfo のモック値が反映されていることを確認し、
        // 以前の '1.2.0' ハードコードへの逆戻りを検出する。
        expect(find.text('9.9.9-test'), findsOneWidget);
        expect(find.text('1.2.0'), findsNothing);
      },
    );

    testWidgets('license page lists packages registered via LicenseRegistry '
        '(pubspec.yaml auto-sync contract)', (WidgetTester tester) async {
      // `showLicensePage` は Flutter 標準の [LicenseRegistry] を参照して
      // パッケージ一覧を描画する。本テストは:
      //   1. ダミーパッケージを [LicenseRegistry.addLicense] で登録し、
      //      ライセンスページに表示されることを確認する。
      //   2. これにより、実機では `pubspec.yaml` の依存が Flutter ツール
      //      チェーンによって同様に [LicenseRegistry] へ自動登録され、
      //      ライセンスページに自動反映されることの回帰テストとする。
      // アプリ側で [LicenseRegistry.addLicense] を呼び出していなくても
      // 自動表示が成立することを担保する契約テストに相当する。
      const String sentinelPackage = '__license_registry_autosync_sentinel__';
      const String sentinelBody = 'SENTINEL_LICENSE_BODY_42';
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(<String>[
          sentinelPackage,
        ], sentinelBody);
      });
      // 登録は LicenseRegistry.reset の公開 API が無いため累積する。
      // テスト内で固有なセンチネル文字列を使い、他テストと衝突しないよう
      // 識別子を十分にユニークにしてある。

      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('license-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('license-tile')));
      await tester.pumpAndSettle();

      // LicensePage のパッケージ一覧に、LicenseRegistry 経由で登録した
      // センチネルパッケージ名が表示されることを確認する。
      expect(find.text(sentinelPackage), findsOneWidget);
    });

    test('app code does not call LicenseRegistry.addLicense '
        '(no hardcoded package/license text policy)', () async {
      // アプリ本体でパッケージ名・ライセンス本文のハードコードを禁止する
      // ポリシーを、lib/ 配下に `LicenseRegistry.addLicense` / `LicenseEntry`
      // のリテラルが現れないことで担保する。
      // Flutter ツールチェーンが pubspec.yaml 依存を自動登録するため、
      // アプリ側からの手動登録は不要であり、手動登録が復活した場合は
      // 同期漏れリスクが再発する。
      final Directory libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'lib/ ディレクトリがテスト実行パスから見つかりません',
      );
      final List<File> dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      final List<String> offenders = <String>[];
      for (final File file in dartFiles) {
        final String src = file.readAsStringSync();
        // コメントは許容（ポリシー説明で語を使うため）。実呼び出しのみを検出する。
        if (src.contains('LicenseRegistry.addLicense(') ||
            src.contains('LicenseEntryWithLineBreaks(') ||
            RegExp(r'\bLicenseEntry\s*\(').hasMatch(src)) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'lib/ 配下で LicenseRegistry への手動登録やハードコードが検出されました。'
            'pubspec.yaml と表示の乖離を防ぐため、ライセンス情報は '
            'pubspec.yaml の依存に一本化してください: $offenders',
      );
    });

    // Issue #727 PR2 (UX flatten): per-broadcaster NG management is now a
    // top-level Settings tile. The screen pushes [BroadcasterNgListScreen]
    // when the store is wired, and renders disabled with 「未対応」 when
    // not.
    testWidgets(
      'NG設定 tile is disabled with 「未対応」 when broadcasterNgStore is null',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        final Finder scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('broadcaster-ng-filter-tile')),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        expect(find.text('NG設定'), findsOneWidget);
        expect(find.text('未対応'), findsOneWidget);

        final ListTile tile = tester.widget(
          find.byKey(const Key('broadcaster-ng-filter-tile')),
        );
        expect(tile.enabled, isFalse);
        expect(tile.onTap, isNull);
      },
    );

    testWidgets('NG設定 tile pushes BroadcasterNgListScreen when store wired', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeBroadcasterNgStore ngStore = FakeBroadcasterNgStore();

      await tester.pumpWidget(
        _buildScreen(settingsStore, broadcasterNgStore: ngStore),
      );
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('broadcaster-ng-filter-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // No subtitle is rendered when the tile is enabled (sage review:
      // tile name 「NG設定」 is self-explanatory; subtitle removed
      // for tile compactness and above-the-fold space).
      expect(find.text('未対応'), findsNothing);
      expect(find.text('NG設定'), findsOneWidget);

      await tester.tap(find.byKey(const Key('broadcaster-ng-filter-tile')));
      await tester.pumpAndSettle();

      expect(find.byType(BroadcasterNgListScreen), findsOneWidget);
    });

    testWidgets(
      'shows error UI (not perma-spinner) when settingsStore.load() throws '
      'a StateError from legacy persisted data',
      (WidgetTester tester) async {
        // 「更新インストール後に NG 設定項目が一覧に出ない」報告の根本原因
        // 再現テスト。`SettingsStore.load()` が `Error` 系を投げると、
        // SettingsScreenMixin が `Exception` 限定で catch していた頃は
        // `settings`/`settingsError` ともに null のままで CircularProgress
        // Indicator が消えず、ユーザーには「設定一覧が出てない」ように
        // 見えていた。修正後はエラー UI と再試行ボタンが表示されること。
        final ThrowingSettingsStore store = ThrowingSettingsStore(
          errorToThrow: StateError('simulated legacy parse failure'),
        );

        await tester.pumpWidget(_buildScreen(store));
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('設定の読み込みに失敗しました'), findsOneWidget);
        expect(find.text('再試行'), findsOneWidget);
      },
    );
  });

  group('SettingsScreen export/import', () {
    // `SharePlus.instance._platform` は `SharePlus.instance` の最初のアクセス時に
    // `SharePlatform.instance` をキャプチャする (static final)。したがって、
    // 本グループの最初のテストより前にフェイクをインストールしておく必要がある。
    //
    // tests 内部から `SharePlus.instance.share(...)` を呼び出す前に必ず
    // 1 度だけキャプチャされるため、`setUpAll` にて設定すれば十分。
    late FakeSharePlatform fakeShare;
    late FakeFilePickerPlatform fakeFilePicker;
    late Directory tempDir;

    setUpAll(() {
      fakeShare = FakeSharePlatform();
      SharePlatform.instance = fakeShare;
      fakeFilePicker = FakeFilePickerPlatform();
      FilePickerPlatform.instance = fakeFilePicker;
      // Force `SharePlus.instance` static-final to initialize now with our
      // fake platform so later tests cannot accidentally capture the real one.
      // ignore: unnecessary_statements
      SharePlus.instance;
    });

    setUp(() {
      fakeShare.reset();
      fakeFilePicker.reset();
      tempDir = Directory.systemTemp.createTempSync(
        'settings_screen_export_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    SettingsStore buildStore() {
      return SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
        tempDirectory: tempDir,
      );
    }

    testWidgets('export: double-tap guard calls SharePlus.share exactly once', (
      WidgetTester tester,
    ) async {
      // `File.writeAsString` はウィジェットテストの FakeAsync 内では
      // 進まないため、data 層は通さずスタブ SettingsStore で置き換える。
      final _StubSettingsStore store = _StubSettingsStore(
        exportPath: '${tempDir.path}/comerune-settings.json',
        exportDelay: const Duration(milliseconds: 150),
      );
      fakeShare.responseDelay = const Duration(milliseconds: 200);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Finder exportBtn = find.byKey(const Key('export-settings-button'));
      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('export-settings-button'),
      );

      await tester.tap(exportBtn);
      await tester.pump(); // _isExporting = true, re-render with spinner
      // 2 回目のタップ (ボタンは disabled のため onPressed: null で無視)
      await tester.tap(exportBtn, warnIfMissed: false);

      // store.writeExportToTempFile の delay + share.responseDelay を越える。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(fakeShare.calls, hasLength(1));
    });

    testWidgets(
      'export: button is disabled and shows spinner while in-flight',
      (WidgetTester tester) async {
        final _StubSettingsStore store = _StubSettingsStore(
          exportPath: '${tempDir.path}/comerune-settings.json',
          exportDelay: const Duration(milliseconds: 100),
        );
        fakeShare.responseDelay = const Duration(milliseconds: 200);

        await tester.pumpWidget(_buildScreen(store));
        await tester.pumpAndSettle();

        final Finder exportBtn = find.byKey(
          const Key('export-settings-button'),
        );
        await scrollToKeyInList(
          tester,
          const Key('settings-list'),
          const Key('export-settings-button'),
        );

        await tester.tap(exportBtn);
        await tester.pump(); // in-flight 状態を一度だけ描画する

        final OutlinedButton btnWidget = tester.widget<OutlinedButton>(
          exportBtn,
        );
        expect(btnWidget.onPressed, isNull, reason: 'disabled while in-flight');
        expect(
          find.descendant(
            of: exportBtn,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );

        // Let share complete and clean up; avoid leaking pending timers.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      },
    );

    testWidgets('export: button re-enables after completion', (
      WidgetTester tester,
    ) async {
      final _StubSettingsStore store = _StubSettingsStore(
        exportPath: '${tempDir.path}/comerune-settings.json',
      );
      // 0 レスポンス遅延で即完了させ、finally で `_isExporting = false` に戻る
      // ことを検証する。
      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Finder exportBtn = find.byKey(const Key('export-settings-button'));
      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('export-settings-button'),
      );

      await tester.tap(exportBtn);
      await tester.pump();
      await tester.pump();

      final OutlinedButton btnWidget = tester.widget<OutlinedButton>(exportBtn);
      expect(btnWidget.onPressed, isNotNull, reason: 're-enabled');
      expect(
        find.descendant(
          of: exportBtn,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'export: share params carry the timestamped file name as both subject and XFile.name',
      (WidgetTester tester) async {
        // Google Drive は `ShareParams.subject` を保存時の既定ファイル名に
        // 採用し、FileProvider の DISPLAY_NAME より優先する。
        // タイムスタンプ付きのディスク実体に対して subject / XFile.name が
        // 旧来の canonical 名のままだと、Drive 上で上書き保存になる。
        //
        // タイムスタンプ生成ルールの変更に追従させるため、data 層の
        // `SettingsExport.timestampedFileName` を使って期待値を作る。
        final String timestampedName = SettingsExport.timestampedFileName(
          DateTime(2026, 4, 19, 1, 2, 3),
        );
        final _StubSettingsStore store = _StubSettingsStore(
          exportPath:
              '${tempDir.path}${Platform.pathSeparator}$timestampedName',
        );

        await tester.pumpWidget(_buildScreen(store));
        await tester.pumpAndSettle();

        final Finder exportBtn = find.byKey(
          const Key('export-settings-button'),
        );
        await scrollToKeyInList(
          tester,
          const Key('settings-list'),
          const Key('export-settings-button'),
        );

        await tester.tap(exportBtn);
        await tester.pump();
        await tester.pump();

        expect(fakeShare.calls, hasLength(1));
        final ShareParams params = fakeShare.calls.single;
        expect(
          params.subject,
          timestampedName,
          reason: 'subject は Drive の保存ファイル名として使われるため basename と一致させる',
        );
        expect(params.files, isNotNull);
        expect(params.files!, hasLength(1));
        final XFile shared = params.files!.single;
        expect(
          shared.name,
          timestampedName,
          reason:
              'XFile.name は FileProvider 経由の DISPLAY_NAME に使われる。 '
              'subject と揃えることで受信側の挙動を安定させる',
        );
        expect(shared.mimeType, SettingsExport.mimeType);
        expect(
          SettingsExport.timestampedFileNamePattern.hasMatch(shared.name),
          isTrue,
          reason: 'shared file name must match the timestamped pattern',
        );
      },
    );

    testWidgets(
      'export: surfaces exportFailed SnackBar when writeExport throws',
      (WidgetTester tester) async {
        final SettingsStore store = _FailingExportSettingsStore();

        await tester.pumpWidget(_buildScreen(store));
        await tester.pumpAndSettle();

        final Finder exportBtn = find.byKey(
          const Key('export-settings-button'),
        );
        await scrollToKeyInList(
          tester,
          const Key('settings-list'),
          const Key('export-settings-button'),
        );

        await tester.tap(exportBtn);
        await tester.pump();
        await tester.pump();
        // SnackBar の in アニメーション分だけ進める。
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('設定のエクスポートに失敗しました'), findsOneWidget);
        expect(fakeShare.calls, isEmpty);
      },
    );

    testWidgets('import: user cancel (null result) leaves settings untouched', (
      WidgetTester tester,
    ) async {
      final SettingsStore store = _StubSettingsStore();
      fakeFilePicker.resultToReturn = null; // user cancel

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Finder importBtn = find.byKey(const Key('import-settings-button'));
      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('import-settings-button'),
      );

      await tester.tap(importBtn);
      await tester.pump();
      await tester.pump();

      expect(find.text('設定をインポートしました'), findsNothing);
      expect(find.text('無効な設定ファイルです'), findsNothing);
      expect(fakeFilePicker.pickCalls, hasLength(1));

      final OutlinedButton btnWidget = tester.widget<OutlinedButton>(importBtn);
      expect(btnWidget.onPressed, isNotNull, reason: 're-enabled after cancel');
    });

    testWidgets('import: invalid JSON shows importInvalidFile SnackBar', (
      WidgetTester tester,
    ) async {
      final SettingsStore store = buildStore();
      final File bad = File('${tempDir.path}/bad.json')
        ..writeAsStringSync('not valid json');
      fakeFilePicker.resultToReturn = buildSingleFileResult(path: bad.path);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Finder importBtn = find.byKey(const Key('import-settings-button'));
      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('import-settings-button'),
      );

      await tester.tap(importBtn);
      // FilePicker 完了 + File.readAsString (実 I/O) + showDialog まで進める。
      // spinner のアニメーションが永続するため pumpAndSettle は使えない。
      // I/O 完了待ちに runAsync を噛ませ、その後 dialog アニメーションを
      // 進めるために有限 pump を繰り返す。
      for (int i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 200));
      }

      // ダイアログが表示されていることを確認してから「インポート」ボタンを探す
      expect(find.byType(AlertDialog), findsOneWidget);
      final Finder confirmBtn = find.widgetWithText(TextButton, 'インポート');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      for (int i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('無効な設定ファイルです'), findsOneWidget);
    });

    testWidgets('import: double-tap guard calls FilePicker exactly once', (
      WidgetTester tester,
    ) async {
      final SettingsStore store = buildStore();
      fakeFilePicker.responseDelay = const Duration(milliseconds: 200);
      fakeFilePicker.resultToReturn = null; // user cancel on completion

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Finder importBtn = find.byKey(const Key('import-settings-button'));
      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('import-settings-button'),
      );

      await tester.tap(importBtn);
      await tester.pump(); // in-flight
      await tester.tap(importBtn, warnIfMissed: false);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(fakeFilePicker.pickCalls, hasLength(1));
    });

    testWidgets('import: picker is invoked with both json and txt extensions '
        '(so text/plain-stored JSON on Drive remains selectable)', (
      WidgetTester tester,
    ) async {
      // Google Drive 等が共有経由で受け取った `.json` を `text/plain` として
      // 保存するケースが観測されている。SAF は MIME でフィルタするため、
      // `['json']` 単独では text/plain な JSON が選べない。`['json', 'txt']`
      // を渡すことで `application/json` + `text/plain` の両方を許容する。
      final SettingsStore store = _StubSettingsStore();
      fakeFilePicker.resultToReturn = null; // user cancel

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        const Key('settings-list'),
        const Key('import-settings-button'),
      );
      await tester.tap(find.byKey(const Key('import-settings-button')));
      await tester.pump();
      await tester.pump();

      expect(fakeFilePicker.pickCalls, hasLength(1));
      expect(fakeFilePicker.pickCalls[0]['type'], FileType.custom);
      expect(fakeFilePicker.pickCalls[0]['allowedExtensions'], <String>[
        'json',
        'txt',
      ]);
    });
  });

  group('SettingsScreen app update tile', () {
    SharedPreferencesSettingsStore newStore() =>
        SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

    testWidgets('shows current version from PackageInfo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildScreen(newStore()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-update-tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('現在のバージョン: 1.2.0'), findsOneWidget);
    });

    testWidgets('is not actionable when no checker is wired', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildScreen(newStore()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-update-tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final ListTile tile = tester.widget<ListTile>(
        find.byKey(const Key('app-update-tile')),
      );
      expect(tile.onTap, isNull);
    });

    testWidgets('manual check reports up to date', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildScreen(
          newStore(),
          versionUpdateChecker: _checkerReturning(tag: 'v1.2.0'),
          updatePromptStore: UpdatePromptStore(
            prefs: InMemorySharedPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-update-tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('app-update-tile')));
      await tester.pumpAndSettle();
      expect(find.text('お使いのバージョンは最新です'), findsOneWidget);
    });

    testWidgets('manual check surfaces an optional update dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          newStore(),
          versionUpdateChecker: _checkerReturning(tag: 'v9.9.9'),
          updatePromptStore: UpdatePromptStore(
            prefs: InMemorySharedPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-update-tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('app-update-tile')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('app-update-now')), findsOneWidget);
    });

    testWidgets('manual check reports unavailable on fetch failure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          newStore(),
          versionUpdateChecker: _checkerFailing(),
          updatePromptStore: UpdatePromptStore(
            prefs: InMemorySharedPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-update-tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('app-update-tile')));
      await tester.pumpAndSettle();
      expect(find.text('更新を確認できませんでした'), findsOneWidget);
    });
  });
}

/// In-memory stub SettingsStore that avoids real filesystem I/O.
///
/// [writeExportToTempFile] returns [exportPath] (or a default) after
/// [exportDelay]; the path is not actually written to disk unless the
/// test does so explicitly (for `invalid JSON` etc.).  `importFromJson`
/// delegates to the real SharedPreferencesSettingsStore so that the
/// screen receives a realistic AppSettings instance.
class _StubSettingsStore implements SettingsStore {
  _StubSettingsStore({String? exportPath, this.exportDelay = Duration.zero})
    : exportPath = exportPath ?? '/tmp/stub-settings.json';

  final SharedPreferencesSettingsStore _delegate =
      SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

  final String exportPath;
  final Duration exportDelay;

  @override
  Future<AppSettings> load() => _delegate.load();

  @override
  Future<void> save(AppSettings settings) => _delegate.save(settings);

  @override
  double? loadPreMuteVolume() => _delegate.loadPreMuteVolume();

  @override
  Future<void> savePreMuteVolume(double? volume) =>
      _delegate.savePreMuteVolume(volume);

  @override
  double? loadPreMuteAndroidTtsVolume() =>
      _delegate.loadPreMuteAndroidTtsVolume();

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) =>
      _delegate.savePreMuteAndroidTtsVolume(volume);

  @override
  Future<String> exportAsJson() => _delegate.exportAsJson();

  @override
  Future<String> writeExportToTempFile() async {
    if (exportDelay > Duration.zero) {
      await Future<void>.delayed(exportDelay);
    }
    return exportPath;
  }

  @override
  Future<AppSettings> importFromJson(String jsonString) =>
      _delegate.importFromJson(jsonString);
}

/// SettingsStore whose `writeExportToTempFile` always throws.  Used to verify
/// that the screen displays the failure SnackBar.
class _FailingExportSettingsStore implements SettingsStore {
  final SharedPreferencesSettingsStore _delegate =
      SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

  @override
  Future<AppSettings> load() => _delegate.load();

  @override
  Future<void> save(AppSettings settings) => _delegate.save(settings);

  @override
  double? loadPreMuteVolume() => _delegate.loadPreMuteVolume();

  @override
  Future<void> savePreMuteVolume(double? volume) =>
      _delegate.savePreMuteVolume(volume);

  @override
  double? loadPreMuteAndroidTtsVolume() =>
      _delegate.loadPreMuteAndroidTtsVolume();

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) =>
      _delegate.savePreMuteAndroidTtsVolume(volume);

  @override
  Future<String> exportAsJson() => _delegate.exportAsJson();

  @override
  Future<String> writeExportToTempFile() async {
    throw Exception('simulated export failure');
  }

  @override
  Future<AppSettings> importFromJson(String jsonString) =>
      _delegate.importFromJson(jsonString);
}

Widget _buildScreen(
  SettingsStore settingsStore, {
  UserSessionStore? userSessionStore,
  ValueNotifier<AppThemeMode>? themeModeNotifier,
  BroadcasterNgStore? broadcasterNgStore,
  ValueNotifier<String?>? broadcasterIdNotifier,
  VersionUpdateChecker? versionUpdateChecker,
  UpdatePromptStore? updatePromptStore,
}) {
  return MaterialApp(
    home: SettingsScreen(
      settingsStore: settingsStore,
      userSessionStore: userSessionStore,
      themeModeNotifier: themeModeNotifier,
      broadcasterNgStore: broadcasterNgStore,
      broadcasterIdNotifier: broadcasterIdNotifier,
      versionUpdateChecker: versionUpdateChecker,
      updatePromptStore: updatePromptStore,
    ),
  );
}

VersionUpdateChecker _checkerReturning({required String tag, String? body}) {
  final MockClient mock = MockClient((http.Request request) async {
    return http.Response(
      jsonEncode(<String, Object?>{
        'tag_name': tag,
        if (body != null) 'body': body,
      }),
      200,
    );
  });
  return VersionUpdateChecker(
    repository: GithubReleaseRepository(httpClient: mock),
    isSupportedPlatform: true,
  );
}

VersionUpdateChecker _checkerFailing() {
  final MockClient mock = MockClient((http.Request request) async {
    return http.Response('err', 500);
  });
  return VersionUpdateChecker(
    repository: GithubReleaseRepository(httpClient: mock),
    isSupportedPlatform: true,
  );
}
