import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_display_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

const Key _listKey = Key('comment-display-settings-list');

void main() {
  group('CommentDisplaySettingsScreen', () {
    testWidgets('toggles showUserName and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default is true
      AppSettings loaded = await settingsStore.load();
      expect(loaded.showUserName, isTrue);

      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('show-user-name-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showUserName, isFalse);
    });

    testWidgets(
      'keeps resolveUserName switch enabled when showUserName is off',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Turn off showUserName
        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('show-user-name-switch'),
        );

        // resolveUserName switch should remain enabled and be toggleable.
        final SwitchListTile resolveTile = tester.widget(
          find.byKey(
            const Key('resolve-user-name-switch'),
            skipOffstage: false,
          ),
        );
        expect(resolveTile.onChanged, isNotNull);

        AppSettings loaded = await settingsStore.load();
        expect(loaded.resolveUserName, isTrue);

        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('resolve-user-name-switch'),
        );
        loaded = await settingsStore.load();
        expect(loaded.resolveUserName, isFalse);
        expect(loaded.showUserName, isFalse);
      },
    );

    testWidgets('auto-save comment log toggle persists value when turned off', (
      WidgetTester tester,
    ) async {
      // Pre-set auto-save to ON so we can test turning it OFF
      // (turning ON requires a file picker which cannot be mocked easily).
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setBool('settings.comment.autoSaveCommentLog', true);
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Verify initial state is ON
      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isTrue);

      // Toggle OFF
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('auto-save-comment-log-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isFalse);
    });

    testWidgets('past comment count dropdown persists selected value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be count100
      AppSettings loaded = await settingsStore.load();
      expect(loaded.pastCommentFetchCount, PastCommentFetchCount.count100);

      // Scroll to and open the dropdown. `ensureVisible` is called explicitly
      // after `scrollToKeyInList` so that later additions to the list do not
      // leave the dropdown partially clipped, which would cause the subsequent
      // tap to miss the hit-box.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('past-comment-count-dropdown'),
      );
      await tester.ensureVisible(
        find.byKey(const Key('past-comment-count-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('past-comment-count-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Select '500' option in the dropdown overlay
      await tester.tap(find.text('500').last);
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.pastCommentFetchCount, PastCommentFetchCount.count500);
    });

    testWidgets('toggles commentTwoLineEnabled and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.commentTwoLineEnabled, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('comment-two-line-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('comment-two-line-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.commentTwoLineEnabled, isTrue);
    });

    testWidgets('toggles commentZebraStripingEnabled and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.commentZebraStripingEnabled, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('comment-zebra-striping-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('comment-zebra-striping-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.commentZebraStripingEnabled, isTrue);
    });

    testWidgets('toggles showOperatorComment and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showOperatorComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-operator-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showOperatorComment, isFalse);
    });

    testWidgets('toggles showSystemMessage and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showSystemMessage, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-system-message-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showSystemMessage, isFalse);
    });

    testWidgets('toggles showEmotion and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showEmotion, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-emotion-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showEmotion, isFalse);
    });

    testWidgets('toggles showGiftComment and persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showGiftComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-gift-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showGiftComment, isFalse);
    });

    testWidgets('toggles showNicoadComment and persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showNicoadComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-nicoad-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showNicoadComment, isFalse);
    });

    testWidgets(
      'message type subtitle shows enabled count and updates on toggle',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('message-type-expansion-tile'),
        );

        expect(find.text('5 / 5 表示中'), findsOneWidget);

        await expandExpansionTileByKey(
          tester,
          _listKey,
          const Key('message-type-expansion-tile'),
        );
        await toggleFilterChipByKey(
          tester,
          _listKey,
          const Key('show-operator-comment-chip'),
        );

        expect(find.text('4 / 5 表示中'), findsOneWidget);
      },
    );

    testWidgets(
      'toggles emphasizeGiftNicoadComment and persists value (default ON)',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Default must be ON.
        AppSettings loaded = await settingsStore.load();
        expect(loaded.emphasizeGiftNicoadComment, isTrue);

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('emphasize-gift-nicoad-switch'),
        );
        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('emphasize-gift-nicoad-switch'),
        );

        loaded = await settingsStore.load();
        expect(loaded.emphasizeGiftNicoadComment, isFalse);
      },
    );

    testWidgets('disables statistics child toggles when parent toggle is off', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Parent is off by default; child toggles should be disabled.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-viewer-comment-switch'),
      );
      SwitchListTile viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNull);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-active-user-switch'),
      );
      SwitchListTile activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNull);

      // Turn on parent.
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('statistics-enabled-switch'),
      );

      // Child toggles should now be enabled.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-viewer-comment-switch'),
      );
      viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNotNull);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-active-user-switch'),
      );
      activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNotNull);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: CommentDisplaySettingsScreen(settingsStore: settingsStore),
  );
}
